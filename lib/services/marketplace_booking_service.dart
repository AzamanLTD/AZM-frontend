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
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:azaman/data/demo_interceptor.dart';
import 'package:azaman/config.dart';
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

// ── TRANSIT BOOKING FAILURE CLASSIFICATION (§r42, 2026-10-01) ────────────────
//
// Deep-dive step 5 found transit seat booking had NO durable identity and
// NO failure classification: a booking that committed while its HTTP
// response was lost turned the customer's same-seat retry into an
// indistinguishable 'Seats already booked' (their own committed seats vs
// another customer's), and the UI asserted a generic 'Booking failed' on
// every error — even an ambiguous transport loss where the booking MAY
// have gone through.
//
// This classification is a read-only projection for the UI, mirroring the
// storefront taxonomy adopted in the retail checkout deep-dive (step 2).
// It NEVER decides the durable identity lifecycle — the in-method
// disposition and DurableOperationRegistry own that (parity with
// ApiClient.postFinancial / StorefrontService.checkoutCart).
//
// Traced wire semantics (AZM-backend routes/marketplaceRoutes.js +
// middleware/idempotency.js, 2026-10-01):
// - 401: protect / require2FA reject BEFORE any booking mutation (auth
//   runs ahead of the idempotency claim). Re-auth, then retry the SAME
//   logical operation (instance stays armed, same key).
// - 409: IDEMPOTENCY_PAYLOAD_CONFLICT — the durable key was already used
//   with a DIFFERENT seat selection. The registry gives a materially
//   changed selection its OWN key, so a 409 on the wire is a reconciliation
//   signal: check your bookings before booking again.
// - 400/403/404: the backend's explicit pre-economic validations (empty
//   seats, trip not found, seats taken by another customer). Residual gap
//   (same as storefront, recorded): the controller catch-all also surfaces
//   uncaught internal errors as 400 with no machine-readable code — in
//   current source every such throw precedes the booking commit, so 400
//   stays de-facto pre-economic, but that contract is implicit.
// - 408 / 425 / 429 / 5xx / transport loss / malformed 2xx payload: the
//   economic outcome is UNPROVEN — the booking MAY have committed. Fail
//   safe as ambiguousOrUnknown; the instance stays ARMED and a retry of
//   the SAME seat selection reuses the SAME key so the backend converges
//   (exact replay of the committed booking) instead of duplicating.
enum TransitBookingFailureClass {
  definitivePreEconomic,
  authenticationRequired,
  rateLimited,
  domainConflict,
  ambiguousOrUnknown,
}

extension TransitBookingFailureClassIsUnconfirmed
    on TransitBookingFailureClass {
  /// True when the economic outcome is UNPROVEN — the booking may have
  /// committed. The UI must warn (check your bookings) instead of asserting
  /// the booking definitely failed.
  bool get isUnconfirmed => this == TransitBookingFailureClass.ambiguousOrUnknown;
}

// ── SERVICE ──────────────────────────────────────────────────────────────────

