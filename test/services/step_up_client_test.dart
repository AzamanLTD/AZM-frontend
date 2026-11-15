// §WP-H G — wire-level proof of the client half of action-bound step-up.
//
// Runs the REAL ApiClient against a MockClient, so what is asserted is the bytes
// the backend would see: the challenge is recognised, the server's descriptor is
// echoed verbatim, the proof travels with it, and the replay carries
// x-step-up-grant with the SAME Idempotency-Key as the refused attempt.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/step_up_service.dart';

/// A stand-in for a real sha256 hex digest.
final String _digest = List<String>.filled(64, 'a').join();

final Map<String, dynamic> _descriptor = <String, dynamic>{
  'userId': 'user-1',
  'actionType': 'FIAT_WITHDRAWAL',
  'routeScope': 'POST /api/withdraw',
  'method': 'POST',
  'path': '/api/wallet/withdraw',
  'currency': 'GHS',
  'amount': '125.50',
  'destination': '0244123456',
  'resource': null,
  'idempotencyKey': 'op-1',
  'params': <String, dynamic>{},
};

String _challengeBody() => jsonEncode(<String, dynamic>{
      'success': false,
      'code': 'STEP_UP_REQUIRED',
      'message': 'This action needs a fresh verification bound to it.',
      'actionType': 'FIAT_WITHDRAWAL',
      'actionDigest': _digest,
      'action': _descriptor,
    });

const Map<String, dynamic> _withdrawBody = <String, dynamic>{
  'amount': '125.50',
  'destination': '0244123456',
};

void main() {
  // requireAuth: false — these tests assert wire construction, not token
  // plumbing (secure storage is unavailable in unit tests).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.stepUpProofProvider = null;
  });

  tearDown(() {
    ApiClient.stepUpProofProvider = null;
  });

  test('a challenge earns a grant, and the replay reuses the same key',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/api/step-up/grant')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], _descriptor);
        expect(body['totpToken'], '123456');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'stepUpGrant': 'grant-token',
            'actionDigest': _digest,
            'ttlSeconds': 120,
          }),
          201,
        );
      }
      if (request.headers[ApiClient.stepUpGrantHeader] == null) {
        return http.Response(_challengeBody(), 401);
      }
      return http.Response(jsonEncode(<String, dynamic>{'success': true}), 200);
    });

    ApiClient.stepUpProofProvider = (challenge) async {
      expect(challenge.actionType, 'FIAT_WITHDRAWAL');
      expect(challenge.action['amount'], '125.50');
      expect(challenge.summary, contains('GHS 125.50'));
      return const StepUpProof.totp('123456');
    };

    final api = ApiClient(client: client);
    final response = await api.post(
      '/api/wallet/withdraw',
      _withdrawBody,
      requireAuth: false,
      idempotencyKey: 'op-1',
    );

    expect(response.statusCode, 200);
    // challenge, grant exchange, replay
    expect(requests.length, 3);
    expect(requests[0].headers['Idempotency-Key'], 'op-1');
    expect(requests[2].headers[ApiClient.stepUpGrantHeader], 'grant-token');
    // the replay is the SAME operation, not a second one
    expect(requests[2].headers['Idempotency-Key'], 'op-1');
    expect(jsonDecode(requests[2].body), jsonDecode(requests[0].body));
  });

  test('with no UI wired the challenge surfaces unchanged and nothing retries',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(_challengeBody(), 401);
    });

    final api = ApiClient(client: client);
    await expectLater(
      api.post('/api/wallet/withdraw', _withdrawBody, requireAuth: false),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.code, 'code', 'STEP_UP_REQUIRED')),
    );
    expect(calls, 1, reason: 'no grant request, no replay');
  });

  test('cancelling the sheet leaves the original refusal intact', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(_challengeBody(), 401);
    });
    ApiClient.stepUpProofProvider = (_) async => null;

    final api = ApiClient(client: client);
    await expectLater(
      api.post('/api/wallet/withdraw', _withdrawBody, requireAuth: false),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });

  test('a refused proof reports the backend reason and never replays', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/api/step-up/grant')) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': false,
            'code': 'TOTP_UNAVAILABLE',
            'message': 'Verification is unavailable. Nothing was executed.',
          }),
          503,
        );
      }
      return http.Response(_challengeBody(), 401);
    });
    ApiClient.stepUpProofProvider = (_) async => const StepUpProof.totp('000000');

    final api = ApiClient(client: client);
    await expectLater(
      api.post('/api/wallet/withdraw', _withdrawBody, requireAuth: false),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 503)
          .having((e) => e.code, 'code', 'TOTP_UNAVAILABLE')),
    );
    // the action itself was never replayed with a grant that does not exist
    expect(
      paths.where((p) => p.endsWith('/api/wallet/withdraw')).length,
      1,
    );
  });

  test('a password proof replaces the code and never carries both', () async {
    Map<String, dynamic>? grantBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/step-up/grant')) {
        grantBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'stepUpGrant': 'grant-token',
            'actionDigest': _digest,
          }),
          201,
        );
      }
      if (request.headers[ApiClient.stepUpGrantHeader] == null) {
        return http.Response(_challengeBody(), 401);
      }
      return http.Response('{}', 200);
    });
    ApiClient.stepUpProofProvider = (_) async =>
        const StepUpProof.password('correct horse battery staple');

    final api = ApiClient(client: client);
    await api.post('/api/wallet/withdraw', _withdrawBody, requireAuth: false);

    expect(grantBody, isNotNull);
    expect(grantBody!['password'], 'correct horse battery staple');
    expect(grantBody!.containsKey('totpToken'), isFalse);
  });
}
