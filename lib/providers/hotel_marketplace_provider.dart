import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart';

final hotelMarketplaceServiceProvider = Provider<HotelMarketplaceService>(
  (ref) => HotelMarketplaceService(),
);

class HotelMarketplaceState {
  final bool isLoading;
  final bool isBooking;
  final String? error;
  final HotelBookingFailureClass? bookingFailureClass;
  final BusinessProfile? business;
  final List<HotelRoom> rooms;

  const HotelMarketplaceState({
    this.isLoading = false,
    this.isBooking = false,
    this.error,
    this.bookingFailureClass,
    this.business,
    this.rooms = const [],
  });

  HotelMarketplaceState copyWith({
    bool? isLoading,
    bool? isBooking,
    String? error,
    HotelBookingFailureClass? bookingFailureClass,
    BusinessProfile? business,
    List<HotelRoom>? rooms,
    bool clearError = false,
  }) {
    return HotelMarketplaceState(
      isLoading: isLoading ?? this.isLoading,
      isBooking: isBooking ?? this.isBooking,
      error: clearError ? null : (error ?? this.error),
      bookingFailureClass: clearError
          ? null
          : (bookingFailureClass ?? this.bookingFailureClass),
      business: business ?? this.business,
      rooms: rooms ?? this.rooms,
    );
  }
}

class HotelMarketplaceNotifier extends StateNotifier<HotelMarketplaceState> {
  final HotelMarketplaceService _service;
  HotelMarketplaceNotifier(this._service)
    : super(const HotelMarketplaceState());

  Future<void> load(String bizId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final detail = await _service.fetchHotel(bizId);
      state = HotelMarketplaceState(
        business: detail.business,
        rooms: detail.rooms,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Map<String, dynamic>> reserve({
    required String bizId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    int partySize = 1,
    String? operationType,
    FinancialOperationRef? ref,
    bool payWithWallet = false,
    double? expectedTotalUsdc,
    Map<String, String>? secondFactor,
  }) async {
    state = state.copyWith(isBooking: true, clearError: true);
    try {
      final reservation = await _service.reserve(
        bizId: bizId,
        roomId: roomId,
        checkIn: checkIn,
        checkOut: checkOut,
        partySize: partySize,
        operationType: operationType,
        ref: ref,
        payWithWallet: payWithWallet,
        expectedTotalUsdc: expectedTotalUsdc,
        secondFactor: secondFactor,
      );
      state = state.copyWith(isBooking: false);
      return reservation;
    } catch (e) {
      // Classify the failure's ECONOMIC class for the UI (deep-dive step 6):
      // pure projection of the service's classifyHotelReservationFailure,
      // which reuses the SAME disposition predicate as the identity
      // lifecycle — the class can never contradict armed/retired state.
      state = state.copyWith(
        isBooking: false,
        error: e.toString(),
        bookingFailureClass:
            HotelMarketplaceService.classifyHotelReservationFailure(e),
      );
      rethrow;
    }
  }
}

final hotelMarketplaceProvider =
    StateNotifierProvider<HotelMarketplaceNotifier, HotelMarketplaceState>(
      (ref) =>
          HotelMarketplaceNotifier(ref.watch(hotelMarketplaceServiceProvider)),
    );

/// The quote for one stay request: `bizId|yyyy-mm-dd|yyyy-mm-dd|guests`.
String stayQuoteKey(
  String bizId,
  DateTime checkIn,
  DateTime checkOut,
  int guests,
) {
  String d(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  return '$bizId|${d(checkIn)}|${d(checkOut)}|$guests';
}

final stayQuoteProvider = FutureProvider.autoDispose.family<StayQuote, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  DateTime day(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  return ref
      .watch(hotelMarketplaceServiceProvider)
      .stayQuote(
        bizId: parts[0],
        checkIn: day(parts[1]),
        checkOut: day(parts[2]),
        guests: int.parse(parts[3]),
      );
});
