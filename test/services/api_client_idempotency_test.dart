// =============================================================================
// r42 CROSS-REPO INTEGRATION CONTRACT — HTTP Idempotency-Key on financial POSTs
//
// The backend shared financial idempotency authority (AZM-backend PR #311)
// requires an `Idempotency-Key` header on every protected mutation and
// rejects keyless requests with 400 IDEMPOTENCY_KEY_REQUIRED before the
// handler runs. These tests pin the frontend half of that wire contract:
//
//   1. Representative protected operations send the header.
//   2. One logical operation has ONE identity — where the body carries a
//      legacy clientRequestId, the HTTP header carries the same value.
//   3. A deliberate retry of the same logical operation reuses the same key.
//   4. A new logical operation gets a new key.
//   5. Non-financial routes (e.g. /wallet/saved, de-mounted from the
//      authority in backend §9.5) keep working without a key.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/idempotency_key.dart';

/// Captures every outgoing request so assertions can inspect exact wire
/// headers, exactly like the backend middleware sees them.
class _Recorder {
  final requests = <http.Request>[];
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return http.Response(
      jsonEncode({'success': true}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  // requireAuth: false everywhere — these tests assert wire construction,
  // not token plumbing (secure storage is unavailable in unit tests).

  test('trade initiation sends the HTTP Idempotency-Key header', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    await api.postFinancial('/trades/initiate', {
      'adId': 'ad_123',
      'amountCrypto': 5.0,
      'amountFiat': 100.0,
      'paymentMethod': 'MOMO',
    }, idempotencyKey: IdempotencyKey.generate(), requireAuth: false);

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
    }, idempotencyKey: IdempotencyKey.generate(), requireAuth: false);

    expect(rec.requests.single.headers['Idempotency-Key'], isNotEmpty);
    expect(rec.requests.single.url.path, endsWith('/api/wallet/withdraw'));
  });

  test('savings deposit: one stable logical key — header equals the body '
      'clientRequestId (one operation, one identity)', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    // The exact pattern savings_goal_sheet._deposit uses: the Phase H12
    // clientRequestId doubles as the HTTP Idempotency-Key.
    final requestId = IdempotencyKey.generate();
    await api.postFinancial('/savings/goals/goal_9/deposit', {
      'amountGhs': 25.0,
      'clientRequestId': requestId,
    }, idempotencyKey: requestId, requireAuth: false);

    final req = rec.requests.single;
    expect(req.headers['Idempotency-Key'], requestId);
    expect(jsonDecode(req.body)['clientRequestId'], requestId);
    // The two identities cannot diverge — they are literally the same value.
    expect(req.headers['Idempotency-Key'],
        jsonDecode(req.body)['clientRequestId']);
  });

  test('friend transfer: one stable logical key — header equals the body '
      'clientRequestId', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    // The exact pattern FriendService.sendFunds uses.
    final requestId = IdempotencyKey.generate();
    await api.postFinancial('/friends/transfer/send', {
      'friendshipId': 'fr_1',
      'amount': 10.0,
      'clientRequestId': requestId,
    }, idempotencyKey: requestId, requireAuth: false);

    final req = rec.requests.single;
    expect(req.headers['Idempotency-Key'], requestId);
    expect(jsonDecode(req.body)['clientRequestId'], requestId);
  });

  test('a deliberate retry of the same logical operation reuses the same key '
      '(identical header bytes on every attempt)', () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    final logicalKey = IdempotencyKey.generate();
    final body = {'tradeId': 'trade_77'};
    // First attempt, and the user-driven retry of the SAME logical action.
    await api.postFinancial('/trades/accept', body,
        idempotencyKey: logicalKey, requireAuth: false);
    await api.postFinancial('/trades/accept', body,
        idempotencyKey: logicalKey, requireAuth: false);

    expect(rec.requests, hasLength(2));
    expect(rec.requests[0].headers['Idempotency-Key'],
        rec.requests[1].headers['Idempotency-Key']);
    expect(rec.requests[0].headers['Idempotency-Key'], logicalKey);
    // And the body is byte-identical too, so the backend fingerprint matches.
    expect(rec.requests[0].body, rec.requests[1].body);
  });

  test('a new logical operation gets a new key (no accidental key reuse)',
      () async {
    final keys = <String>{};
    for (var i = 0; i < 100; i++) {
      keys.add(IdempotencyKey.generate());
    }
    expect(keys, hasLength(100));
    // RFC 4122 v4 shape — the backend derives economic dedup keys from
    // this value, so a malformed key would poison the whole contract.
    final sample = keys.first;
    expect(
        sample,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
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
            idempotencyKey: '', requireAuth: false),
        throwsArgumentError);
    expect(
        () => api.postFinancial('/wallet/withdraw', {'amount': 1.0},
            idempotencyKey: '   ', requireAuth: false),
        throwsArgumentError);
    // Nothing was sent — the client never fires a request the backend
    // would reject with 400 IDEMPOTENCY_KEY_REQUIRED.
    expect(rec.requests, isEmpty);
  });

  test('plain post() does not invent an Idempotency-Key when none is passed',
      () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);

    await api.post('/users/onboarding/complete', {'step': 'done'},
        requireAuth: false);
    expect(rec.requests.single.headers.containsKey('Idempotency-Key'),
        isFalse);
  });
}
