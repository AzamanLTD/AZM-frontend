// WP-H action-bound step-up grant — the full protocol, at the API level.
//
// Each test drives real production code (StepUpGrantProtocol and, where the
// wire matters, ApiClient.postFinancial with an injected http.Client), so the
// assertions are about what the app transmits, not about a mock's shape.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/utils/durable_operation_registry.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/financial_step_up.dart';
import 'package:azaman/services/step_up_grant.dart';

const _digest = 'digest-abc-123';

Map<String, dynamic> _challengeBody({
  String digest = _digest,
  String amount = '125.00',
  String? destination = '0244000000',
}) => {
      'success': false,
      'code': 'STEP_UP_REQUIRED',
      'message': 'This action needs a fresh verification bound to it.',
      'actionType': 'FIAT_WITHDRAWAL',
      'actionDigest': digest,
      'action': {
        'userId': 'u-1',
        'actionType': 'FIAT_WITHDRAWAL',
        'routeScope': 'WITHDRAWAL',
        'method': 'POST',
        'path': '/api/withdrawals',
        'currency': 'GHS',
        'amount': amount,
        'destination': destination,
        'resource': null,
        'idempotencyKey': 'op-key-1',
        'params': <String, dynamic>{},
      },
    };

/// A transport that answers the grant endpoint from a scripted queue.
class _ScriptedTransport {
  _ScriptedTransport(this.responses);
  final List<StepUpHttpResult> responses;
  final List<Map<String, dynamic>> sentBodies = [];
  final List<String> sentPaths = [];

  Future<StepUpHttpResult> call(String path, Map<String, dynamic> body) async {
    sentPaths.add(path);
    sentBodies.add(Map<String, dynamic>.from(body));
    if (responses.isEmpty) {
      throw StateError('unexpected grant call');
    }
    return responses.removeAt(0);
  }
}

