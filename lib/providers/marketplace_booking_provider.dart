// =============================================================================
// AZAMAN — MARKETPLACE BOOKING PROVIDER (2026-07-02)
//
// Riverpod state management for the marketplace booking lifecycle.
// Uses AsyncNotifier pattern matching existing providers in the codebase.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/models/business_models.dart';

// ── TRIP LIST ────────────────────────────────────────────────────────────────

final transitTripsProvider =
    FutureProvider.family<List<TransitTrip>, String?>((ref, businessProfileId) async {
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

final checkInTokenProvider =
    FutureProvider.family<CheckInToken, String>((ref, reservationId) async {
  final svc = ref.watch(marketplaceBookingServiceProvider);
  return svc.generateCheckInQR(reservationId);
});

// ── BUSINESS STORIES ─────────────────────────────────────────────────────────

final businessStoriesProvider =
    FutureProvider.family<List<BusinessStory>, String>((ref, businessProfileId) async {
  final svc = ref.watch(marketplaceBookingServiceProvider);
  return svc.getBusinessStories(businessProfileId);
});

// ── BOOKING ACTION STATE ─────────────────────────────────────────────────────

class BookingActionState {
  final bool isLoading;
  final String? error;
  final BookSeatResult? result;

  const BookingActionState({this.isLoading = false, this.error, this.result});

  BookingActionState copyWith({bool? isLoading, String? error, BookSeatResult? result}) {
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
  }) async {
    state = const BookingActionState(isLoading: true);
    try {
      final result = await _svc.bookSeats(
        tripId: tripId,
        seatIds: seatIds,
        passengerNames: passengerNames,
        customerNote: customerNote,
        businessProfileId: businessProfileId,
      );
      state = BookingActionState(result: result);
    } catch (e) {
      state = BookingActionState(error: e.toString());
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

final bookingActionProvider =
    StateNotifierProvider<BookingActionNotifier, BookingActionState>(
  (ref) => BookingActionNotifier(ref.watch(marketplaceBookingServiceProvider)),
);

// ── CHECK-IN ACTION STATE (business side) ────────────────────────────────────

class CheckInActionState {
  final bool isLoading;
  final String? error;
  final CheckInResult? result;
  final AzamanIdSearchResult? searchResult;

  const CheckInActionState({this.isLoading = false, this.error, this.result, this.searchResult});

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
      state = CheckInActionState(error: e.toString().replaceFirst('MarketplaceBookingException: ', ''));
    }
  }

  Future<void> searchByAzamanId(String azamanId) async {
    state = const CheckInActionState(isLoading: true);
    try {
      final result = await _svc.searchByAzamanId(azamanId);
      state = CheckInActionState(searchResult: result);
    } catch (e) {
      state = CheckInActionState(error: e.toString().replaceFirst('MarketplaceBookingException: ', ''));
    }
  }

  Future<void> directCheckIn(String reservationId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _svc.directCheckIn(reservationId);
      state = CheckInActionState(result: result);
    } catch (e) {
      state = CheckInActionState(error: e.toString().replaceFirst('MarketplaceBookingException: ', ''));
    }
  }

  void reset() => state = const CheckInActionState();
}

final checkInActionProvider =
    StateNotifierProvider<CheckInActionNotifier, CheckInActionState>(
  (ref) => CheckInActionNotifier(ref.watch(marketplaceBookingServiceProvider)),
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

class MarketplaceBookingNotifier extends StateNotifier<MarketplaceBookingState> {
  final MarketplaceBookingService _service;
  MarketplaceBookingNotifier(this._service) : super(const MarketplaceBookingState());

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

  // Create hotel reservation with escrow
  Future<dynamic> createHotelReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final booking = await _service.createReservation(
      bizId: bizId,
      checkIn: checkIn,
      checkOut: checkOut,
      productId: productId,
    );
    return booking;
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

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _service.confirmDineInTab(tabId);
  }
}

final marketplaceBookingProvider = StateNotifierProvider<MarketplaceBookingNotifier, MarketplaceBookingState>(
  (ref) => MarketplaceBookingNotifier(ref.watch(marketplaceBookingServiceProvider)),
);
