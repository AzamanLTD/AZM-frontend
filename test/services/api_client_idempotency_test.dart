// =============================================================================
// r42 CROSS-REPO INTEGRATION CONTRACT — HTTP Idempotency-Key on financial POSTs
//
// The backend shared financial idempotency authority (AZM-backend PR #311)
// requires an `Idempotency-Key` header on every protected mutation and
// rejects keyless requests with 400 IDEMPOTENCY_KEY_REQUIRED before the
// handler runs. These tests pin the frontend half of that wire contract,
// now backed by the durable OPERATION-INSTANCE registry (2026-09-27
// independent-review close-out):
//
//   1. Representative protected operations send the header.
//   2. One logical operation has ONE identity — where the body carries a
//      legacy clientRequestId, postFinancial OVERWRITES it with the same
//      durable instance key the header carries.
//   3. A retry of the same operation INSTANCE (through its ref) reuses the
//      same key — even across a simulated app restart.
//   4. A genuinely new operation instance gets a new key.
//   5. THE REVIEWER SCENARIO: withdrawal A of 50 times out, withdrawal B
//      of 75 begins, then A is retried — the retry sends A's ORIGINAL key
//      (never B's, never a fresh one).
//   6. Disposition: 2xx and definitive pre-economic 4xx retire the
//      instance; 409/5xx and network loss retain it for same-key retry.
//   7. A persistence failure blocks the request entirely (the durable
//      record must exist before the first request may leave the device).
//   8. Post-death recovery (exact-match recoverExact) resumes the unfinished
//      instance with the same key on an identical body.
//   9. Non-financial routes (e.g. /wallet/saved, de-mounted from the
//      authority in backend §9.5) keep working without a key.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Captures every outgoing request so assertions can inspect exact wire
/// headers, exactly like the backend middleware sees them.
class _Recorder {
  final requests = <http.Request>[];
  final http.Response? reply;
  _Recorder({this.reply});

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return reply ??
        http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
  });
}

http.Client _throwingClient(List<http.Request> sink) => MockClient((request) async {
      sink.add(request);
      throw http.ClientException('Server unreachable');
    });

