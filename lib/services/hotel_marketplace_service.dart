import 'dart:convert';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_interceptor.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Economic classification of a durable hotel-reservation failure. Pure
/// projection of the SAME disposition predicate the identity lifecycle
/// uses ([HotelMarketplaceService._isDefinitivePreEconomic]), so a class
/// can never contradict the armed/retired state of the operation.
enum HotelBookingFailureClass {
  /// Answered, final, and provably pre-economic (400/403/404/422…): the
  /// reservation was NOT created; the caller may freely start over.
  definitivePreEconomic,

  /// 401: the session is gone; re-auth, then retry the SAME operation.
  authenticationRequired,

  /// 429: the operation was rejected for pace, not content; retry later.
  rateLimited,

  /// 409 fingerprint conflict: the key was already used for a materially
  /// different reservation. Refresh authoritative state before anything.
  domainConflict,

  /// Transport loss, 5xx, timeout or a malformed 2xx: the economic
  /// outcome is UNPROVEN. The operation stays armed; a same-key retry
  /// converges on the authoritative result instead of duplicating.
  ambiguousOrUnknown,
}

class HotelMarketplaceException implements Exception {
  final String message;
  final int? statusCode;
  const HotelMarketplaceException(this.message, {this.statusCode});

  @override
  String toString() => 'HotelMarketplaceException: $message';
}

class HotelBusinessDetail {
  final BusinessProfile business;
  final List<HotelRoom> rooms;

  const HotelBusinessDetail({required this.business, required this.rooms});
}

class HotelMarketplaceService {
  HotelMarketplaceService({ApiClient? apiClient})
      : _client = apiClient ?? ApiClient();
  final ApiClient _client;

