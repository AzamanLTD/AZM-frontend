import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/hotel_marketplace_service.dart';

final hotelMarketplaceServiceProvider = Provider<HotelMarketplaceService>(
  (ref) => HotelMarketplaceService(),
);

class HotelMarketplaceState {
  final bool isLoading;
  final bool isBooking;
  final String? error;
  final BusinessProfile? business;
  final List<HotelRoom> rooms;

  const HotelMarketplaceState({
    this.isLoading = false,
    this.isBooking = false,
    this.error,
    this.business,
    this.rooms = const [],
  });

  HotelMarketplaceState copyWith({
    bool? isLoading,
    bool? isBooking,
    String? error,
    BusinessProfile? business,
    List<HotelRoom>? rooms,
    bool clearError = false,
  }) {
    return HotelMarketplaceState(
      isLoading: isLoading ?? this.isLoading,
      isBooking: isBooking ?? this.isBooking,
      error: clearError ? null : (error ?? this.error),
      business: business ?? this.business,
      rooms: rooms ?? this.rooms,
    );
  }
}

class HotelMarketplaceNotifier extends StateNotifier<HotelMarketplaceState> {
  final HotelMarketplaceService _service;
  HotelMarketplaceNotifier(this._service) : super(const HotelMarketplaceState());

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
  }) async {
    state = state.copyWith(isBooking: true, clearError: true);
    try {
      final reservation = await _service.reserve(
        bizId: bizId,
        roomId: roomId,
        checkIn: checkIn,
        checkOut: checkOut,
        partySize: partySize,
      );
      state = state.copyWith(isBooking: false);
      return reservation;
    } catch (e) {
      state = state.copyWith(isBooking: false, error: e.toString());
      rethrow;
    }
  }
}

final hotelMarketplaceProvider = StateNotifierProvider<HotelMarketplaceNotifier, HotelMarketplaceState>(
  (ref) => HotelMarketplaceNotifier(ref.watch(hotelMarketplaceServiceProvider)),
);