void main() {
  // requireAuth: false everywhere — these tests assert wire construction,
  // not token plumbing (secure storage is unavailable in unit tests).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    DurableOperationRegistry.storageWriterOverride = null;
  });

  test('trade initiation sends the HTTP Idempotency-Key header', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    await api.postFinancial('/trades/initiate', {
      'adId': 'ad_123',
      'amountCrypto': 5.0,
      'amountFiat': 100.0,
      'paymentMethod': 'MOMO',
    }, operationType: 'test.trade.initiate', requireAuth: false);

    expect(rec.requests, hasLength(1));
    final key = rec.requests.single.headers['Idempotency-Key'];
    expect(key, isNotNull);
    expect(key, isNotEmpty);
    expect(key, isNot(contains(' ')));
    expect(rec.requests.single.url.path, endsWith('/api/trades/initiate'));
  });

  test('wallet withdrawal sends the HTTP Idempotency-Key header', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    await api.postFinancial('/wallet/withdraw', {
      'amount': 50.0,
      'destination': '+233200000000',
      'networkPref': 'MOMO',
    }, operationType: 'test.wallet.withdraw', requireAuth: false);

    expect(rec.requests.single.headers['Idempotency-Key'], isNotEmpty);
    expect(rec.requests.single.url.path, endsWith('/api/wallet/withdraw'));
  });

  test('savings deposit: one durable identity — header equals the body '
      'clientRequestId (one operation, one identity)', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    // The exact pattern savings_goal_sheet._deposit uses: the legacy
    // Phase H12 clientRequestId placeholder is OVERWRITTEN by
    // postFinancial with the durable instance key.
    await api.postFinancial('/savings/goals/goal_9/deposit', {
      'amountGhs': 25.0,
      'clientRequestId': '',
    }, operationType: 'test.savings.deposit', requireAuth: false);

    final req = rec.requests.single;
    final headerKey = req.headers['Idempotency-Key'];
    expect(headerKey, isNotNull);
    expect(jsonDecode(req.body)['clientRequestId'], headerKey);
    // The two identities cannot diverge — they are literally the same value.
    expect(headerKey, jsonDecode(req.body)['clientRequestId']);
  });

  test('a retry of the same operation INSTANCE (through its ref) reuses '
      'the same key — even across a full simulated process restart',
      () async {
    final ref = FinancialOperationRef();

    // First process lifetime: send, network error (no server answer —
    // the connection died, nothing came back).
    final rec1Requests = <http.Request>[];
    final api1 = ApiClient(client: _throwingClient(rec1Requests));
    final body = {'tradeId': 'trade_77'};
    await expectLater(
        api1.postFinancial('/trades/accept', body,
            operationType: 'test.trade.accept.restart',
            ref: ref,
            requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final firstKey = rec1Requests.single.headers['Idempotency-Key'];

    // "Process death": a brand-new ApiClient AND a re-seeded registry —
    // the ONLY carried state is the persisted journal plus the ref's
    // instance id (adopted from the journal by real recovery paths).
    final store = await SharedPreferences.getInstance();
    final carried = <String, Object>{
      for (final k in store.getKeys())
        if (store.get(k) != null) k: store.get(k)! as Object,
    };
    SharedPreferences.setMockInitialValues(carried);

    final rec2 = _Recorder();
    final api2 = ApiClient(client: rec2.client);
    // post-death recovery: the flow RECONSTRUCTS the request and binds the
    // unique unfinished instance whose fingerprint EXACTLY matches it
    // (DurableOperationRegistry.recoverExact — the fail-closed exact-match
    // contract that replaced the withdrawn newest-adoption rule).
    final account = await api2.operationAccount();
    final match = await DurableOperationRegistry.recoverExact(
        account: account,
        type: 'test.trade.accept.restart',
        request: body);
    expect(match, isA<DurableRecoveryUnique>(),
        reason: 'exactly one unfinished instance matches the body');
    ref.operationId = (match as DurableRecoveryUnique).operation.operationId;

    await api2.postFinancial('/trades/accept', body,
        operationType: 'test.trade.accept.restart',
        ref: ref,
        requireAuth: false);

    expect(rec2.requests.single.headers['Idempotency-Key'], firstKey,
        reason: 'the durable pending instance must survive process death');
    // And the body is byte-identical too, so the backend fingerprint matches.
    expect(rec1Requests.single.body, rec2.requests.single.body);
  });

  test('a genuinely new operation instance gets a new key (ref cleared '
      'after 2xx — the next action of the same type is a new instance)',
      () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    await api.postFinancial('/wallet/withdraw', {'amount': 50.0},
        operationType: 'test.wallet.repeat', ref: ref, requireAuth: false);
    final k1 = rec.requests[0].headers['Idempotency-Key'];

    // 2xx retired the instance and cleared the ref: a resubmit through the
    // same ref is a GENUINELY NEW action → fresh key.
    await api.postFinancial('/wallet/withdraw', {'amount': 50.0},
        operationType: 'test.wallet.repeat', ref: ref, requireAuth: false);
    final k2 = rec.requests[1].headers['Idempotency-Key'];
    expect(k1, isNot(equals(k2)));
  });

  test('REVIEWER SCENARIO: A=withdrawal 50 times out, B=withdrawal 75 '
      'begins, then A is retried — the retry sends A\'s ORIGINAL key '
      '(not B\'s, not a fresh one)', () async {
    final refA = FinancialOperationRef();
    final refB = FinancialOperationRef();

    // A: withdrawal of 50 — response lost (network error).
    final aRequests = <http.Request>[];
    final apiA = ApiClient(client: _throwingClient(aRequests));
    final bodyA = {'amount': 50.0, 'destination': '+233200000000'};
    await expectLater(
        apiA.postFinancial('/withdraw/fiat', bodyA,
            operationType: 'test.scenario.withdraw.fiat',
            ref: refA,
            requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final keyA = aRequests.single.headers['Idempotency-Key'];

    // B: a genuinely new withdrawal of 75 — independent instance.
    final bRequests = <http.Request>[];
    final apiB = ApiClient(client: _throwingClient(bRequests));
    final bodyB = {'amount': 75.0, 'destination': '+233200000000'};
    await expectLater(
        apiB.postFinancial('/withdraw/fiat', bodyB,
            operationType: 'test.scenario.withdraw.fiat',
            ref: refB,
            requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final keyB = bRequests.single.headers['Idempotency-Key'];
    expect(keyA, isNot(equals(keyB)));

    // The retry of A sends A's ORIGINAL key.
    final recA2 = _Recorder();
    final apiA2 = ApiClient(client: recA2.client);
    await apiA2.postFinancial('/withdraw/fiat', bodyA,
        operationType: 'test.scenario.withdraw.fiat',
        ref: refA,
        requireAuth: false);
    expect(recA2.requests.single.headers['Idempotency-Key'], keyA,
        reason: 'the retry of A must reuse A\'s original key');
    expect(recA2.requests.single.headers['Idempotency-Key'],
        isNot(equals(keyB)),
        reason: 'the retry of A must never send B\'s key');

    // And B is still recoverable, independent, untouched.
    final account = await apiA2.operationAccount();
    final pending = await DurableOperationRegistry.pending(
        account: account, type: 'test.scenario.withdraw.fiat');
    expect(pending, hasLength(1),
        reason: 'A answered (2xx → retired); B remains recoverable');
    expect(pending.single.key, keyB);
  });

  test('disposition: answered 2xx retires the instance and clears the ref',
      () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    await api.postFinancial('/vaults/v1/deposit', {'amountUsdc': 5},
        operationType: 'test.disposition.ok', ref: ref, requireAuth: false);

    expect(ref.operationId, isNull, reason: 'terminal completion clears the ref');
    final account = await api.operationAccount();
    expect(await DurableOperationRegistry.pending(account: account), isEmpty);
  });

  test('disposition: definitive pre-economic 4xx (400) retires the '
      'instance — a corrected retry is a genuinely new action', () async {
    final rec = _Recorder(
        reply: http.Response(jsonEncode({'error': 'bad request'}), 400));
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    await expectLater(
        api.postFinancial('/vaults/v1/deposit', {'amountUsdc': 5},
            operationType: 'test.disposition.400', ref: ref, requireAuth: false),
        throwsA(isA<ApiException>()));

    expect(ref.operationId, isNull, reason: 'pre-economic rejection released the claim');
    final account = await api.operationAccount();
    expect(await DurableOperationRegistry.pending(account: account), isEmpty);
  });

  test('disposition: 409 idempotency replay KEEPS the instance armed — '
      'the retry converges on the same server-side operation', () async {
    final rec = _Recorder(
        reply: http.Response(
            jsonEncode({'error': {'code': 'IDEMPOTENCY_IN_FLIGHT'}}), 409));
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    await expectLater(
        api.postFinancial('/trades/accept', {'tradeId': 'trade_9'},
            operationType: 'test.disposition.409', ref: ref, requireAuth: false),
        throwsA(isA<ApiException>()));
    expect(ref.operationId, isNotNull, reason: '409 keeps the claim armed');

    // Same instance: the next attempt through the ref reuses the SAME key.
    final key1 = rec.requests[0].headers['Idempotency-Key'];
    await expectLater(
        api.postFinancial('/trades/accept', {'tradeId': 'trade_9'},
            operationType: 'test.disposition.409', ref: ref, requireAuth: false),
        throwsA(isA<ApiException>()));
    expect(rec.requests[1].headers['Idempotency-Key'], key1);
  });

  test('disposition: 5xx KEEPS the instance armed — the server may have '
      'committed; the retry MUST reuse the same key', () async {
    final rec = _Recorder(
        reply: http.Response(jsonEncode({'error': 'boom'}), 500));
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    await expectLater(
        api.postFinancial('/trades/accept', {'tradeId': 'trade_9'},
            operationType: 'test.disposition.5xx', ref: ref, requireAuth: false),
        throwsA(isA<ApiException>()));
    expect(ref.operationId, isNotNull, reason: 'unknown server state retains the claim');

    final key1 = rec.requests[0].headers['Idempotency-Key'];
    await expectLater(
        api.postFinancial('/trades/accept', {'tradeId': 'trade_9'},
            operationType: 'test.disposition.5xx', ref: ref, requireAuth: false),
        throwsA(isA<ApiException>()));
    expect(rec.requests[1].headers['Idempotency-Key'], key1);
  });

  test('a materially different body through the same ref begins a NEW '
      'instance — the pending one is untouched and recoverable', () async {
    // A: withdrawal of 50 — response lost.
    final aRequests = <http.Request>[];
    final api = ApiClient(client: _throwingClient(aRequests));
    final ref = FinancialOperationRef();
    await expectLater(
        api.postFinancial('/withdraw/fiat', {'amount': 50.0},
            operationType: 'test.changed.body', ref: ref, requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final keyA = aRequests.single.headers['Idempotency-Key'];

    // The same flow ref, but a materially different body: a genuinely new
    // action — a fresh instance with a fresh key.
    final rec2 = _Recorder();
    final api2 = ApiClient(client: rec2.client);
    await api2.postFinancial('/withdraw/fiat', {'amount': 99.0},
        operationType: 'test.changed.body', ref: ref, requireAuth: false);
    final keyB = rec2.requests.single.headers['Idempotency-Key'];
    expect(keyB, isNot(equals(keyA)));

    // The ORIGINAL instance was never replaced: it remains pending with
    // its own key, recoverable by id.
    final account = await api2.operationAccount();
    final pending = await DurableOperationRegistry.pending(
        account: account, type: 'test.changed.body');
    expect(pending, hasLength(1));
    expect(pending.single.key, keyA,
        reason: 'the unfinished 50-withdrawal keeps its identity');
  });

  test('persistence invariant: a durable-record write failure blocks the '
      'request entirely — nothing reaches the wire keyless', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);
    DurableOperationRegistry.storageWriterOverride = (slot, encoded) async {
      throw Exception('disk full');
    };

    await expectLater(
        api.postFinancial('/wallet/withdraw', {'amount': 50.0},
            operationType: 'test.persist.fail', requireAuth: false),
        throwsA(isA<Exception>()));
    expect(rec.requests, isEmpty,
        reason: 'the record must exist before the first request may leave '
            'the device');
  });

  test('POST /wallet/saved keeps working WITHOUT an Idempotency-Key '
      '(backend §9.5 de-mounted this non-financial route)', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    // Exactly what saved_wallets_screen / vendor_settings_screen /
    // user_local_payment_methods do — plain keyless POST.
    await api.post('/wallet/saved', {
      'label': 'MTN MOMO',
      'address': '+233200000000',
    }, requireAuth: false);

    final req = rec.requests.single;
    expect(req.url.path, endsWith('/api/wallet/saved'));
    // The route is non-financial: no key must be required, and none is sent.
    expect(req.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('postFinancial refuses a keyless money-moving request — the '
      'requirement is structural, not convention', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    expect(
        () => api.postFinancial('/wallet/withdraw', {'amount': 1.0},
            operationType: '  ', requireAuth: false),
        throwsArgumentError);
    expect(rec.requests, isEmpty,
        reason: 'nothing may reach the wire without a durable identity');
  });

// =============================================================================
// r42 CLOSE-OUT REVIEW (2026-09-27) — the application-level post-death
// recovery regression. The earlier A/B test kept refs alive in memory; the
// reviewer required proving that A SPECIFICALLY is recoverable after full
// process death while a NEWER unfinished B of the same type also exists.
// =============================================================================

  test('CLOSE-OUT REGRESSION: A=50 and B=75 both lose their responses; '
      'process dies; reconstructing A recovers A (NOT the newer B), the '
      'wire retry sends K1, B stays pending with K2, then B recovers with '
      'K2 — no third key is ever sent', () async {
    const type = 'test.closeout.withdrawal.fiat';
    final bodyA = {'amount': 50, 'recipientPhone': '+233200000000'};
    final bodyB = {'amount': 75, 'recipientPhone': '+233200000000'};

    // First process lifetime: A then B, both with lost responses.
    final sent1 = <http.Request>[];
    final api1 = ApiClient(client: _throwingClient(sent1));
    await expectLater(
        api1.postFinancial('/withdraw/fiat', bodyA,
            operationType: type, requireAuth: false),
        throwsA(isA<http.ClientException>()));
    await expectLater(
        api1.postFinancial('/withdraw/fiat', bodyB,
            operationType: type, requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final k1 = sent1[0].headers['Idempotency-Key'];
    final k2 = sent1[1].headers['Idempotency-Key'];
    expect(k1, isNot(equals(k2)));

    // FULL process death: new client, re-seeded journal, NO refs survive.
    final store = await SharedPreferences.getInstance();
    final carried = <String, Object>{
      for (final k in store.getKeys())
        if (store.get(k) != null) k: store.get(k)! as Object,
    };
    SharedPreferences.setMockInitialValues(carried);

    // Reconstruction of the user's intended A request → EXACT recovery.
    final api2 = ApiClient(client: _Recorder().client);
    final account = await api2.operationAccount();
    final matchA = await DurableOperationRegistry.recoverExact(
        account: account, type: type, request: bodyA);
    expect(matchA, isA<DurableRecoveryUnique>(),
        reason: 'recovery must find A specifically — not B because B is newer');
    final opA = (matchA as DurableRecoveryUnique).operation;
    expect(opA.key, k1);

    final recA = _Recorder();
    final apiA = ApiClient(client: recA.client);
    await apiA.postFinancial('/withdraw/fiat', bodyA,
        operationType: type,
        ref: FinancialOperationRef(operationId: opA.operationId),
        requireAuth: false);
    expect(recA.requests.single.headers['Idempotency-Key'], k1,
        reason: 'the recovered A retry MUST send A\'s original key');

    // B is untouched and independently recoverable with K2.
    final matchB = await DurableOperationRegistry.recoverExact(
        account: account, type: type, request: bodyB);
    expect(matchB, isA<DurableRecoveryUnique>());
    final opB = (matchB as DurableRecoveryUnique).operation;
    expect(opB.key, k2);

    final recB = _Recorder();
    final apiB = ApiClient(client: recB.client);
    await apiB.postFinancial('/withdraw/fiat', bodyB,
        operationType: type,
        ref: FinancialOperationRef(operationId: opB.operationId),
        requireAuth: false);
    expect(recB.requests.single.headers['Idempotency-Key'], k2);

    // Nothing was orphaned or tripled: exactly the two original keys exist.
    final pending =
        await DurableOperationRegistry.pending(account: account, type: type);
    expect(pending.map((o) => o.key).toSet(), {k1, k2});
  });

  test('CLOSE-OUT: identical bodies both lost → recovery is AMBIGUOUS and '
      'fails closed on the wire too — no key is sent until the instance is '
      'chosen explicitly', () async {
    const type = 'test.closeout.deposit.duplicate';
    final body = {'amount': 10, 'goalId': 'goal_1'};

    final sent1 = <http.Request>[];
    final api1 = ApiClient(client: _throwingClient(sent1));
    await expectLater(
        api1.postFinancial('/savings/deposit', body,
            operationType: type, requireAuth: false),
        throwsA(isA<http.ClientException>()));
    await expectLater(
        api1.postFinancial('/savings/deposit', body,
            operationType: type, requireAuth: false),
        throwsA(isA<http.ClientException>()));

    // Process death.
    final store = await SharedPreferences.getInstance();
    final carried = <String, Object>{
      for (final k in store.getKeys())
        if (store.get(k) != null) k: store.get(k)! as Object,
    };
    SharedPreferences.setMockInitialValues(carried);

    final api2 = ApiClient(client: _Recorder().client);
    final account = await api2.operationAccount();
    final match = await DurableOperationRegistry.recoverExact(
        account: account, type: type, request: body);
    expect(match, isA<DurableRecoveryAmbiguous>(),
        reason: 'the recovery contract must not guess between two '
            'identical unfinished operations');
    expect((match as DurableRecoveryAmbiguous).candidates.length, 2);
  });

  test('CLOSE-OUT: retryRecovered (the security-settings recovery surface) '
      'replays the STORED snapshot of a post-death instance under its '
      'ORIGINAL key — exact by construction', () async {
    const type = 'test.closeout.recovered.replay';
    final body = {'amount': 42, 'recipientPhone': '+233200000001'};

    final sent1 = <http.Request>[];
    final api1 = ApiClient(client: _throwingClient(sent1));
    await expectLater(
        api1.postFinancial('/withdraw/fiat', body,
            operationType: type, requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final originalKey = sent1.single.headers['Idempotency-Key'];

    // Process death.
    final store = await SharedPreferences.getInstance();
    final carried = <String, Object>{
      for (final k in store.getKeys())
        if (store.get(k) != null) k: store.get(k)! as Object,
    };
    SharedPreferences.setMockInitialValues(carried);

    // The user explicitly resumes the listed instance.
    final account = await ApiClient(client: _Recorder().client).operationAccount();
    final ops = await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops.length, 1);

    final rec = _Recorder();
    final api2 = ApiClient(client: rec.client);
    await api2.retryRecovered(ops.single, requireAuth: false);

    expect(rec.requests.single.headers['Idempotency-Key'], originalKey,
        reason: 'the replay must reuse the ORIGINAL instance key');
    expect(jsonDecode(rec.requests.single.body)['amount'], 42);
  });

}