class MarketplaceBookingService {
  MarketplaceBookingService({ApiClient? apiClient})
      : _client = apiClient ?? ApiClient();
  final ApiClient _client;

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
  ///
  /// The [operationType] + [ref] pair is the durable identity path (§r42,
  /// 2026-10-01): ONE logical seat-booking intent → ONE durable identity
  /// per (account, endpoint, key). A retry of the SAME seat selection
  /// (same ref, matching fingerprint) reuses the SAME key so the backend
  /// converges on the same booking (exact replay of the committed
  /// response) instead of duplicating; a materially changed selection
  /// begins a GENUINELY NEW instance (the old unfinished record stays
  /// recoverable in the journal). Mirrors the contract of
  /// [StorefrontService.checkoutCart] / [ApiClient.postFinancial].
  ///
  /// Without [operationType] the call is the legacy unkeyed path: plain
  /// transport, no journal, no recovery — the DB-level
  /// `TransitBookingSeat @@unique([tripId, seatId])` still prevents
  /// duplicate seat claims structurally, so a keyless request keeps today's
  /// behavior (the exposure is reconciliation UX only, not duplicate
  /// economics).
  Future<BookSeatResult> bookSeats({
    required String tripId,
    required List<String> seatIds,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
    String? operationType,
    FinancialOperationRef? ref,
  }) async {
    final endpoint = '/marketplace/transit/trips/$tripId/book';
    final body = <String, dynamic>{
      'seatIds': seatIds,
      'passengerNames': passengerNames,
      'customerNote': customerNote,
      'businessProfileId': businessProfileId,
    };

    if (operationType == null) {
      // Legacy unkeyed path: no durable lifecycle — plain transport.
      final res = await _client.post(endpoint, body);
      final parsed = jsonDecode(res.body) as Map<String, dynamic>;
      if (parsed['success'] != true) {
        throw MarketplaceBookingException(parsed['message'] ?? 'Booking failed');
      }
      return BookSeatResult.fromJson(parsed);
    }

    // Demo mode short-circuits before economics: no durable entry needed
    // (the SAME policy as [ApiClient.postFinancial]). The demo book
    // response is not the authoritative wire shape, so it must never flow
    // through the durable instance or the malformed-success guard — it
    // keeps today's legacy parse exactly. An endpoint the demo interceptor
    // does not handle falls through to the real durable path below.
    if (AppConfig.demoMode) {
      final m = DemoInterceptor.tryPost(endpoint, body);
      if (m != null) {
        final parsed = jsonDecode(m.body) as Map<String, dynamic>;
        if (parsed['success'] != true) {
          throw MarketplaceBookingException(
              parsed['message'] ?? 'Booking failed');
        }
        return BookSeatResult.fromJson(parsed);
      }
    }

    // r42 OPERATION-INSTANCE MODEL (parity with StorefrontService.checkoutCart):
    // resolve the durable instance from the ref-bound journal — retry the
    // ref's unfinished instance when the seat selection matches its
    // fingerprint, begin a genuinely new one otherwise. Arm the caller's
    // ref BEFORE the request leaves the device so a failure here is a RETRY
    // of this instance on the caller's next attempt.
    final op = await _resolveOperation(
        type: operationType, endpoint: endpoint, request: body, ref: ref);
    try {
      final res = await _client.post(endpoint, body,
          headers: {'Idempotency-Key': op.key});
      final parsed = jsonDecode(res.body) as Map<String, dynamic>;
      // Malformed-success guard (deep-dive step 2, parity with checkoutCart):
      // an answered 2xx that does not carry an AUTHORITATIVE booking —
      // success:true AND a non-empty booking id + bookingRef, the minimum
      // shape the backend guarantees on BOTH the fresh 201 and the exact
      // replay 201 — is an UNKNOWN economic state. Never surface it as
      // success (the caller would confirm an unconfirmed booking) and never
      // as a definitive failure. The FormatException stays OUTSIDE every
      // disposition clause → the durable instance stays armed for a
      // same-key retry; classifyTransitBookingFailure maps it to
      // ambiguousOrUnknown.
      if (!_carriesAuthoritativeBooking(parsed)) {
        throw const FormatException(
            'Booking response was successful but carried no authoritative '
            'booking result (id/bookingRef).');
      }
      // Answered success — this booking instance is complete.
      await _releaseOperation(ref);
      return BookSeatResult.fromJson(parsed);
    } on ApiException catch (e) {
      // Disposition mirrors postFinancial / checkoutCart: definitive
      // pre-economic 4xx (everything except 401/408/409/425/429) → the
      // instance is terminal; the backend released the claim.
      // 401/408/409/425/429 (and every 5xx and transport loss) → retained
      // (the booking may be committed/in-flight; a same-key retry
      // converges). ApiClient.post throws ApiException for every non-2xx
      // before this service parses anything (2026-10-01 recovery audit).
      if (_isDefinitivePreEconomic(e.statusCode)) {
        await _releaseOperation(ref);
      }
      rethrow;
    }
  }

  // ── DURABLE IDENTITY HELPERS (parity with StorefrontService) ───────────────

