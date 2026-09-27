// =============================================================================
// r42 — DURABLE FINANCIAL OPERATION REGISTRY (audit close-out regression)
//
// The cross-repo audit's required proofs, in order:
//
//   1. arming a logical action creates a durable pending entry;
//   2. re-arming the SAME logical action (same fingerprint) returns the
//      SAME key — including after full simulated process death;
//   3. a genuinely NEW action (fresh logical id) gets a fresh key K2 ≠ K1;
//   4. a materially different body under the same logical id is a
//      GENUINELY NEW action → fresh key (the fingerprint separates);
//   5. network error / timeout → the entry is retained; the retry re-arms
//      with the SAME key;
//   6. 2xx (terminal completion) → the entry is retired; the next arm
//      mints a fresh key;
//   7. a definitive pre-economic 4xx (400/403/404/422) → retired; the
//      corrected retry is a genuinely new action with a fresh key;
//   8. 401 (auth incomplete) → retained; the post-auth retry reuses the
//      same key;
//   9. 409 (replay / in-flight) → retained; the retry converges;
//  10. terminal completion removes the pending entry from storage.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_action_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // A fresh, EMPTY store per test = a fresh application install.
    SharedPreferences.setMockInitialValues({});
  });

  group('DurableActionRegistry', () {
    test('1. arming creates a durable pending entry', () async {
      final k = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      expect(k, isNotEmpty);
      final entry = await DurableActionRegistry.pending('withdrawal.fiat');
      expect(entry, isNotNull);
      expect(entry!['k'], k);
      expect(entry['e'], '/withdraw/fiat');
      expect(entry['s'], 'pending');
    });

    test('2. re-arming the same logical action returns the SAME key — '
        'including after full process death', () async {
      final req = {'amount': 10.0, 'recipientPhone': '+233200000000'};
      final k1 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: req);
      // "Process death": nothing survives but the persisted storage.
      // (The mock store IS the persistence — a new registry usage reads it.)
      final k2 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: Map<String, dynamic>.from(req));
      expect(k2, k1);
      // Key order in the map must not matter — the canonical form sorts.
      final k3 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'recipientPhone': '+233200000000', 'amount': 10.0});
      expect(k3, k1);
    });

    test('3. a genuinely new action (fresh logical id) gets a fresh key',
        () async {
      final k1 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      final k2 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.wallet',
          endpoint: '/wallet/withdraw',
          request: {'amount': 10.0});
      expect(k2, isNot(k1));
    });

    test('4. a materially different body under the same logical id is a '
        'GENUINELY NEW action → fresh key', () async {
      final k1 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      final k2 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 25.0});
      expect(k2, isNot(k1),
          reason: 'a different amount is a different financial operation');
    });

    test('4b. the legacy clientRequestId field does NOT enter the '
        'fingerprint (it carries the key)', () async {
      final k1 = await DurableActionRegistry.arm(
          logicalActionId: 'savings.goal.deposit',
          endpoint: '/savings/deposit',
          request: {'amountGhs': 5.0, 'clientRequestId': 'aaa'});
      final k2 = await DurableActionRegistry.arm(
          logicalActionId: 'savings.goal.deposit',
          endpoint: '/savings/deposit',
          request: {'amountGhs': 5.0, 'clientRequestId': 'bbb'});
      expect(k2, k1);
    });

    test('10. terminal completion removes the pending entry', () async {
      await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      await DurableActionRegistry.retire('withdrawal.fiat');
      expect(await DurableActionRegistry.pending('withdrawal.fiat'), isNull);
      // And the next arm mints fresh.
      final k1 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      await DurableActionRegistry.retire('withdrawal.fiat');
      final k2 = await DurableActionRegistry.arm(
          logicalActionId: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 10.0});
      expect(k2, isNot(k1));
    });

    test('9 (registry level). concurrent arms of the same action id are '
        'linearized to ONE identity (pending entry read-back)', () async {
      final req = {'amount': 10.0};
      final results = await Future.wait([
        DurableActionRegistry.arm(
            logicalActionId: 'withdrawal.fiat',
            endpoint: '/withdraw/fiat',
            request: req),
        DurableActionRegistry.arm(
            logicalActionId: 'withdrawal.fiat',
            endpoint: '/withdraw/fiat',
            request: req),
        DurableActionRegistry.arm(
            logicalActionId: 'withdrawal.fiat',
            endpoint: '/withdraw/fiat',
            request: req),
      ]);
      expect(results.toSet(), hasLength(1),
          reason: 'one pending entry, one identity');
    });

    test('the armed key is RFC 4122 v4-shaped (the backend derives '
        'economic dedup keys from it)', () async {
      final k = await DurableActionRegistry.arm(
          logicalActionId: 'x', endpoint: '/x', request: {});
      expect(
          k,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('postFinancial durable lifecycle (the helper owns the lifecycle)',
        () {
    const action = 'test.lifecycle.withdraw';
    const body = {'amount': 50.0, 'recipientPhone': '+233200000000'};

    test('5. network error / timeout → entry retained; the retry re-arms '
        'with the SAME key', () async {
      final keys = <String>[];
      var attempts = 0;
      final api = ApiClient(client: MockClient((request) async {
        attempts++;
        keys.add(request.headers['Idempotency-Key']!);
        throw http.ClientException('connection reset');
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<http.ClientException>()));
      expect(attempts, 1);
      // The pending entry survived the failure.
      final entry = await DurableActionRegistry.pending(action);
      expect(entry, isNotNull);
      expect(entry!['k'], keys.single);
    });

    test('6. 2xx (terminal) → entry retired; the next arm mints fresh',
        () async {
      final keys = <String>[];
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(jsonEncode({'success': true}), 200,
            headers: {'content-type': 'application/json'});
      }));
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(await DurableActionRegistry.pending(action), isNull);
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys, hasLength(2));
      expect(keys[1], isNot(keys[0]));
    });

    test('7. definitive pre-economic 4xx (400) → retired; the corrected '
        'retry is a genuinely new action with a fresh key', () async {
      final keys = <String>[];
      var status = 400;
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(
            jsonEncode({'message': 'invalid amount'}), status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      expect(await DurableActionRegistry.pending(action), isNull);
      status = 200;
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys[1], isNot(keys[0]));
    });

    test('8. 401 (auth incomplete) → retained; the post-auth retry reuses '
        'the SAME key', () async {
      final keys = <String>[];
      var status = 401;
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(jsonEncode({'message': 'no token'}), status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      expect(await DurableActionRegistry.pending(action), isNotNull);
      status = 200;
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys[1], keys[0],
          reason: 'auth retry is the same logical action');
    });

    test('9. 409 (replay / in-flight) → retained; the retry converges',
        () async {
      final keys = <String>[];
      var status = 409;
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(
            jsonEncode({'code': 'IDEMPOTENCY_IN_PROGRESS'}), status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      expect(await DurableActionRegistry.pending(action), isNotNull);
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      expect(keys[1], keys[0]);
    });

    test('429 (rate limit) → retained — the throttled retry is the same '
        'logical action', () async {
      final keys = <String>[];
      var status = 429;
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(jsonEncode({'message': 'slow down'}), status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      status = 200;
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys[1], keys[0]);
    });

    test('5xx (unknown server state) → retained; the retry MUST reuse the '
        'same key (the mutation may have committed)', () async {
      final keys = <String>[];
      var status = 500;
      final api = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(jsonEncode({'message': 'oops'}), status,
            headers: {'content-type': 'application/json'});
      }));
      await expectLater(
          api.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<ApiException>()));
      status = 200;
      await api.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys[1], keys[0]);
    });

    test('full scenario: lost response + process death + restart → the '
        'same key is sent again (the whole point)', () async {
      final keys = <String>[];
      // First "process": network error after arming.
      final api1 = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        throw http.ClientException('dropped');
      }));
      await expectLater(
          api1.postFinancial('/withdraw/fiat', body,
              logicalActionId: action, requireAuth: false),
          throwsA(isA<http.ClientException>()));
      // Second "process": brand-new client, only persisted state survives.
      final api2 = ApiClient(client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return http.Response(
            jsonEncode({'success': true, 'withdrawal': {'id': 1}}), 201,
            headers: {'content-type': 'application/json'});
      }));
      await api2.postFinancial('/withdraw/fiat', body,
          logicalActionId: action, requireAuth: false);
      expect(keys, hasLength(2));
      expect(keys[1], keys[0],
          reason: 'the restarted app must re-send the SAME durable identity');
      expect(await DurableActionRegistry.pending(action), isNull,
          reason: '201 → terminal, entry retired');
    });
  });
}