  Future<HotelBusinessDetail> fetchHotel(String bizId) async {
    final response = await _client.get('/marketplace/business/$bizId');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw HotelMarketplaceException(
        (body['message'] ?? 'Unable to load hotel').toString(),
        statusCode: response.statusCode,
      );
    }

    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rooms = (data['hotelRooms'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HotelRoom.fromJson)
        .toList();
    return HotelBusinessDetail(
      business: BusinessProfile.fromJson(
        (data['business'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      rooms: rooms,
    );
  }

  /// Books a room.
  ///
  /// The [operationType] + [ref] pair is the durable identity path (deep-dive
  /// step 6, 2026-10-06): ONE logical reservation intent → ONE durable
  /// identity → the backend's canonical createReservation dedupe (same key
  /// + same fingerprint ⇒ exact replay of the SAME reservation, `replayed:
  /// true`; same key + materially different body ⇒ 409 fail-closed).
  ///
  /// Keyless (legacy) requests still auto-dedupe on the backend's
  /// body-derived key, BUT a keyless rebook of an identical, previously
  /// CANCELLED slot replays that cancelled reservation as a fresh success —
  /// only a per-operation key makes "new logical operation" explicit.
  /// The ref also arms the journal: a lost response stays recoverable
  /// (same-key retry converges) instead of a blind duplicate attempt.
  ///
  /// CONTRACT: [operationType] and [ref] are an INSEPARABLE PAIR — the
  /// durable path requires a [FinancialOperationRef] as the lifecycle
  /// owner of the instance. [operationType] without [ref] is a caller
  /// bug and fails closed with an [ArgumentError] BEFORE any HTTP
  /// request and BEFORE any durable record is created: without a ref
  /// nothing could ever retire the instance ([_releaseOperation] is
  /// ref-driven), so a successful operation would stay pending forever.
  ///
  /// Without [operationType] the call is the legacy unkeyed path: plain
  /// transport, no journal, no recovery — exactly today's wire.
  Future<Map<String, dynamic>> reserve({
    required String bizId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    int partySize = 1,
    String? operationType,
    FinancialOperationRef? ref,
  }) async {
    final endpoint = '/marketplace/business/$bizId/reservations';
    final body = <String, dynamic>{
      'roomId': roomId,
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'partySize': partySize,
    };

    if (operationType == null) {
      // Legacy unkeyed path: no durable lifecycle — plain transport.
      return _reserveLegacy(endpoint, body);
    }

    // Durable-path contract (lifecycle hardening, 2026-10-06): the ref is
    // the instance's lifecycle OWNER — [_releaseOperation] retires by
    // ref, so operationType without ref would create a durable record
    // nothing can ever retire (a successful operation pending forever).
    // Fail closed BEFORE the demo short-circuit, BEFORE any HTTP request
    // and BEFORE any durable record is created: the pair is inseparable.
    if (ref == null) {
      throw ArgumentError(
          'HotelMarketplaceService.reserve: operationType and ref must be '
          'supplied together — the durable path requires a ref as the '
          'lifecycle owner of the operation instance.');
    }

    // Demo mode short-circuits before economics (the SAME policy as
    // [MarketplaceBookingService.bookSeats]): a demo-intercepted reply
    // never flows through the durable instance. An endpoint the demo
    // interceptor does not handle falls through to the durable path.
    if (AppConfig.demoMode) {
      final m = DemoInterceptor.tryPost(endpoint, body);
      if (m != null) {
        return _parseReservation(m.body, statusCode: m.statusCode);
      }
    }

    // Durable identity (parity with checkoutCart / bookSeats): retry the
    // ref's unfinished instance when the body matches its fingerprint,
    // begin a genuinely new one otherwise, and arm the caller's ref
    // BEFORE the request leaves the device.
    final op = await _resolveOperation(
        type: operationType, endpoint: endpoint, request: body, ref: ref);
    try {
      final response =
          await _client.post(endpoint, body, headers: {'Idempotency-Key': op.key});
      // Malformed-success guard (parity with checkoutCart / bookSeats): an
      // answered 2xx without an AUTHORITATIVE reservation is an UNKNOWN
      // economic state — never success, never definitive. The
      // FormatException stays OUTSIDE every disposition clause → the
      // instance stays armed for a same-key retry;
      // classifyHotelReservationFailure maps it to ambiguousOrUnknown.
      if (!_carriesAuthoritativeReservation(response.body)) {
        throw const FormatException(
            'Reservation response was successful but carried no '
            'authoritative reservation (id).');
      }
      // Answered success — this reservation instance is complete.
      await _releaseOperation(ref);
      return _parseReservation(response.body, statusCode: response.statusCode);
    } on ApiException catch (e) {
      // Disposition mirrors postFinancial / checkoutCart / bookSeats:
      // definitive pre-economic 4xx → terminal (backend released the
      // claim); 401/408/409/425/429, every 5xx and every transport loss →
      // retained (the reservation may have committed; a same-key retry
      // converges).
      if (_isDefinitivePreEconomic(e.statusCode)) {
        await _releaseOperation(ref);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _reserveLegacy(
      String endpoint, Map<String, dynamic> body) async {
    final response = await _client.post(endpoint, body);
    return _parseReservation(response.body, statusCode: response.statusCode);
  }

  /// Parses a raw reservation response body: non-success →
  /// [HotelMarketplaceException]; success without a reservation map → the
  /// historical "completed without a reservation" error.
  Map<String, dynamic> _parseReservation(String raw, {int? statusCode}) {
    final body = jsonDecode(raw) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw HotelMarketplaceException(
        (body['message'] ?? 'Booking failed').toString(),
        statusCode: statusCode,
      );
    }
    final reservation = (body['reservation'] as Map?)?.cast<String, dynamic>();
    if (reservation == null) {
      throw const HotelMarketplaceException('Booking completed without a reservation response.');
    }
    return reservation;
  }

  // ── DURABLE IDENTITY HELPERS (parity with the shared operation contract) ───

  /// Minimum authoritative reservation shape guaranteed by the backend on
  /// BOTH success paths (fresh create and exact replay 200): `success:true`
  /// AND a reservation map AND a non-empty string `reservation.id`
  /// (generated at commit in reservationController.createReservation).
  static bool _carriesAuthoritativeReservation(String raw) {
    final body = jsonDecode(raw) as Map<String, dynamic>;
    if (body['success'] != true) return false;
    final reservation = body['reservation'];
    if (reservation is! Map<String, dynamic>) return false;
    final id = reservation['id'];
    return id is String && id.isNotEmpty;
  }

  /// Resolves the durable operation instance (the SAME policy as
  /// [ApiClient.postFinancial]): retry the ref's instance when it is still
  /// pending and the body matches its recorded fingerprint; otherwise
  /// begin a GENUINELY NEW instance (the old record stays untouched and
  /// recoverable — never silently replaced).
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

  /// r42 disposition predicate (parity with StorefrontService /
  /// MarketplaceBookingService): definitive pre-economic 4xx — everything
  /// except 401 / 408 / 409 / 425 / 429 — releases the ref's instance;
  /// every other answered outcome (and every transport loss) stays armed
  /// for a same-key retry.
  static bool _isDefinitivePreEconomic(int statusCode) =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 401 &&
      statusCode != 408 &&
      statusCode != 409 &&
      statusCode != 425 &&
      statusCode != 429;

  /// Maps a thrown failure of the durable reservation path to its economic
  /// class. Pure projection: reuses the SAME definitive predicate as the
  /// disposition, so classification can never contradict the lifecycle.
  static HotelBookingFailureClass classifyHotelReservationFailure(
      Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return HotelBookingFailureClass.authenticationRequired;
      }
      if (error.statusCode == 429) return HotelBookingFailureClass.rateLimited;
      if (error.statusCode == 409) return HotelBookingFailureClass.domainConflict;
      if (_isDefinitivePreEconomic(error.statusCode)) {
        return HotelBookingFailureClass.definitivePreEconomic;
      }
      return HotelBookingFailureClass.ambiguousOrUnknown; // 5xx / other
    }
    // FormatException (malformed 2xx), TimeoutException, http
    // ClientException / SocketException, and anything unrecognized: the
    // economic outcome is UNPROVEN. Fail safe as unknown.
    return HotelBookingFailureClass.ambiguousOrUnknown;
  }
}