  /// Resolves the durable operation instance for a service-owned booking
  /// flow (the SAME policy as [ApiClient.postFinancial]): retry the ref's
  /// instance when it is still pending and the body matches its recorded
  /// fingerprint; otherwise begin a GENUINELY NEW instance (the old record
  /// stays untouched and recoverable — never silently replaced).
  Future<DurableOperation> _resolveOperation({
    required String type,
    required String endpoint,
    required Map<String, dynamic> request,
    FinancialOperationRef? ref,
  }) async {
    final account = await _client.operationAccount(failClosed: true);
    final retryId = ref?.operationId;
    if (retryId != null) {
      try {
        return await DurableOperationRegistry.retry(retryId,
            account: account, request: request);
      } on DurableOperationException {
        // Not retryable as that instance (terminal, or a materially
        // different request): a genuinely new action.
      }
    }
    final op = await DurableOperationRegistry.begin(
        account: account, type: type, endpoint: endpoint, request: request);
    if (ref != null) ref.operationId = op.operationId;
    return op;
  }

  /// Terminal completion / definitive pre-economic release of the ref's
  /// instance: retires THAT instance only and clears the ref.
  Future<void> _releaseOperation(FinancialOperationRef? ref) async {
    final id = ref?.operationId;
    if (id == null) return;
    await DurableOperationRegistry.retire(id,
        account: await _client.operationAccount(failClosed: true));
    if (ref != null) ref.operationId = null;
  }

  /// Minimum authoritative booking shape guaranteed by the backend on BOTH
  /// success paths (fresh 201 and exact replay 201): `success:true` AND a
  /// non-empty string `booking.id` AND a non-empty string `booking.bookingRef`
  /// (both generated at commit in transitBookingService.bookSeats). Anything
  /// less is NOT a confirmed booking: treat as malformed success → the
  /// caller never claims completion, the durable instance stays armed.
  static bool _carriesAuthoritativeBooking(Map<String, dynamic> parsed) {
    if (parsed['success'] != true) return false;
    final booking = parsed['booking'];
    if (booking is! Map<String, dynamic>) return false;
    final id = booking['id'];
    final bookingRef = booking['bookingRef'];
    return id is String &&
        id.isNotEmpty &&
        bookingRef is String &&
        bookingRef.isNotEmpty;
  }

  /// r42 disposition predicate (parity with StorefrontService): definitive
  /// pre-economic 4xx — everything except 401 / 408 / 409 / 425 / 429 —
  /// releases the ref's instance; every other answered outcome (and every
  /// transport loss) stays armed for a same-key retry. 408 (request timeout)
  /// and 425 (too early) are EXCLUDED from terminal disposition: an answered
  /// 408/425 does not prove the backend never received the request (a
  /// proxy/gateway can answer after the upstream commit), so the safe
  /// default keeps the instance ARMED.
  static bool _isDefinitivePreEconomic(int statusCode) =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 401 &&
      statusCode != 408 &&
      statusCode != 409 &&
      statusCode != 425 &&
      statusCode != 429;

  /// Maps a thrown failure of the durable seat-booking path to its economic
  /// class. Pure projection: reuses the SAME definitive predicate as the
  /// disposition ([_isDefinitivePreEconomic]), so the classification can
  /// never contradict the identity lifecycle.
  static TransitBookingFailureClass classifyTransitBookingFailure(
      Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return TransitBookingFailureClass.authenticationRequired;
      }
      if (error.statusCode == 429) return TransitBookingFailureClass.rateLimited;
      if (error.statusCode == 409) return TransitBookingFailureClass.domainConflict;
      if (_isDefinitivePreEconomic(error.statusCode)) {
        return TransitBookingFailureClass.definitivePreEconomic;
      }
      return TransitBookingFailureClass.ambiguousOrUnknown; // 5xx / other
    }
    // FormatException (malformed 2xx payload), TimeoutException, http
    // ClientException / SocketException, and anything unrecognized: the
    // economic outcome is UNPROVEN. Fail safe as unknown — never "safe to
    // retry blindly", never "definitive".
    return TransitBookingFailureClass.ambiguousOrUnknown;
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

