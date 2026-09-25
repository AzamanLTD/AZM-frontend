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
import 'package:azaman/models/business_models.dart';

// ── PROVIDER ─────────────────────────────────────────────────────────────────

final marketplaceBookingServiceProvider =
    Provider<MarketplaceBookingService>((ref) => MarketplaceBookingService());

// ── EXCEPTION ────────────────────────────────────────────────────────────────

class MarketplaceBookingException implements Exception {
  final String message;
  final int? statusCode;
  MarketplaceBookingException(this.message, {this.statusCode});

  @override
  String toString() => 'MarketplaceBookingException: $message';
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
    }
    return CheckInToken.fromJson(body);
  }

  /// Business scans QR token to check in a customer.
  Future<CheckInResult> verifyCheckInToken(String token) async {
    final res = await _client.post('/marketplace/business/checkin', {'token': token});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Check-in failed');
    }
    return CheckInResult.fromJson(body);
  }

  /// Business searches by AZM-ID (manual fallback when scanner is down).
  Future<AzamanIdSearchResult> searchByAzamanId(String azamanId) async {
    final res = await _client.post('/marketplace/business/checkin', {'azamanId': azamanId});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Search failed');
    }
    return AzamanIdSearchResult.fromJson(body);
  }

  /// Direct check-in by reservationId (from search results).
  Future<CheckInResult> directCheckIn(String reservationId) async {
    final res = await _client.post('/marketplace/business/checkin', {'reservationId': reservationId});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Check-in failed');
    }
    return CheckInResult.fromJson(body);
  }

  // ── TRANSIT TRIPS ──────────────────────────────────────────────────────────

  /// List available transit trips.
  Future<List<TransitTrip>> listTrips({String? businessProfileId, String? status}) async {
    final params = <String, String>{};
    if (businessProfileId != null) params['businessProfileId'] = businessProfileId;
    if (status != null) params['status'] = status;
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
    final res = await _client.get('/marketplace/transit/trips$query');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to load trips');
    }
    final trips = body['trips'] as List? ?? [];
    return trips.map((t) => TransitTrip.fromJson(t as Map<String, dynamic>)).toList();
  }

  /// Get seat availability for a trip.
  Future<SeatAvailability> getTripSeats(String tripId) async {
    final res = await _client.get('/marketplace/transit/trips/$tripId/seats');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to load seats');
    }
    return SeatAvailability.fromJson(body);
  }

  /// Book seats on a trip.
  Future<BookSeatResult> bookSeats({
    required String tripId,
    required List<String> seatIds,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
  }) async {
    final res = await _client.post('/marketplace/transit/trips/$tripId/book', {
      'seatIds': seatIds,
      'passengerNames': passengerNames,
      'customerNote': customerNote,
      'businessProfileId': businessProfileId,
    });
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Booking failed');
    }
    return BookSeatResult.fromJson(body);
  }

  /// Cancel a transit booking.
  Future<bool> cancelBooking(String bookingId) async {
    final res = await _client.delete('/marketplace/transit/bookings/$bookingId');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  }

  /// Transit check-in (business side).
  Future<bool> transitCheckIn(String bookingId) async {
    final res = await _client.post('/marketplace/transit/bookings/$bookingId/checkin', {});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  }

  // ── REVIEW → STORY ─────────────────────────────────────────────────────────

  /// Promote a review to a story.
  Future<bool> promoteReviewToStory(String reviewId) async {
    final res = await _client.post('/marketplace/reviews/$reviewId/share-story', {});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  }

  /// Get business stories (viral loop).
  Future<List<BusinessStory>> getBusinessStories(String businessProfileId) async {
    final res = await _client.get('/marketplace/business/$businessProfileId/stories');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final stories = body['stories'] as List? ?? [];
    return stories.map((s) => BusinessStory.fromJson(s as Map<String, dynamic>)).toList();
  }

  // ── NO-SHOW PENALTY POLICY ─────────────────────────────────────────────────

  /// Set no-show penalty policy for a reservation or transit booking.
  Future<bool> setPenaltyPolicy({
    String? reservationId,
    String? transitBookingId,
    double? noShowPenaltyPct,
    double? noShowPenaltyUsdc,
  }) async {
    final body = <String, dynamic>{};
    if (reservationId != null) body['reservationId'] = reservationId;
    if (transitBookingId != null) body['transitBookingId'] = transitBookingId;
    if (noShowPenaltyPct != null) body['noShowPenaltyPct'] = noShowPenaltyPct;
    if (noShowPenaltyUsdc != null) body['noShowPenaltyUsdc'] = noShowPenaltyUsdc;
    final res = await _client.patch('/marketplace/business/penalty-policy', body: body);
    final respBody = jsonDecode(res.body) as Map<String, dynamic>;
    return respBody['success'] == true;
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
  }) async {
    final res = await _client.post('/marketplace/business/trips', {
      'vehicleId': vehicleId,
      'routeName': routeName,
      'origin': origin,
      'destination': destination,
      'departureAt': departureAt,
      'arrivalAt': arrivalAt,
      'fareUsdc': fareUsdc,
    });
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw MarketplaceBookingException(body['message'] ?? 'Failed to create trip');
    }
    return body['trip'] as Map<String, dynamic>;
  }

  /// Create or update a vehicle's seat map.
  Future<bool> setSeatMap({
    required String vehicleId,
    required List<Map<String, dynamic>> layout,
    required int rows,
    required int cols,
  }) async {
    final res = await _client.post('/marketplace/business/seat-map', {
      'vehicleId': vehicleId,
      'layout': layout,
      'rows': rows,
      'cols': cols,
    });
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['success'] == true;
  }

  // Fetch business detail with products and showcase
  Future<({BusinessProfile business, List<dynamic> products})> fetchBusinessDetail(String bizId) async {
    final res = await _client.get('/marketplace/business/$bizId');
    final data = jsonDecode(res.body)['data'];
    return (
      business: BusinessProfile.fromJson(data['business']),
      products: (data['products'] as List).toList(),
    );
  }

  // Create hotel reservation
  Future<dynamic> createReservation({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required String productId,
  }) async {
    final res = await _client.post('/marketplace/business/$bizId/reservations', {
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'productId': productId,
    });
    return jsonDecode(res.body)['data'];
  }

  // Fetch dine-in tab
  Future<dynamic> fetchDineInTab(String tabId) async {
    final res = await _client.get('/marketplace/business/dine-in/$tabId');
    return jsonDecode(res.body)['data'];
  }

  // Confirm and pay dine-in tab
  Future<void> confirmDineInTab(String tabId) async {
    await _client.post('/marketplace/business/dine-in/$tabId/confirm', {});
  }
}

