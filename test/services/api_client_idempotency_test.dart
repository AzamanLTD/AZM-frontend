// =============================================================================
// r42 CROSS-REPO INTEGRATION CONTRACT — HTTP Idempotency-Key on financial POSTs
//
// The backend shared financial idempotency authority (AZM-backend PR #311)
// requires an `Idempotency-Key` header on every protected mutation and
// rejects keyless requests with 400 IDEMPOTENCY_KEY_REQUIRED before the
// handler runs. These tests pin the frontend half of that wire contract,
// now backed by the DURABLE registry (2026-09-27 audit close-out):
//
//   1. Representative protected operations send the header.
//   2. One logical operation has ONE identity — where the body carries a
//      legacy clientRequestId, postFinancial OVERWRITES it with the same
//      durable registry key the header carries.
//   3. A retry of the same logical operation reuses the same key — even
//      across a simulated app restart (fresh SharedPreferences state is
//      NOT the mechanism; the persisted pending entry is).
//   4. A new logical operation gets a new key.
//   5. Non-financial routes (e.g. /wallet/saved, de-mounted from the
//      authority in backend §9.5) keep working without a key.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';

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

void main() {
  // requireAuth: false everywhere — these tests assert wire construction,
  // not token plumbing (secure storage is unavailable in unit tests).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('trade initiation sends the HTTP Idempotency-Key header', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    await api.postFinancial('/trades/initiate', {
      'adId': 'ad_123',
      'amountCrypto': 5.0,
      'amountFiat': 100.0,
      'paymentMethod': 'MOMO',
    }, logicalActionId: 'test.trade.initiate', requireAuth: false);

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
    }, logicalActionId: 'test.wallet.withdraw', requireAuth: false);

    expect(rec.requests.single.headers['Idempotency-Key'], isNotEmpty);
    expect(rec.requests.single.url.path, endsWith('/api/wallet/withdraw'));
  });

  test('savings deposit: one durable identity — header equals the body '
      'clientRequestId (one operation, one identity)', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    // The exact pattern savings_goal_sheet._deposit uses: the legacy
    // Phase H12 clientRequestId placeholder is OVERWRITTEN by
    // postFinancial with the durable registry key.
    await api.postFinancial('/savings/goals/goal_9/deposit', {
      'amountGhs': 25.0,
      'clientRequestId': '',
    }, logicalActionId: 'test.savings.deposit', requireAuth: false);

    final req = rec.requests.single;
    final headerKey = req.headers['Idempotency-Key'];
    expect(headerKey, isNotNull);
    expect(jsonDecode(req.body)['clientRequestId'], headerKey);
    // The two identities cannot diverge — they are literally the same value.
    expect(headerKey, jsonDecode(req.body)['clientRequestId']);
  });

  test('a deliberate retry of the same logical operation reuses the same '
      'key — even across a full simulated process restart', () async {
    // First process lifetime: send, network error (no server answer —
    // the connection died, nothing came back).
    final rec1Requests = <http.Request>[];
    final rec1 = MockClient((request) async {
      rec1Requests.add(request);
      throw http.ClientException('Server unreachable');
    });
    final api1 = ApiClient(client: rec1);
    final body = {'tradeId': 'trade_77'};
    await expectLater(
        api1.postFinancial('/trades/accept', body,
            logicalActionId: 'test.trade.accept.restart', requireAuth: false),
        throwsA(isA<http.ClientException>()));
    final firstKey = rec1Requests.single.headers['Idempotency-Key'];

    // "Process death": a brand-new ApiClient — the ONLY thing carried
    // over is the persisted registry state (mock storage).
    final rec2 = _Recorder();
    final api2 = ApiClient(client: rec2.client);
    await api2.postFinancial('/trades/accept', body,
        logicalActionId: 'test.trade.accept.restart', requireAuth: false);

    expect(rec2.requests.single.headers['Idempotency-Key'], firstKey,
        reason: 'the durable pending entry must survive process death');
    // And the body is byte-identical too, so the backend fingerprint matches.
    expect(rec1Requests.single.body, rec2.requests.single.body);
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
            logicalActionId: '  ', requireAuth: false),
        throwsArgumentError);
    expect(rec.requests, isEmpty,
        reason: 'nothing may reach the wire without a durable identity');
  });
}
