// =============================================================================
// TRANSIT SEAT BOOKING — durable identity regression tests (§r42, 2026-10-01).
//
// The retail checkout recovery deep-dive step 5 (2026-10-01) found the REAL
// gap in the marketplace verticals: transit seat booking had NO durable
// identity — a booking that committed while its HTTP response was lost
// turned the customer's same-seat retry into an indistinguishable
// 400 'Seats already booked' (their own committed seats vs another
// customer's), and the UI asserted a generic 'Booking failed' on every
// error, including ambiguous transport losses where the booking MAY have
// gone through.
//
// The production path is now (AZM-backend commit 1713467 mounts the shared
// idempotency authority on POST /marketplace/transit/trips/:id/book, claim
// committed INSIDE the booking transaction):
//
//   TransitSeatSelectionScreen (_bookingRef) →
//   BookingActionNotifier.bookSeats(operationType: 'transit.book_seats',
//   ref: FinancialOperationRef) →
//   MarketplaceBookingService.bookSeats → _resolveOperation →
//   DurableOperationRegistry → Idempotency-Key HEADER on the wire
//
// These tests pin the identity invariants of the REAL production path at
// the service level, through the actual durable wiring (no mocked
// MarketplaceBookingService):
//
//   1. One logical booking retry (same ref, same seat selection) reuses
//      the SAME Idempotency-Key header — across service recreation too.
//   2. A lost/ambiguous first attempt retains the identity for the retry;
//      a materially changed selection begins a GENUINELY NEW identity and
//      the old unfinished instance stays recoverable in the journal.
//   3. The identity survives process death: journal replay reproduces the
//      exact wire — route (tripId), body, and key.
//   4. A definitive pre-economic 400 disposes the instance; the next
//      attempt is a new logical action with a new identity. An ambiguous
//      409 keeps the identity armed.
//   5. A malformed 2xx (no authoritative booking id/bookingRef) is an
//      UNKNOWN economic state: never surfaced as success, instance stays
//      armed, and the classification maps it to ambiguousOrUnknown.
//   6. The SERVICE layer never mints identity itself: a caller that
//      brings no operationType sends an unkeyed legacy request.
//   7. The failure classification is a pure projection of the SAME
//      predicate as the disposition (it can never contradict the
//      lifecycle), and the notifier surfaces it for the UI.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Records every outgoing request and replays a scripted sequence of
/// replies: each entry is either an [http.Response] or an exception to
/// throw. When the script is exhausted, replies 201/success.
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

  /// The minimum authoritative booking shape the backend guarantees on BOTH
  /// success paths (fresh 201 and exact replay 201): success:true AND a
  /// non-empty booking id + bookingRef (traced in AZM-backend
  /// services/transitBookingService.bookSeats — response built inside the
  /// booking $transaction so the committed claim's responseBody is
  /// byte-identical to the controller's wire response).
  static final http.Response _ok = http.Response(
    jsonEncode({
      'success': true,
      'booking': {
        'id': 'booking-1',
        'bookingRef': 'TB-001',
        'status': 'PENDING',
      },
      'seatIds': ['s1', 's2'],
      'totalFare': 42.5,
    }),
    201,
    headers: {'content-type': 'application/json'},
  );

  static http.Response status(int code, {String message = 'boom'}) =>
      http.Response(jsonEncode({'success': false, 'message': message}), code,
          headers: {'content-type': 'application/json'});
}

const _type = 'transit.book_seats';
const _trip = 'trip-001';

// The exact booking body TransitSeatSelectionScreen._bookSeats sends.
final _seatsA = <String>['s1', 's2'];
final _namesA = <String>['Amara', 'Kofi'];

// Materially different economic intent: a different seat selection.
final _seatsB = <String>['s1', 's3'];

