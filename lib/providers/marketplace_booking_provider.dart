// =============================================================================
// AZAMAN — MARKETPLACE BOOKING PROVIDER (2026-07-02)
//
// Riverpod state management for the marketplace booking lifecycle.
// Uses AsyncNotifier pattern matching existing providers in the codebase.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/security/second_factor.dart';

// ── TRIP LIST ────────────────────────────────────────────────────────────────

final transitTripsProvider = FutureProvider.family<List<TransitTrip>, String?>((
  ref,
  businessProfileId,
) async {
  final svc = ref.watch(marketplaceBookingServiceProvider);
  return svc.listTrips(businessProfileId: businessProfileId);
});

// ── SEAT AVAILABILITY ────────────────────────────────────────────────────────

final seatAvailabilityProvider =
    FutureProvider.family<SeatAvailability, String>((ref, tripId) async {
      final svc = ref.watch(marketplaceBookingServiceProvider);
      return svc.getTripSeats(tripId);
    });

// ── SELECTED SEATS (interactive state) ───────────────────────────────────────

final selectedSeatsProvider = StateProvider<Set<String>>((ref) => {});

// ── CHECK-IN TOKEN ───────────────────────────────────────────────────────────

final checkInTokenProvider = FutureProvider.family<CheckInToken, String>((
  ref,
  reservationId,
) async {
  final svc = ref.watch(marketplaceBookingServiceProvider);
  return svc.generateCheckInQR(reservationId);
});

// ── BUSINESS STORIES ─────────────────────────────────────────────────────────

final businessStoriesProvider =
    FutureProvider.family<List<BusinessStory>, String>((
      ref,
      businessProfileId,
    ) async {
      final svc = ref.watch(marketplaceBookingServiceProvider);
      return svc.getBusinessStories(businessProfileId);
    });

// ── BOOKING ACTION STATE ─────────────────────────────────────────────────────

class BookingActionState {
  final bool isLoading;
  final String? error;

  /// Economic classification of the last [BookingActionNotifier.bookSeats]
  /// failure (§r42, 2026-10-01): tells the UI whether the outcome is
  /// UNPROVEN (the booking may have committed — warn and reconcile) or
  /// definitively pre-economic (the backend's own message is safe to
  /// surface verbatim). Null on success / while loading.
  final TransitBookingFailureClass? failureClass;
  final BookSeatResult? result;

  /// The server's own failure code when it sent one (INSUFFICIENT_BALANCE,
  /// KYC_REQUIRED, SELF_PAYMENT …), so the screen can answer the specific
  /// case (offer a top-up) instead of a generic message.
  final String? errorCode;

  const BookingActionState({
    this.isLoading = false,
    this.error,
    this.failureClass,
    this.result,
    this.errorCode,
  });

  BookingActionState copyWith({
    bool? isLoading,
    String? error,
    BookSeatResult? result,
  }) {
    return BookingActionState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      result: result ?? this.result,
    );
  }
}

class BookingActionNotifier extends StateNotifier<BookingActionState> {
  final MarketplaceBookingService _svc;
  BookingActionNotifier(this._svc) : super(const BookingActionState());

  Future<void> bookSeats({
    required String tripId,
    required List<String> seatIds,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
    String? operationType,
    FinancialOperationRef? ref,
  }) async {
    state = const BookingActionState(isLoading: true);
    try {
      final result = await _svc.bookSeats(
        tripId: tripId,
        seatIds: seatIds,
        passengerNames: passengerNames,
        customerNote: customerNote,
        businessProfileId: businessProfileId,
        operationType: operationType,
        ref: ref,
      );
      state = BookingActionState(result: result);
    } catch (e) {
      // Classify the failure's ECONOMIC class for the UI (§r42): the same
      // seat-selection retry with the same ref reuses the same durable key
      // on the wire, so the classification must never contradict the
      // identity lifecycle — it is a pure projection of the service's
      // classifyTransitBookingFailure, which reuses the SAME predicate as
      // the in-service disposition.
      state = BookingActionState(
        error: e.toString(),
        failureClass: MarketplaceBookingService.classifyTransitBookingFailure(
          e,
        ),
      );
    }
  }

  /// Books AND pays for the seats from the wallet, behind [secondFactor].
  ///
  /// A second-factor challenge or a refused factor is rethrown with the
  /// state back to idle, so the caller's prompt can ask again (the durable
  /// instance stays armed: a 401 retains it, and the retry reuses its key).
  /// Every other failure lands in state like [bookSeats], with its economic
  /// class and the server's code.
  Future<void> payForSeats({
    required String tripId,
    required List<String> seatIds,
    required SecondFactor secondFactor,
    required double expectedTotalUsdc,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
    String? operationType,
    FinancialOperationRef? ref,
  }) async {
    state = const BookingActionState(isLoading: true);
    try {
      final result = await _svc.bookSeats(
        tripId: tripId,
        seatIds: seatIds,
        passengerNames: passengerNames,
        customerNote: customerNote,
        businessProfileId: businessProfileId,
        operationType: operationType,
        ref: ref,
        payWithWallet: true,
        secondFactor: secondFactor,
        expectedTotalUsdc: expectedTotalUsdc,
      );
      state = BookingActionState(result: result);
    } catch (e) {
      if (secondFactorChallenge(e) != null || isSecondFactorRefused(e)) {
        state = const BookingActionState();
        rethrow;
      }
      state = BookingActionState(
        error: e is ApiException ? e.message : e.toString(),
        errorCode: e is ApiException ? e.code : null,
        failureClass: MarketplaceBookingService.classifyTransitBookingFailure(
          e,
        ),
      );
    }
  }

