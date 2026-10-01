// =============================================================================
// RETAIL CHECKOUT RECOVERY — canonical identity path regression tests.
//
// The 2026-10-01 trace audit established the PRODUCTION retail checkout:
//
//   CartScreen → StorefrontService.checkoutCart(operationType:
//   'storefront.cart.checkout', ref: FinancialOperationRef) →
//   _resolveOperation → DurableOperationRegistry → backend checkout
//
// The parallel RetailCheckoutController → RetailCheckoutOperation →
// StorefrontRetailCheckoutGateway chain is NOT production-reachable (the
// widget registry's last construction site was removed in the same audit);
// it transports a caller-owned key through the legacy pre-armed
// checkoutCart `idempotencyKey` parameter and has no journal, recovery or
// disposition.
//
// These tests pin the identity invariants of the REAL production path at
// the service level, through the actual durable wiring (no mocked
// StorefrontService):
//
//   1. One logical checkout retry (same ref, same cart) reuses the SAME
//      idempotency identity — across service recreation too.
//   2. A lost/ambiguous first attempt retains the identity for the retry.
//   3. A materially changed cart begins a GENUINELY NEW identity, and the
//      old unfinished instance stays recoverable in the journal.
//   4. The identity survives the claimed recovery boundary: process death
//      (journal replay reproduces the exact wire, same key).
//   5. A definitive pre-economic failure disposes the instance; the next
//      attempt is a new logical action with a new identity. An ambiguous
//      409 keeps the identity armed.
//   6. The SERVICE layer never mints or dedups identity itself: identity
//      belongs to the caller's ref-bound durable instance, and a caller
//      that brings none sends an unkeyed legacy request.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
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

  static final http.Response _ok = http.Response(
    jsonEncode({
      'success': true,
      'data': {'order': {'id': 'order-1', 'orderRef': 'R-001'}},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  static http.Response status(int code, {String message = 'boom'}) =>
      http.Response(jsonEncode({'message': message}), code,
          headers: {'content-type': 'application/json'});
}

const _type = 'storefront.cart.checkout';
const _biz = 'biz-001';

// The exact cart item shape CartScreen sends (cartProvider.toCheckoutItems).
final _cartA = <Map<String, dynamic>>[
  {'productId': 'p1', 'quantity': 2},
  {'productId': 'p2', 'quantity': 1, 'variants': {'Size': 'Large'}},
];

// Materially different economic intent: one quantity changed.
final _cartB = <Map<String, dynamic>>[
  {'productId': 'p1', 'quantity': 3},
  {'productId': 'p2', 'quantity': 1, 'variants': {'Size': 'Large'}},
];

StorefrontService _service(_ScriptedClient rec) =>
    StorefrontService(apiClient: ApiClient(client: rec.client));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    // The production checkout POST reads the auth token from secure
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

  test('retry of the same logical checkout reuses the SAME idempotency '
      'identity (lost first attempt, service recreation between attempts)',
      () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1: the response is LOST — the order may have committed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref),
        throwsA(isA<http.ClientException>()));
    expect(rec.requests, hasLength(1));
    final key1 = jsonDecode(rec.requests[0].body)['idempotencyKey'] as String;
    final firstInstanceId = ref.operationId;
    expect(firstInstanceId, isNotNull,
        reason: 'the ref retains the unfinished instance across the retry');
    expect(rec.requests[0].url.path, endsWith('/storefront/biz-001/checkout'));

    // The journal holds exactly the one unfinished instance, still armed.
    final pendingAfterLoss = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterLoss, hasLength(1));
    expect(pendingAfterLoss.single.key, key1);

    // Attempt 2: a NEW StorefrontService instance (the app retried) — the
    // identity comes from the ref-bound journal record, not the service.
    final result = await _service(rec).checkoutCart(
        businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref);
    expect(rec.requests, hasLength(2));
    final key2 = jsonDecode(rec.requests[1].body)['idempotencyKey'] as String;
    expect(key2, key1,
        reason: 'a retry of the same logical checkout MUST reuse the same '
            'identity so it converges on the same server-side order');
    expect(result['order'], isNotNull);

    // Answered success disposes the instance: the ref is clear, the journal
    // is empty, and a NEXT checkout would be a genuinely new action.
    expect(ref.operationId, isNull);
    final pendingAfterSuccess = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pendingAfterSuccess, isEmpty);
  });

  test('a materially changed cart begins a GENUINELY NEW identity; the old '
      'unfinished instance stays recoverable', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Attempt 1 with cart A: ambiguous loss — instance armed.
    rec.script.add(http.ClientException('response lost'));
    await expectLater(
        _service(rec).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref),
        throwsA(isA<http.ClientException>()));
    final keyA = jsonDecode(rec.requests[0].body)['idempotencyKey'] as String;

    // The user edits the cart (quantity 2 → 3) and tries again — this is
    // a DIFFERENT economic intent and must never reuse cart A's key.
    final result = await _service(rec).checkoutCart(
        businessProfileId: _biz, items: _cartB, operationType: _type, ref: ref);
    final keyB = jsonDecode(rec.requests[1].body)['idempotencyKey'] as String;
    expect(keyB, isNot(keyA),
        reason: 'a materially different cart is a new logical checkout');
    expect(result['order'], isNotNull);

    // The NEW instance completed; cart A's unfinished instance was NEVER
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
        _service(rec).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref),
        throwsA(isA<http.ClientException>()));
    final key1 = jsonDecode(rec.requests[0].body)['idempotencyKey'] as String;

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
        reason: 'the checkout instance outlives the process in the journal');
    expect(ops.single.key, key1);

    // The recovered replay reproduces the ORIGINAL wire request exactly —
    // route (businessProfileId), body, and key — on a fresh client.
    final replayRec = _ScriptedClient();
    await ApiClient(client: replayRec.client)
        .retryRecovered(ops.single, requireAuth: false);

    expect(replayRec.requests, hasLength(1));
    final replay = replayRec.requests.single;
    expect(replay.url.path, rec.requests[0].url.path,
        reason: 'the replay preserves the :businessProfileId route parameter');
    expect(jsonDecode(replay.body)['idempotencyKey'], key1,
        reason: 'the replay carries the ORIGINAL instance key');
    expect(replay.headers['Idempotency-Key'], key1);
    expect(jsonDecode(replay.body)['items'], _cartA,
        reason: 'the replay is byte-identical to the original cart intent');
  });

  test('a definitive pre-economic failure disposes the instance — the next '
      'attempt is a NEW logical action with a NEW identity', () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Answered 400: definitive pre-economic failure → terminal.
    rec.script.add(_ScriptedClient.status(400, message: 'Invalid cart'));
    await expectLater(
        _service(rec).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref),
        throwsA(predicate<ApiException>((e) => e.statusCode == 400)));
    final key1 = jsonDecode(rec.requests[0].body)['idempotencyKey'] as String;
    expect(ref.operationId, isNull,
        reason: 'a definitive outcome retires the instance and clears the ref');
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, isEmpty);

    // The user fixes the problem and checks out the same cart again: a
    // genuinely new logical action — NEVER the disposed instance's key.
    final result = await _service(rec).checkoutCart(
        businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref);
    final key2 = jsonDecode(rec.requests[1].body)['idempotencyKey'] as String;
    expect(key2, isNot(key1));
    expect(result['order'], isNotNull);
  });

  test('an ambiguous 409 keeps the identity ARMED for a same-key retry',
      () async {
    final rec = _ScriptedClient();
    final ref = FinancialOperationRef();

    // Answered 409: the mutation may be committed/in-flight — the conflict
    // is authoritative but the instance must stay armed.
    rec.script.add(_ScriptedClient.status(409, message: 'Idempotent replay'));
    await expectLater(
        _service(rec).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref),
        throwsA(predicate<ApiException>((e) => e.statusCode == 409)),
        reason: 'ApiClient maps every non-2xx to ApiException before the '
            'service parses it');
    final key1 = jsonDecode(rec.requests[0].body)['idempotencyKey'] as String;
    expect(ref.operationId, isNotNull,
        reason: 'an ambiguous outcome retains the identity');

    // The retry converges on the same key.
    final result = await _service(rec).checkoutCart(
        businessProfileId: _biz, items: _cartA, operationType: _type, ref: ref);
    expect(jsonDecode(rec.requests[1].body)['idempotencyKey'], key1);
    expect(result['order'], isNotNull);
  });

  test('the SERVICE layer never mints identity — it belongs to the caller',
      () async {
    final rec = _ScriptedClient();

    // No operationType/ref/idempotencyKey: the legacy unkeyed seam sends
    // NO identity at all (the caller declined the durable contract).
    final result = await _service(rec).checkoutCart(
        businessProfileId: _biz, items: _cartA);
    expect(rec.requests, hasLength(1));
    expect(jsonDecode(rec.requests[0].body).containsKey('idempotencyKey'), isFalse,
        reason: 'the service must not invent identity the caller did not bring');
    expect(rec.requests[0].headers.containsKey('Idempotency-Key'), isFalse);
    expect(result['order'], isNotNull);
    final pending = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending, isEmpty);

    // Two DISTINCT caller refs over the same cart are two logical
    // operations: each ref owns its own instance identity — the service
    // neither reuses nor dedups them behind the caller's back.
    final rec2 = _ScriptedClient();
    rec2.script.addAll([
      http.ClientException('lost'),
      http.ClientException('lost'),
    ]);
    final refA = FinancialOperationRef();
    final refB = FinancialOperationRef();
    await expectLater(
        _service(rec2).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: refA),
        throwsA(isA<http.ClientException>()));
    await expectLater(
        _service(rec2).checkoutCart(
            businessProfileId: _biz, items: _cartA, operationType: _type, ref: refB),
        throwsA(isA<http.ClientException>()));
    final keyA = jsonDecode(rec2.requests[0].body)['idempotencyKey'] as String;
    final keyB = jsonDecode(rec2.requests[1].body)['idempotencyKey'] as String;
    expect(keyA, isNot(keyB),
        reason: 'identity is per logical caller operation, never per-request '
            'dedup or a service-global key');
    expect(refA.operationId, isNot(refB.operationId));
    final pending2 = await DurableOperationRegistry.pending(
        account: 'acct-test', type: _type);
    expect(pending2, hasLength(2),
        reason: 'both refs hold their own unfinished instances');
  });
}