void main() {
  // The wire tests drive the real durable-operation registry, which needs a
  // binding and an account namespace; these assertions are about wire shape,
  // so authentication is disabled and the namespace is pinned.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiClient.operationAccountOverride = () async => 'test-account';
  });

  tearDown(() {
    FinancialStepUp.uninstall();
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  group('challenge parsing', () {
    test('1. a STEP_UP_REQUIRED body becomes a challenge with the exact action', () {
      final challenge = StepUpGrantChallenge.fromBody(_challengeBody());
      expect(challenge, isNotNull);
      expect(challenge!.actionType, 'FIAT_WITHDRAWAL');
      expect(challenge.actionDigest, _digest);
      expect(challenge.action['amount'], '125.00');
      expect(challenge.action['idempotencyKey'], 'op-key-1');
    });

    test('a malformed body is never turned into a challenge', () {
      expect(StepUpGrantChallenge.fromBody(null), isNull);
      expect(StepUpGrantChallenge.fromBody({'actionDigest': 'd'}), isNull);
      expect(StepUpGrantChallenge.fromBody({'action': {}}), isNull);
    });
  });

  group('factor discovery', () {
    test('2. the grant endpoint decides the factor; the probe sends no credential', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 200,
          body: {'success': true, 'stepUpGrant': 'tok-1', 'actionDigest': _digest, 'ttlSeconds': 60},
        ),
      ]);
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '123456'));

      final grant = await StepUpGrantProtocol(send: transport.call)
          .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!);

      expect(grant.token, 'tok-1');
      // The probe carried the action and NO credential field at all.
      expect(transport.sentBodies.first.containsKey('action'), isTrue);
      expect(transport.sentBodies.first.containsKey('totpToken'), isFalse);
      expect(transport.sentBodies.first.containsKey('password'), isFalse);
      // The proof carried only the field the backend asked for.
      expect(transport.sentBodies.last['totpToken'], '123456');
      expect(transport.sentBodies.last['action'], transport.sentBodies.first['action']);
    });

    test('password factor is honoured when that is what the backend names', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: 'PASSWORD_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 200,
          body: {'stepUpGrant': 'tok-p', 'actionDigest': _digest},
        ),
      ]);
      FinancialStepUp.install((c) async {
        expect(c.factor, StepUpFactor.password);
        return StepUpCredential(StepUpFactor.password, 'hunter2');
      });
      final grant = await StepUpGrantProtocol(send: transport.call)
          .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!);
      expect(grant.token, 'tok-p');
      expect(transport.sentBodies.last['password'], 'hunter2');
      expect(transport.sentBodies.last.containsKey('totpToken'), isFalse);
    });
  });

  group('digest binding', () {
    test('3. a grant for a different digest refuses before any economic retry', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 200,
          body: {'stepUpGrant': 'tok-x', 'actionDigest': 'a-DIFFERENT-digest'},
        ),
      ]);
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '123456'));
      await expectLater(
        StepUpGrantProtocol(send: transport.call)
            .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!),
        throwsA(isA<StepUpGrantDigestMismatch>()),
      );
    });

    test('8. a changed amount produces a different digest and is refused', () async {
      final challenge = StepUpGrantChallenge.fromBody(_challengeBody())!;
      final changed = StepUpGrantChallenge.fromBody(
        _challengeBody(amount: '999.00', digest: 'digest-after-change'),
      )!;
      const grant = StepUpGrant(token: 't', actionDigest: _digest);
      expect(grant.matches(challenge), isTrue);
      expect(grant.matches(changed), isFalse);
    });
  });

  group('cancellation and refusals', () {
    test('7. dismissing the prompt sends no proof and keeps the operation identity', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
      ]);
      FinancialStepUp.install((c) async => null); // user dismissed

      await expectLater(
        StepUpGrantProtocol(send: transport.call)
            .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!),
        throwsA(isA<StepUpCancelled>()),
      );
      // Only the credential-free probe was sent. Nothing carried a proof.
      expect(transport.sentBodies, hasLength(1));
      expect(transport.sentBodies.single.containsKey('totpToken'), isFalse);
    });

    test('10. a replayed TOTP is a truthful refusal, never an automatic retry', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 409,
          code: 'TOTP_REPLAYED',
          body: {'message': 'That code was already used.'},
        ),
      ]);
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '111111'));
      await expectLater(
        StepUpGrantProtocol(send: transport.call)
            .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!),
        throwsA(isA<StepUpGrantRefused>().having((e) => e.code, 'code', 'TOTP_REPLAYED')),
      );
      // Exactly two calls: probe + one proof. No loop.
      expect(transport.sentBodies, hasLength(2));
    });

    test('11. a claim-store outage is not presented as a definitive failure', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 503,
          code: 'TOTP_CLAIM_STORE_UNAVAILABLE',
          body: {'message': 'Verification is unavailable right now.'},
        ),
      ]);
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '222222'));
      await expectLater(
        StepUpGrantProtocol(send: transport.call)
            .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!),
        throwsA(isA<StepUpGrantRefused>()
            .having((e) => e.code, 'code', 'TOTP_CLAIM_STORE_UNAVAILABLE')),
      );
      expect(transport.sentBodies, hasLength(2)); // no repeated submissions
    });

    test('9. an expired grant is refused by the endpoint and surfaces as a refusal', () async {
      final transport = _ScriptedTransport([
        const StepUpHttpResult(statusCode: 401, code: '2FA_REQUIRED'),
        const StepUpHttpResult(
          statusCode: 410,
          code: 'STEP_UP_GRANT_EXPIRED',
          body: {'message': 'That confirmation expired.'},
        ),
      ]);
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '333333'));
      await expectLater(
        StepUpGrantProtocol(send: transport.call)
            .obtain(StepUpGrantChallenge.fromBody(_challengeBody())!),
        throwsA(isA<StepUpGrantRefused>()),
      );
    });
  });

  group('credential hygiene', () {
    test('6. the grant and the credential refuse serialisation and redact toString', () {
      const grant = StepUpGrant(token: 'secret-token', actionDigest: _digest);
      expect(grant.toString(), isNot(contains('secret-token')));
      // jsonEncode wraps the refusal in JsonUnsupportedObjectError.
      expect(() => jsonEncode(grant), throwsA(isA<JsonUnsupportedObjectError>()));

      final credential = StepUpCredential(StepUpFactor.totp, '654321');
      expect(credential.toString(), isNot(contains('654321')));
      expect(() => jsonEncode(credential), throwsA(isA<JsonUnsupportedObjectError>()));
    });

    test('the challenge body never carries a credential', () {
      final challenge = StepUpGrantChallenge.fromBody(_challengeBody())!;
      final body = challenge.grantBody();
      expect(body.keys, ['action']);
    });
  });

  group('wire behaviour through ApiClient.postFinancial', () {
    test('4/5. the original request is retried with the grant header and the SAME key', () async {
      final seen = <http.Request>[];
      var call = 0;

      final mock = MockClient((request) async {
        seen.add(request);
        call++;
        if (request.url.path.endsWith('/step-up/grant')) {
          // The exact resolved route, not a suffix: '/api/api/step-up/grant'
          // also ends with '/step-up/grant' and hid a 404.
          expect(request.url.path, '/api/step-up/grant');
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          if (!decoded.containsKey('totpToken')) {
            return http.Response(
              jsonEncode({'success': false, 'code': '2FA_REQUIRED'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'stepUpGrant': 'grant-tok',
              'actionDigest': _digest,
              'ttlSeconds': 60,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // The economic endpoint: first attempt challenged, retry succeeds.
        if (call == 1) {
          return http.Response(
            jsonEncode(_challengeBody()),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'id': 'wd-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '444444'));
      final client = ApiClient(client: mock);

      final response = await client.postFinancial(
        '/api/withdrawals',
        {'amount': '125.00', 'destination': '0244000000'},
        operationType: 'WITHDRAWAL',
        requireAuth: false,
      );

      expect(response.statusCode, 200);
      final economic = seen.where((r) => r.url.path.endsWith('/withdrawals')).toList();
      expect(economic, hasLength(2));

      // 5. Same Idempotency-Key on both economic attempts.
      final k1 = economic.first.headers['Idempotency-Key'];
      final k2 = economic.last.headers['Idempotency-Key'];
      expect(k1, isNotNull);
      expect(k2, k1);

      // 4. The retry carries the grant; the first attempt did not.
      expect(economic.first.headers.containsKey('x-step-up-grant'), isFalse);
      expect(economic.last.headers['x-step-up-grant'], 'grant-tok');

      // The economic body is byte-identical (no credential injected into it).
      expect(economic.last.body, economic.first.body);
      // The grant token is never in the body.
      expect(economic.last.body, isNot(contains('grant-tok')));
    });

    test('6b. the grant token is not written into persisted operation state', () async {
      // The durable snapshot is the request body plus endpoint/key metadata;
      // assert the token never appears in what the registry would store by
      // checking the economic bodies, which are the only persisted payload.
      final bodies = <String>[];
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/step-up/grant')) {
          // The exact resolved route, not a suffix: '/api/api/step-up/grant'
          // also ends with '/step-up/grant' and hid a 404.
          expect(request.url.path, '/api/step-up/grant');
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          if (!decoded.containsKey('totpToken')) {
            return http.Response(jsonEncode({'code': '2FA_REQUIRED'}), 401,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(
            jsonEncode({'stepUpGrant': 'TOKEN-SHOULD-NOT-PERSIST', 'actionDigest': _digest}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        bodies.add(request.body);
        if (bodies.length == 1) {
          return http.Response(jsonEncode(_challengeBody()), 409,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'success': true}), 200,
            headers: {'content-type': 'application/json'});
      });
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '555555'));
      final client = ApiClient(client: mock);
      await client.postFinancial('/api/withdrawals', {'amount': '1.00'},
          operationType: 'WITHDRAWAL', requireAuth: false);
      for (final b in bodies) {
        expect(b, isNot(contains('TOKEN-SHOULD-NOT-PERSIST')));
        expect(b, isNot(contains('555555')));
      }
    });

    test('12. a lost response keeps the same operation identity for the next attempt', () async {
      final keys = <String?>[];
      var economic = 0;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/step-up/grant')) {
          // The exact resolved route, not a suffix: '/api/api/step-up/grant'
          // also ends with '/step-up/grant' and hid a 404.
          expect(request.url.path, '/api/step-up/grant');
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          if (!decoded.containsKey('totpToken')) {
            return http.Response(jsonEncode({'code': '2FA_REQUIRED'}), 401,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(
            jsonEncode({'stepUpGrant': 'g', 'actionDigest': _digest}), 200,
            headers: {'content-type': 'application/json'});
        }
        economic++;
        keys.add(request.headers['Idempotency-Key']);
        if (economic == 1) {
          return http.Response(jsonEncode(_challengeBody()), 409,
              headers: {'content-type': 'application/json'});
        }
        // The grant-protected retry loses its response.
        return http.Response('gateway timeout', 504);
      });
      FinancialStepUp.install((c) async => StepUpCredential(StepUpFactor.totp, '666666'));
      final client = ApiClient(client: mock);
      await expectLater(
        client.postFinancial('/api/withdrawals', {'amount': '2.00'},
            operationType: 'WITHDRAWAL', requireAuth: false),
        throwsA(isA<ApiException>()),
      );
      // Both attempts used one identity; the unknown outcome did not mint another.
      expect(keys, hasLength(2));
      expect(keys.last, keys.first);
    });
  });
}