  Future<bool> cancelBooking(String bookingId) async {
    state = const BookingActionState(isLoading: true);
    try {
      final success = await _svc.cancelBooking(bookingId);
      state = const BookingActionState();
      return success;
    } catch (e) {
      state = BookingActionState(error: e.toString());
      return false;
    }
  }

  void reset() => state = const BookingActionState();
}

/// The wallet-pay quote for a selection: key is `tripId|1A,1B` (seats
/// sorted, so the same selection in any order shares one quote).
final transitPaymentQuoteProvider = FutureProvider.autoDispose
    .family<TransitPaymentQuote, String>((ref, key) {
      final sep = key.indexOf('|');
      final tripId = key.substring(0, sep);
      final seats = key.substring(sep + 1).split(',');
      return ref
          .watch(marketplaceBookingServiceProvider)
          .quoteSeats(tripId: tripId, seatIds: seats);
    });

String transitQuoteKey(String tripId, Iterable<String> seatIds) =>
    '$tripId|${(seatIds.toList()..sort()).join(',')}';

final bookingActionProvider =
    StateNotifierProvider<BookingActionNotifier, BookingActionState>(
      (ref) =>
          BookingActionNotifier(ref.watch(marketplaceBookingServiceProvider)),
    );

// ── CHECK-IN ACTION STATE (business side) ────────────────────────────────────

class CheckInActionState {
  final bool isLoading;
  final String? error;
  final CheckInResult? result;
  final AzamanIdSearchResult? searchResult;

  const CheckInActionState({
    this.isLoading = false,
    this.error,
    this.result,
    this.searchResult,
  });

  CheckInActionState copyWith({
    bool? isLoading,
    String? error,
    CheckInResult? result,
    AzamanIdSearchResult? searchResult,
  }) {
    return CheckInActionState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      result: result ?? this.result,
      searchResult: searchResult ?? this.searchResult,
    );
  }
}

class CheckInActionNotifier extends StateNotifier<CheckInActionState> {
  final MarketplaceBookingService _svc;
  CheckInActionNotifier(this._svc) : super(const CheckInActionState());

  Future<void> verifyToken(String token) async {
    state = const CheckInActionState(isLoading: true);
    try {
      final result = await _svc.verifyCheckInToken(token);
      state = CheckInActionState(result: result);
    } catch (e) {
      state = CheckInActionState(
        error: e.toString().replaceFirst('MarketplaceBookingException: ', ''),
      );
    }
  }

  Future<void> searchByAzamanId(String azamanId) async {
    state = const CheckInActionState(isLoading: true);
    try {
      final result = await _svc.searchByAzamanId(azamanId);
      state = CheckInActionState(searchResult: result);
    } catch (e) {
      state = CheckInActionState(
        error: e.toString().replaceFirst('MarketplaceBookingException: ', ''),
      );
    }
  }

  Future<void> directCheckIn(String reservationId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _svc.directCheckIn(reservationId);
      state = CheckInActionState(result: result);
    } catch (e) {
      state = CheckInActionState(
        error: e.toString().replaceFirst('MarketplaceBookingException: ', ''),
      );
    }
  }

  void reset() => state = const CheckInActionState();
}

final checkInActionProvider =
    StateNotifierProvider<CheckInActionNotifier, CheckInActionState>(
      (ref) =>
          CheckInActionNotifier(ref.watch(marketplaceBookingServiceProvider)),
    );

// ── MARKETPLACE BOOKING NOTIFIER ─────────────────────────────────────────────

class MarketplaceBookingState {
  final bool isLoading;
  final String? error;
  final BusinessProfile? business;
  final List<dynamic> products;
  final dynamic dineInTab;

  const MarketplaceBookingState({
    this.isLoading = false,
    this.error,
    this.business,
    this.products = const [],
    this.dineInTab,
  });

  MarketplaceBookingState copyWith({
    bool? isLoading,
    String? error,
    BusinessProfile? business,
    List<dynamic>? products,
    dynamic dineInTab,
  }) {
    return MarketplaceBookingState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      business: business ?? this.business,
      products: products ?? this.products,
      dineInTab: dineInTab ?? this.dineInTab,
    );
  }
}

class MarketplaceBookingNotifier
    extends StateNotifier<MarketplaceBookingState> {
  final MarketplaceBookingService _service;
  MarketplaceBookingNotifier(this._service)
    : super(const MarketplaceBookingState());

  // Load business detail with products (rooms/menu) and showcase
  Future<void> loadBusinessDetail(String bizId) async {
    state = state.copyWith(isLoading: true);
    try {
      final result = await _service.fetchBusinessDetail(bizId);
      state = state.copyWith(
        isLoading: false,
        business: result.business,
        products: result.products,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // Load dine-in tab
  Future<void> loadDineInTab(String tabId) async {
    state = state.copyWith(isLoading: true);
    try {
      final tab = await _service.fetchDineInTab(tabId);
      state = state.copyWith(isLoading: false, dineInTab: tab);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final marketplaceBookingProvider =
    StateNotifierProvider<MarketplaceBookingNotifier, MarketplaceBookingState>(
      (ref) => MarketplaceBookingNotifier(
        ref.watch(marketplaceBookingServiceProvider),
      ),
    );

// ── TRIP DETAIL (single trip by ID) ──────────────────────────────────────────
/// Fetches all trips and finds the one matching [tripId].
/// Used by the seat selection screen to show trip info in the booking success sheet.
final tripDetailProvider = FutureProvider.family<TransitTrip?, String>((
  ref,
  tripId,
) async {
  final svc = ref.watch(marketplaceBookingServiceProvider);
  final trips = await svc.listTrips();
  return trips.where((t) => t.id == tripId).firstOrNull;
});
