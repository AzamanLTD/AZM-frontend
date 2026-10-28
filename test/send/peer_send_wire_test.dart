// =============================================================================
// PEER SEND — WIRE CONTRACT TESTS
//
// The unified Send composer must commit through the canonical durable rail
// only: POST /api/friends/transfer/send (protect + require2FA +
// idempotency middleware on the backend). The legacy
// POST /finance/internal-transfer does not exist on any reviewed backend
// baseline — the composer must never emit it.
//
// These tests pin FriendService.sendFunds to a MockClient so the exact wire
// (route, payload, durable identity, retry convergence) is asserted, not
// trusted.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

class _Recorder {
  final requests = <http.Request>[];
  http.Response? reply;
  Object? throwOnNext;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (throwOnNext != null) {
      final Object t = throwOnNext!;
      throwOnNext = null;
      throw t;
    }
    return reply ??
        http.Response(
          jsonEncode({
            'success': true,
            'transfer': {'id': 'tx-1'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
  });
}

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockSecureStorage();
    ApiClient.operationAccountOverride = () async => 'test-account';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  test('sendFunds posts the CANONICAL rail with friendship, amount, reference '
      'and a durable identity on BOTH the header and the body', () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));

    final result = await svc.sendFunds('fs-canary', 4.5, 'lunch', 'tok');

    expect(result['success'], true, reason: '2xx returns the parsed body');
    expect(rec.requests, hasLength(1));
    final req = rec.requests.single;

    expect(
      req.url.path,
      endsWith('/friends/transfer/send'),
      reason: 'the canonical friendship rail, never /finance/internal-transfer',
    );
    expect(req.method, 'POST');

    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['friendshipId'], 'fs-canary');
    expect(body['amount'], 4.5);
    expect(body['reference'], 'lunch');

    // Durable identity: the Idempotency-Key header and the legacy
    // clientRequestId body field carry the SAME value, so a retry
    // converges on the server-side operation instead of double-debiting.
    final key = req.headers['Idempotency-Key'];
    expect(key, isNotNull);
    expect(key, isNotEmpty);
    expect(
      body['clientRequestId'],
      key,
      reason: 'header and body identity must never diverge',
    );

    // The wire NEVER touches the non-existent legacy route.
    expect(req.url.path, isNot(contains('internal-transfer')));
    for (final r in rec.requests) {
      expect(r.url.path, isNot(contains('finance/internal-transfer')));
    }
  });

  test('a timeout retry re-uses the SAME durable operation identity — never '
      'a fresh key that could double-send', () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));

    // First attempt: the network drops the response mid-flight.
    rec.throwOnNext = http.ClientException('Server unreachable');
    await expectLater(
      svc.sendFunds('fs-retry', 2.0, null, 'tok'),
      throwsA(anything),
    );

    // Retry of the SAME logical transfer (same friendship, amount).
    await svc.sendFunds('fs-retry', 2.0, null, 'tok');

    expect(rec.requests, hasLength(2), reason: 'exactly one retry attempt');
    final key1 = rec.requests[0].headers['Idempotency-Key'];
    final key2 = rec.requests[1].headers['Idempotency-Key'];
    expect(
      key2,
      key1,
      reason: 'retry must converge on the same server-side operation',
    );
    final body2 = jsonDecode(rec.requests[1].body) as Map<String, dynamic>;
    expect(body2['clientRequestId'], key1);
  });

  test('a 400 (insufficient funds) throws — never a false success', () async {
    final rec = _Recorder();
    rec.reply = http.Response(
      jsonEncode({
        'success': false,
        'message': 'Insufficient funds',
        'code': 'INSUFFICIENT_FUNDS',
      }),
      400,
    );
    final svc = FriendService.forTesting(ApiClient(client: rec.client));

    await expectLater(
      svc.sendFunds('fs-400', 9.9, null, 'tok'),
      throwsA(anything),
    );
  });

  test('no wire payload ever carries a placeholder AZM ID — the financial '
      'key is the friendship, and model construction rejects masks', () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));
    await svc.sendFunds('fs-clean', 1.0, null, 'tok');

    for (final r in rec.requests) {
      expect(r.body, isNot(contains('AZM-•••')));
      expect(r.body, isNot(contains('AZM-—')));
      expect(r.body, isNot(contains('AZM-')));
    }

    // The model is structurally incapable of holding a masked placeholder.
    expect(
      () => SendRecipient(
        username: 'someone',
        source: SendRecipientSource.azmLookup,
        azamanId: 'AZM-•••',
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => SendRecipient(
        username: 'someone',
        source: SendRecipientSource.azmLookup,
        azamanId: '',
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
