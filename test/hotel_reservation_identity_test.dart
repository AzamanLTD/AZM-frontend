// =============================================================================
// HOTEL RESERVATION — durable identity regression tests (deep-dive step 6,
// 2026-10-06).
//
// The retail checkout recovery deep-dive step 5 (2026-10-01) called the
// hotel path "conformant" because the BACKEND canonical createReservation
// carries Idempotency-Key + fingerprint + auto-dedupe. The step-6
// end-to-end contract audit found the CLIENT half missing:
//
//   HotelBookingScreen._confirmBooking →
//   HotelMarketplaceNotifier.reserve →
//   HotelMarketplaceService.reserve →
//   plain _client.post('/marketplace/business/$bizId/reservations')
//
//   — NO key on the wire, NO journal, NO recovery, NO classification.
//
// Two real consequences of the keyless client:
//   1. A lost response leaves the customer a blind retry (the backend's
//      auto-dedupe converges ONLY if the body fingerprint is identical —
//      the client has no armed identity and no way to converge by key).
//   2. A keyless rebook of an identical, previously CANCELLED slot
//      replays that cancelled reservation as a fresh success (the
//      backend's dedupe key IS the fingerprint when no key is supplied:
//      "to intentionally rebook after cancelling an identical slot, send
//      a fresh Idempotency-Key" — reservationController.createReservation).
//
// The production path is now (parity with checkoutCart / bookSeats):
//
//   HotelBookingScreen (_bookingRef, 'hotel.reserve_room') →
//   HotelMarketplaceNotifier.reserve(operationType, ref) →
//   HotelMarketplaceService.reserve → _resolveOperation →
//   DurableOperationRegistry → Idempotency-Key HEADER on the wire
//
// These tests pin the identity invariants of the REAL production path at
// the service level, through the actual durable wiring (no mocked
// HotelMarketplaceService):
//
//   1. One logical reservation retry (same ref, same room/dates) reuses
//      the SAME Idempotency-Key header — across service recreation too.
//   2. A lost/ambiguous first attempt retains the identity; a materially
//      changed room/dates begins a GENUINELY NEW identity and the old
//      unfinished instance stays recoverable in the journal.
//   3. The identity survives process death: journal replay reproduces
//      the exact wire — route (bizId), body, and key.
//   4. A definitive pre-economic 400 disposes the instance; the next
//      attempt is a new logical action. An ambiguous 409 keeps it armed.
//   5. A malformed 2xx (no authoritative reservation id) is an UNKNOWN
//      economic state: never surfaced as success, instance stays armed,
//      classification maps it to ambiguousOrUnknown.
//   6. The SERVICE layer never mints identity itself: a caller that
//      brings no operationType sends an unkeyed legacy request.
//   7. The failure classification is a pure projection of the SAME
//      predicate as the disposition, and the provider carries it for UI.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/hotel_marketplace_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Records every outgoing request and replays a scripted sequence of
/// replies: each entry is either an [http.Response] or an exception to
/// throw. When the script is exhausted, replies 200/success.
class _ScriptedClient {
  final requests = <http.Request>[];
  final script = <Object>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (script.isNotEmpty) {
      final next = script.removeAt(0);
      if (next is http.Response) return next;
      throw next;
    }
    return _ok;
  });

  /// The minimum authoritative reservation shape the backend guarantees
  /// on BOTH success paths (fresh create 200/201 and exact replay 200
  /// `replayed:true`): success:true AND a reservation map AND a
  /// non-empty string reservation.id (traced in AZM-backend
  /// reservationController.createReservation — the reservation row is
  /// created inside the request-identity insert so the replay answers
  /// the SAME committed reservation).
  static final http.Response _ok = http.Response(
    jsonEncode({
      'success': true,
      'reservation': {
        'id': 'resv-1',
        'reservationRef': 'HR-001',
        'status': 'CONFIRMED',
        'amountUsdc': '250.00',
      },
      'replayed': false,
    }),
    201,
    headers: {'content-type': 'application/json'},
  );

  static http.Response status(int code, {String message = 'boom'}) =>
      http.Response(jsonEncode({'success': false, 'message': message}), code,
          headers: {'content-type': 'application/json'});
}

