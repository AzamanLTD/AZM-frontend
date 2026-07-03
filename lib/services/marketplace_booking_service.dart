// =============================================================================
// AZAMAN — MARKETPLACE BOOKING SERVICE (2026-07-02)
//
// REST client for the new /api/marketplace endpoints:
//   - QR check-in (generate, verify, AZM-ID search)
//   - Transit trips (list, seat availability, book seats, cancel)
//   - Review → Story promotion
//   - No-show penalty policy
//   - Transit trip + seat map management
//
// Uses the existing ApiClient pattern from business_service.dart.
// =============================================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/marketplace_booking_models.dart';

// ── PROVIDER ─────────────────────────────────────────────────────────────────

final marketplaceBookingServiceProvider =
    Provider<MarketplaceBookingService>((ref) => MarketplaceBookingService());

// ── EXCEPTION ────────────────────────────────────────────────────────────────

class MarketplaceBookingException implements Exception {
  final String message;
  final int? statusCode;
  MarketplaceBookingException(this.message, {this.statusCode
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});

  @override
  String toString() => 'MarketplaceBookingException: $message';

  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

// ── SERVICE ──────────────────────────────────────────────────────────────────

class MarketplaceBookingService {
  final ApiClient _client = ApiClient();

  // ── QR CHECK-IN ────────────────────────────────────────────────────────────

  /// Generate a QR check-in token for a reservation (customer-side).
  Future<CheckInToken> generateCheckInQR(String reservationId) async {
    final res = await _client.get('/marketplace/reservations/$reservationId/checkin-qr');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to generate QR');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return CheckInToken.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Business scans QR token to check in a customer.
  Future<CheckInResult> verifyCheckInToken(String token) async {
    final res = await _client.post('/marketplace/business/checkin', {'token': token
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Check-in failed');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return CheckInResult.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Business searches by AZM-ID (manual fallback when scanner is down).
  Future<AzamanIdSearchResult> searchByAzamanId(String azamanId) async {
    final res = await _client.post('/marketplace/business/checkin', {'azamanId': azamanId
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Search failed');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return AzamanIdSearchResult.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Direct check-in by reservationId (from search results).
  Future<CheckInResult> directCheckIn(String reservationId) async {
    final res = await _client.post('/marketplace/business/checkin', {'reservationId': reservationId
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Check-in failed');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return CheckInResult.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  // ── TRANSIT TRIPS ──────────────────────────────────────────────────────────

  /// List available transit trips.
  Future<List<TransitTrip>> listTrips({String? businessProfileId, String? status
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}) async {
    final params = <String, String>{
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

};
    if (businessProfileId != null) params['businessProfileId'] = businessProfileId;
    if (status != null) params['status'] = status;
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}=${e.value
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}').join('&')
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}' : '';
    final res = await _client.get('/marketplace/transit/trips$query');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to load trips');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    final trips = body['trips'] as List? ?? [];
    return trips.map((t) => TransitTrip.fromJson(t as Map<String, dynamic>)).toList();
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Get seat availability for a trip.
  Future<SeatAvailability> getTripSeats(String tripId) async {
    final res = await _client.get('/marketplace/transit/trips/$tripId/seats');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to load seats');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return SeatAvailability.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Book seats on a trip.
  Future<BookSeatResult> bookSeats({
    required String tripId,
    required List<String> seatIds,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}) async {
    final res = await _client.post('/marketplace/transit/trips/$tripId/book', {
      'seatIds': seatIds,
      'passengerNames': passengerNames,
      'customerNote': customerNote,
      'businessProfileId': businessProfileId,
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Booking failed');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return BookSeatResult.fromJson(body);
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Cancel a transit booking.
  Future<bool> cancelBooking(String bookingId) async {
    final res = await _client.delete('/marketplace/transit/bookings/$bookingId');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Transit check-in (business side).
  Future<bool> transitCheckIn(String bookingId) async {
    final res = await _client.post('/marketplace/transit/bookings/$bookingId/checkin', {
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  // ── REVIEW → STORY ─────────────────────────────────────────────────────────

  /// Promote a review to a story.
  Future<bool> promoteReviewToStory(String reviewId) async {
    final res = await _client.post('/marketplace/reviews/$reviewId/share-story', {
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Get business stories (viral loop).
  Future<List<BusinessStory>> getBusinessStories(String businessProfileId) async {
    final res = await _client.get('/marketplace/business/$businessProfileId/stories');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final stories = body['stories'] as List? ?? [];
    return stories.map((s) => BusinessStory.fromJson(s as Map<String, dynamic>)).toList();
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  // ── NO-SHOW PENALTY POLICY ─────────────────────────────────────────────────

  /// Set no-show penalty policy for a reservation or transit booking.
  Future<bool> setPenaltyPolicy({
    String? reservationId,
    String? transitBookingId,
    double? noShowPenaltyPct,
    double? noShowPenaltyUsdc,
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}) async {
    final body = <String, dynamic>{
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

};
    if (reservationId != null) body['reservationId'] = reservationId;
    if (transitBookingId != null) body['transitBookingId'] = transitBookingId;
    if (noShowPenaltyPct != null) body['noShowPenaltyPct'] = noShowPenaltyPct;
    if (noShowPenaltyUsdc != null) body['noShowPenaltyUsdc'] = noShowPenaltyUsdc;
    final res = await _client.patch('/marketplace/business/penalty-policy', body: body);
    final respBody = jsonDecode(res.body) as Map<String, dynamic>;
    return respBody['success'] == true;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  // ── TRANSIT TRIP MANAGEMENT (business portal) ──────────────────────────────

  /// Create a scheduled transit trip.
  Future<Map<String, dynamic>> createTrip({
    required String vehicleId,
    required String routeName,
    required String origin,
    required String destination,
    required String departureAt,
    String? arrivalAt,
    required double fareUsdc,
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}) async {
    final res = await _client.post('/marketplace/business/trips', {
      'vehicleId': vehicleId,
      'routeName': routeName,
      'origin': origin,
      'destination': destination,
      'departureAt': departureAt,
      'arrivalAt': arrivalAt,
      'fareUsdc': fareUsdc,
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to create trip');
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}
    return body['trip'] as Map<String, dynamic>;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  /// Create or update a vehicle's seat map.
  Future<bool> setSeatMap({
    required String vehicleId,
    required List<Map<String, dynamic>> layout,
    required int rows,
    required int cols,
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}) async {
    final res = await _client.post('/marketplace/business/seat-map', {
      'vehicleId': vehicleId,
      'layout': layout,
      'rows': rows,
      'cols': cols,
    
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  
  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}

  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _api.get('/business-market/$bizId');
    return (
      business: BusinessProfile.fromJson(res['data']['business']),
      products: (res['data']['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _api.post('/business-market/$bizId/reservations', body: {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return res['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _api.get('/business-market/dine-in/$tabId');
    return res['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _api.post('/business-market/dine-in/$tabId/confirm');
  }

}


Providers