MarketplaceBookingService _service(_ScriptedClient rec) =>
    MarketplaceBookingService(apiClient: ApiClient(client: rec.client));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    // The production booking POST reads the auth token from secure storage;
    // answer null like an unauthenticated cold start.
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

  test('retry of the same logical booking reuses the SAME Idempotency-Key '
      '(lost first attempt, service recreation between attempts)', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: the response is LOST — the booking may have committed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    expect(rec.requests, hasLength(1));
    final key1 = rec.requests[0].headers['idempotency-key'];
    expect(key1, isNotNull,
        reason: 'the durable path carries the instance key as the '
            'Idempotency-Key HEADER (the transit route reads the header, '
            'unlike the storefront body field)');
    expect(rec.requests[0].url.path, endsWith('/marketplace/transit/trips/trip-001/book'));

    // The journal holds exactly the one unfinished instance, still armed.
    final pendingAfterLoss = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterLoss, hasLength(1));
    expect(pendingAfterLoss.single.key, key1);
    expect(ref.operationId, isNotNull,
        reason: 'the ref retains the unfinished instance across the retry');

    // Attempt 2: a NEW service instance (the app retried) — the identity
    // comes from the ref-bound journal record, not the service.
    final result = await _service(rec).bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    expect(rec.requests, hasLength(2));
    final key2 = rec.requests[1].headers['idempotency-key'];
    expect(key2, key1,
        reason: 'a retry of the same logical booking MUST reuse the same '
            'identity so the backend converges on the same booking '
            '(exact replay of the committed response) instead of hitting '
            'the indistinguishable 400 "Seats already booked"');
    expect(result.bookingId, 'booking-1');

    // Answered success disposes the instance: the ref is clear, the journal
    // is empty, and a NEXT booking would be a genuinely new action.
    expect(ref.operationId, isNull);
    final pendingAfterSuccess = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterSuccess, isEmpty);
  });

  test('a materially changed seat selection begins a GENUINELY NEW identity; '
      'the old unfinished instance stays recoverable', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1 with seats A: ambiguous loss — instance armed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
            operationType: _type,
            ref: ref),
        throwsA(isA<http.ClientException>()));
    final keyA = rec.requests[0].headers['idempotency-key'];

    // The user changes the seat selection and tries again — this is a
    // DIFFERENT economic intent and must never reuse seats A's key.
    final result = await _service(rec).bookSeats(
        tripId: _trip,
        seatIds: _seatsB,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    final keyB = rec.requests[1].headers['idempotency-key'];
    expect(keyB, isNot(keyA),
        reason: 'a materially different seat selection is a new logical '
            'booking — reusing A\'s key would trigger the backend\'s '
            'same-key/different-intent 409');
    expect(result.bookingId, 'booking-1');

    // The NEW instance completed; seats A's unfinished instance was NEVER
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
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
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
        reason: 'the booking instance outlives the process in the journal');
    expect(ops.single.key, key1);

    // The recovered replay reproduces the ORIGINAL wire request exactly —
    // route (tripId), body, and key — on a fresh client.
    final replayRec = _ScriptedClient();
    await ApiClient(client: replayRec.client)
        .retryRecovered(ops.single, requireAuth: false);
    expect(replayRec.requests, hasLength(1));
    expect(replayRec.requests[0].url.path,
        endsWith('/marketplace/transit/trips/trip-001/book'));
    expect(replayRec.requests[0].headers['idempotency-key'], key1,
        reason: 'the replay carries the SAME key so the backend replays '
            'the committed booking instead of creating a second one');
    final replayBody =
        jsonDecode(replayRec.requests[0].body) as Map<String, dynamic>;
    final originalBody =
        jsonDecode(rec.requests[0].body) as Map<String, dynamic>;
    expect(replayBody, originalBody,
        reason: 'the replayed seat selection, passenger names and note are '
            'byte-identical to the original intent');
  });

  test('a definitive pre-economic 400 disposes the instance; the next '
      'attempt is a new logical action with a new identity. An ambiguous '
      '409 keeps the identity armed for the same-key retry', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: the backend's explicit pre-economic validation (seats
    // taken by another customer). NOTE: with the durable identity armed,
    // the customer's OWN committed seats converge via replay — a 400 here
    // genuinely means another customer holds them.
    rec.script.add(_ScriptedClient.status(400,
        message: 'One or more seats were just booked by another customer. '
            'Please try again.'));
    await expectLater(
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
            operationType: _type,
            ref: ref),
        throwsA(isA<ApiException>()));
    expect(ref.operationId, isNull,
        reason: 'a definitive pre-economic 4xx releases the instance — the '
            'backend released the claim (releaseOn4xx), so the client must '
            'not keep a stale identity armed');
    final pendingAfter400 = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfter400, isEmpty);

    // Next attempt: genuinely new action, NEW identity.
    await _service(rec).bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    expect(rec.requests[1].headers['idempotency-key'],
        isNot(rec.requests[0].headers['idempotency-key']));

    // Attempt 3 (fresh ref): 409 fingerprint conflict — AMBIGUOUS: the key
    // was already used with a different intent; never auto-mint a new key
    // here, keep the instance armed for reconciliation.
    final ref2 = FinancialOperationRef();
    rec.script.add(_ScriptedClient.status(409,
        message: 'This idempotency key was already used with a different '
            'payload.'));
    await expectLater(
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
            operationType: _type,
            ref: ref2),
        throwsA(isA<ApiException>()));
    expect(ref2.operationId, isNotNull,
        reason: 'a 409 keeps the identity armed — the UI must reconcile '
            '(check bookings), and a same-key retry stays exact');
  });

  test('a malformed 2xx without an authoritative booking is an UNKNOWN '
      'economic state: never surfaced as success, instance stays armed',
      () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // 200 with success:true but NO booking id/bookingRef — a server bug or
    // a proxy answer. The booking MAY have committed.
    rec.script.add(http.Response(
        jsonEncode({'success': true, 'booking': {}, 'seatIds': _seatsA}),
        200,
        headers: {'content-type': 'application/json'}));
    await expectLater(
        _service(rec).bookSeats(
            tripId: _trip,
            seatIds: _seatsA,
            passengerNames: _namesA,
            operationType: _type,
            ref: ref),
        throwsA(isA<FormatException>()),
        reason: 'never surface an unconfirmed booking as success — the '
            'caller would show a boarding pass for a booking that was '
            'never proven');
    expect(ref.operationId, isNotNull,
        reason: 'the FormatException stays outside every disposition '
            'clause — the instance stays armed for a same-key retry');

    // The classification maps it to ambiguousOrUnknown (unconfirmed).
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            const FormatException('malformed')),
        TransitBookingFailureClass.ambiguousOrUnknown);

    // A same-selection retry reuses the SAME key and converges.
    final result = await _service(rec).bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    expect(rec.requests[1].headers['idempotency-key'],
        rec.requests[0].headers['idempotency-key']);
    expect(result.bookingId, 'booking-1');
    expect(ref.operationId, isNull);
  });

  test('the SERVICE layer never mints identity itself: a caller that brings '
      'no operationType sends an unkeyed legacy request', () async {
    final rec = _ScriptedClient();

    final result = await _service(rec).bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
    );
    expect(result.bookingId, 'booking-1');
    expect(rec.requests[0].headers.containsKey('idempotency-key'), isFalse,
        reason: 'the legacy path keeps today\'s wire behavior — the DB-level '
            'TransitBookingSeat @@unique([tripId, seatId]) still prevents '
            'duplicate seat claims structurally');

    // And the journal holds nothing for this flow.
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, isEmpty);
  });

  test('classifyTransitBookingFailure is a pure projection of the '
      'disposition predicate — the two can never disagree', () async {
    // Every status the disposition RETAINS (401/408/409/425/429/5xx/other)
    // classifies as NOT definitive; every status the disposition RELEASES
    // (400/403/404) classifies as definitivePreEconomic.
    final released = <int>[400, 403, 404];
    final retained = <int>[401, 408, 409, 425, 429, 500, 502, 503];

    for (final code in released) {
      final cls = MarketplaceBookingService.classifyTransitBookingFailure(
          ApiException(message: 'x', statusCode: code));
      expect(cls, TransitBookingFailureClass.definitivePreEconomic,
          reason: 'HTTP $code');
    }
    for (final code in retained) {
      final cls = MarketplaceBookingService.classifyTransitBookingFailure(
          ApiException(message: 'x', statusCode: code));
      expect(cls, isNot(TransitBookingFailureClass.definitivePreEconomic),
          reason: 'HTTP $code must never be claimed definitive');
    }
    // Named classes for the UI's retry guidance.
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            ApiException(message: 'x', statusCode: 401)),
        TransitBookingFailureClass.authenticationRequired);
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            ApiException(message: 'x', statusCode: 429)),
        TransitBookingFailureClass.rateLimited);
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            ApiException(message: 'x', statusCode: 409)),
        TransitBookingFailureClass.domainConflict);
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            ApiException(message: 'x', statusCode: 408)),
        TransitBookingFailureClass.ambiguousOrUnknown);
    // Unrecognized transport-level failures: fail safe as unknown.
    expect(
        MarketplaceBookingService.classifyTransitBookingFailure(
            http.ClientException('lost')),
        TransitBookingFailureClass.ambiguousOrUnknown);
  });

  test('the notifier surfaces the economic class for the UI: an ambiguous '
      'loss sets failureClass=ambiguousOrUnknown (unconfirmed), a '
      'definitive 400 sets definitivePreEconomic', () async {
    final rec = _ScriptedClient();
    final notifier = BookingActionNotifier(
        MarketplaceBookingService(apiClient: ApiClient(client: rec.client)));
    final ref = FinancialOperationRef();

    // Ambiguous loss: transport failure with the booking MAYBE committed.
    rec.script.add(http.ClientException('response lost'));
    await notifier.bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    expect(notifier.state.error, isNotNull);
    expect(notifier.state.failureClass,
        TransitBookingFailureClass.ambiguousOrUnknown);
    expect(notifier.state.failureClass!.isUnconfirmed, isTrue,
        reason: 'the UI must warn (check your bookings) instead of asserting '
            'the booking definitely failed');

    // Same-selection retry converges (script exhausted → 201).
    await notifier.bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: ref);
    expect(notifier.state.error, isNull);
    expect(notifier.state.result, isNotNull);
    expect(notifier.state.failureClass, isNull);

    // Definitive pre-economic failure: the backend's own validation.
    final notifier2 = BookingActionNotifier(
        MarketplaceBookingService(apiClient: ApiClient(client: rec.client)));
    rec.script.add(
        _ScriptedClient.status(400, message: 'Seats already booked.'));
    await notifier2.bookSeats(
        tripId: _trip,
        seatIds: _seatsA,
        passengerNames: _namesA,
        operationType: _type,
        ref: FinancialOperationRef());
    expect(notifier2.state.failureClass,
        TransitBookingFailureClass.definitivePreEconomic);
    expect(notifier2.state.failureClass!.isUnconfirmed, isFalse);
  });
  test('demo mode short-circuits BEFORE economics: the demo book response '
      'flows through the legacy parse with NO durable entry and NO '
      'malformed-success failure', () async {
    // The demo book response carries no `booking` object (top-level
    // bookingRef only), so it is NOT the authoritative wire shape — the
    // durable path's malformed-success guard must never see it. postFinancial
    // policy: demo has no economics, so no journal entry either.
    // Demo is a session-wide latch (no disable API, matching the app);
    // this test therefore runs LAST in the file so the latch cannot
    // poison the real durable-path tests.
    AppConfig.enableDemoMode();

    final durableResult = await _service(_ScriptedClient()).bookSeats(
      tripId: _trip,
      seatIds: _seatsA,
      passengerNames: _namesA,
      operationType: _type,
      ref: FinancialOperationRef(),
    );
    expect(durableResult.success, isTrue,
        reason: 'the demo booking keeps today\'s success shape — never a '
            'FormatException on the demo payload');
    // Byte-identical to the legacy parse: the demo payload\'s TOP-LEVEL
    // bookingRef is (pre-existing behavior, preserved verbatim) not read
    // by BookSeatResult.fromJson — the guard must not "fix" demo economics.
    final legacyResult = await _service(_ScriptedClient()).bookSeats(
      tripId: _trip,
      seatIds: _seatsA,
      passengerNames: _namesA,
    );
    expect(durableResult.bookingRef, legacyResult.bookingRef);
    expect(durableResult.bookingId, legacyResult.bookingId);
    expect(durableResult.status, legacyResult.status);
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, isEmpty,
        reason: 'demo mode never journals a durable instance');
  });

}