const _type = 'hotel.reserve_room';
const _biz = 'biz-hotel-001';

// The exact reservation body HotelBookingScreen._confirmBooking sends.
final _checkInA = DateTime(2026, 11, 3);
final _checkOutA = DateTime(2026, 11, 5);
const _roomA = 'room-101';

// Materially different economic intent: a different room.
const _roomB = 'room-202';

HotelMarketplaceService _service(_ScriptedClient rec) =>
    HotelMarketplaceService(apiClient: ApiClient(client: rec.client));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    // The production reservation POST reads the auth token from secure
    // storage; answer null like an unauthenticated cold start.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    ApiClient.operationAccountOverride = () async => 'acct-test';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  test('retry of the same logical reservation reuses the SAME '
      'Idempotency-Key (lost first attempt, service recreation between '
      'attempts)', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: the response is LOST — the reservation may have committed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    expect(rec.requests, hasLength(1));
    final key1 = rec.requests[0].headers['idempotency-key'];
    expect(key1, isNotNull,
        reason: 'the durable path carries the instance key as the '
            'Idempotency-Key HEADER — the canonical createReservation '
            'reads exactly this header');
    expect(rec.requests[0].url.path,
        endsWith('/marketplace/business/biz-hotel-001/reservations'));

    // The journal holds exactly the one unfinished instance, still armed.
    final pendingAfterLoss = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterLoss, hasLength(1));
    expect(pendingAfterLoss.single.key, key1);
    expect(ref.operationId, isNotNull,
        reason: 'the ref retains the unfinished instance across the retry');

    // Attempt 2: a NEW service instance (the app retried) — the identity
    // comes from the ref-bound journal record, not the service.
    final reservation = await _service(rec).reserve(
        bizId: _biz,
        roomId: _roomA,
        checkIn: _checkInA,
        checkOut: _checkOutA,
        operationType: _type,
        ref: ref);
    expect(rec.requests, hasLength(2));
    final key2 = rec.requests[1].headers['idempotency-key'];
    expect(key2, key1,
        reason: 'a retry of the same logical reservation MUST reuse the '
            'same identity so the backend converges on the same committed '
            'reservation (exact replay, replayed:true) instead of relying '
            'on body-fingerprint luck — and instead of replaying a '
            'CANCELLED identical slot keylessly');
    expect(reservation['id'], 'resv-1');

    // Answered success disposes the instance: the ref is clear, the journal
    // is empty, and a NEXT reservation would be a genuinely new action.
    expect(ref.operationId, isNull);
    final pendingAfterSuccess = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterSuccess, isEmpty);
  });

  test('a materially changed room begins a GENUINELY NEW identity; the old '
      'unfinished instance stays recoverable', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1 with room A: ambiguous loss — instance armed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    final keyA = rec.requests[0].headers['idempotency-key'];

    // The user changes the room and tries again — a DIFFERENT economic
    // intent that must never reuse room A's key.
    final reservation = await _service(rec).reserve(
        bizId: _biz,
        roomId: _roomB,
        checkIn: _checkInA,
        checkOut: _checkOutA,
        operationType: _type,
        ref: ref);
    final keyB = rec.requests[1].headers['idempotency-key'];
    expect(keyB, isNot(keyA),
        reason: 'a materially different reservation is a new logical '
            'operation — reusing A\'s key would trigger the backend\'s '
            'same-key/different-intent 409');
    expect(reservation['id'], 'resv-1');

    // The NEW instance completed; room A's unfinished instance was NEVER
    // replaced or lost — it is still recoverable in the journal.
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, hasLength(1));
    expect(pending.single.key, keyA,
        reason: 'the old record is retained for journal recovery, not '
            'silently overwritten by the new intent');
  });

  test('the identity survives the claimed recovery boundary: process death '
      'journal replay reproduces the exact wire with the SAME key',
      () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: lost. The process then dies with the ref — identity must
    // survive in the journal alone.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    final key1 = rec.requests[0].headers['idempotency-key'];

    // Process death: only the persisted journal carries over.
    final store = await SharedPreferences.getInstance();
    final carried = <String, Object>{
      for (final k in store.getKeys())
        if (store.get(k) != null) k: store.get(k)!,
    };
    SharedPreferences.setMockInitialValues(carried);

    final ops = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(ops, hasLength(1),
        reason: 'the reservation instance outlives the process in the '
            'journal');
    expect(ops.single.key, key1);

    // The recovered replay reproduces the ORIGINAL wire request exactly —
    // route (bizId), body, and key — on a fresh client.
    final replayRec = _ScriptedClient();
    await ApiClient(client: replayRec.client)
        .retryRecovered(ops.single, requireAuth: false);
    expect(replayRec.requests, hasLength(1));
    expect(replayRec.requests[0].url.path,
        endsWith('/marketplace/business/biz-hotel-001/reservations'));
    expect(replayRec.requests[0].headers['idempotency-key'], key1,
        reason: 'the replay carries the SAME key so the backend replays '
            'the committed reservation instead of creating a second one');
    final replayBody =
        jsonDecode(replayRec.requests[0].body) as Map<String, dynamic>;
    final originalBody =
        jsonDecode(rec.requests[0].body) as Map<String, dynamic>;
    expect(replayBody, originalBody,
        reason: 'the replayed room, dates and party size are '
            'byte-identical to the original intent');
  });

  test('a definitive pre-economic 400 disposes the instance; the next '
      'attempt is a new logical action with a new identity. An ambiguous '
      '409 keeps the identity armed for the same-key retry', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: the backend's explicit pre-economic validation (e.g.
    // check-out must be after check-in) — provably nothing was created.
    rec.script.add(_ScriptedClient.status(400,
        message: 'Check-out must be after check-in.'));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<ApiException>()));
    expect(ref.operationId, isNull,
        reason: 'a definitive pre-economic 4xx releases the instance — '
            'nothing was created, so the client must not keep a stale '
            'identity armed');
    final pendingAfter400 = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfter400, isEmpty);

    // Next attempt: genuinely new action, NEW identity.
    await _service(rec).reserve(
        bizId: _biz,
        roomId: _roomA,
        checkIn: _checkInA,
        checkOut: _checkOutA,
        operationType: _type,
        ref: ref);
    expect(rec.requests[1].headers['idempotency-key'],
        isNot(rec.requests[0].headers['idempotency-key']));

    // Attempt 3 (fresh ref): 409 fingerprint conflict — AMBIGUOUS: the key
    // was already used with a different intent; never auto-mint a new key
    // here, keep the instance armed for reconciliation.
    final ref2 = FinancialOperationRef();
    rec.script.add(_ScriptedClient.status(409,
        message: 'Idempotency-Key was already used for a different '
            'reservation.'));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref2),
        throwsA(isA<ApiException>()));
    expect(ref2.operationId, isNotNull,
        reason: 'a 409 keeps the identity armed — the UI must reconcile '
            '(check bookings), and a same-key retry stays exact');
  });

  test('a malformed 2xx without an authoritative reservation is an UNKNOWN '
      'economic state: never surfaced as success, instance stays armed',
      () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // 200 with success:true but NO reservation id — a server bug or a
    // proxy answer. The reservation MAY have committed.
    rec.script.add(http.Response(
        jsonEncode({'success': true, 'reservation': {'status': 'CONFIRMED'}}),
        200,
        headers: {'content-type': 'application/json'}));
    await expectLater(
        _service(rec).reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<FormatException>()),
        reason: 'never surface an unconfirmed reservation as success — the '
            'caller would show the arrival sheet for a reservation that '
            'was never proven');
    expect(ref.operationId, isNotNull,
        reason: 'the FormatException stays outside every disposition '
            'clause — the instance stays armed for a same-key retry');

    // The classification maps it to ambiguousOrUnknown (unconfirmed).
    expect(
        HotelMarketplaceService.classifyHotelReservationFailure(
            const FormatException('malformed')),
        HotelBookingFailureClass.ambiguousOrUnknown);

    // A same-intent retry reuses the SAME key and converges.
    final reservation = await _service(rec).reserve(
        bizId: _biz,
        roomId: _roomA,
        checkIn: _checkInA,
        checkOut: _checkOutA,
        operationType: _type,
        ref: ref);
    expect(rec.requests[1].headers['idempotency-key'],
        rec.requests[0].headers['idempotency-key']);
    expect(reservation['id'], 'resv-1');
    expect(ref.operationId, isNull);
  });

  test('the SERVICE layer never mints identity itself: a caller that '
      'brings no operationType sends an unkeyed legacy request', () async {
    final rec = _ScriptedClient();

    final reservation = await _service(rec).reserve(
        bizId: _biz,
        roomId: _roomA,
        checkIn: _checkInA,
        checkOut: _checkOutA,
    );
    expect(reservation['id'], 'resv-1');
    expect(rec.requests[0].headers.containsKey('idempotency-key'), isFalse,
        reason: 'the legacy path keeps today\'s wire behavior — the '
            'backend\'s keyless auto-dedupe still converges identical '
            'bodies structurally');

    // And the journal holds nothing for this flow.
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, isEmpty);
  });

  test('classifyHotelReservationFailure is a pure projection of the '
      'disposition predicate — the two can never disagree', () async {
    // Every status the disposition RETAINS (401/408/409/425/429/5xx/other)
    // must classify as a NON-definitive class, and every status the
    // disposition RELEASES (other 4xx) must classify as
    // definitivePreEconomic. The classifier reuses the SAME private
    // predicate, so this holds by construction — the test pins it against
    // silent divergence.
    const retained = [401, 408, 409, 425, 429, 500, 503];
    const released = [400, 403, 404, 422];
    for (final code in retained) {
      expect(
          HotelMarketplaceService.classifyHotelReservationFailure(
              ApiException(
                  message: 'boom',
                  statusCode: code)),
          isNot(HotelBookingFailureClass.definitivePreEconomic),
          reason: 'status $code keeps the instance armed, so it must NOT '
              'classify as definitive');
    }
    for (final code in released) {
      expect(
          HotelMarketplaceService.classifyHotelReservationFailure(
              ApiException(
                  message: 'boom',
                  statusCode: code)),
          HotelBookingFailureClass.definitivePreEconomic,
          reason: 'status $code disposes the instance, so it must '
              'classify as definitive');
    }
  });

  test('the provider carries the economic failure class for the UI '
      '(ambiguous loss → ambiguousOrUnknown, never a silent success)',
      () async {
    final rec = _ScriptedClient();
    final notifier = HotelMarketplaceNotifier(
        HotelMarketplaceService(apiClient: ApiClient(client: rec.client)));
    final ref = FinancialOperationRef();

    // Ambiguous transport loss while booking: the room MAY be booked.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        notifier.reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    expect(notifier.state.isBooking, isFalse);
    expect(notifier.state.bookingFailureClass,
        HotelBookingFailureClass.ambiguousOrUnknown,
        reason: 'the UI must tell the customer the reservation MAY have '
            'gone through and that retrying the same room and dates safely '
            'reuses the request');

    // A definitive 400 is a clean pre-economic failure.
    final notifier2 = HotelMarketplaceNotifier(
        HotelMarketplaceService(apiClient: ApiClient(client: rec.client)));
    rec.script.add(_ScriptedClient.status(400, message: 'bad request'));
    await expectLater(
        notifier2.reserve(
            bizId: _biz,
            roomId: _roomA,
            checkIn: _checkInA,
            checkOut: _checkOutA,
            operationType: _type,
            ref: FinancialOperationRef()),
        throwsA(isA<ApiException>()));
    expect(notifier2.state.bookingFailureClass,
        HotelBookingFailureClass.definitivePreEconomic);
  });
}
