// THE UNLOCK CONTRACT, ON THE WIRE.
//
// The client may only report what the backend said. These tests drive the real
// HttpAppUnlockGateway through a MockClient and pin three things that have
// already gone wrong once:
//
//   • availability comes from capabilities, not from a settings screen;
//   • a refusal keeps the server's code AND its attemptsLeft;
//   • a 429 that carries a code is an unlock lock, not a generic rate limit.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/app_unlock_gateway.dart';

HttpAppUnlockGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) => HttpAppUnlockGateway(ApiClient(client: MockClient(handler)));

void main() {
  // The ApiClient reads the auth token from secure storage on every call, so a
  // platform-channel mock is required or the request never starts (the lesson
  // from the onboarding suite).
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('capabilities are read, never assumed', () async {
    final gateway = _gateway((request) async {
      expect(request.url.path, endsWith('/security/app-unlock/capabilities'));
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'pinConfigured': true,
            'authenticatorConfigured': false,
            'phoneVerified': true,
            'smsUnlockAvailable': false,
            'smsUnavailableReason': 'SMS_SERVICE_UNAVAILABLE',
          },
        }),
        200,
      );
    });

    final caps = await gateway.capabilities();

    expect(caps.pinConfigured, isTrue);
    expect(caps.authenticatorConfigured, isFalse);
    expect(caps.smsUnlockAvailable, isFalse);
    expect(caps.smsUnavailableReason, 'SMS_SERVICE_UNAVAILABLE');
    expect(caps.configured, [AppUnlockMethod.pin]);
    expect(caps.canUse(AppUnlockMethod.sms), isFalse);
  });

  test('a wrong PIN keeps the code and the remaining attempts', () async {
    final gateway = _gateway(
      (request) async => http.Response(
        jsonEncode({
          'success': false,
          'code': 'PIN_INVALID',
          'attemptsLeft': 3,
        }),
        401,
      ),
    );

    await expectLater(
      gateway.verifyPin('0000'),
      throwsA(
        isA<AppUnlockRefusal>()
            .having((r) => r.code, 'code', 'PIN_INVALID')
            .having((r) => r.attemptsLeft, 'attemptsLeft', 3),
      ),
    );
  });

  test('a 429 with a code is a lock, not a rate limit', () async {
    final gateway = _gateway(
      (request) async => http.Response(
        jsonEncode({'success': false, 'code': 'PIN_LOCKED', 'attemptsLeft': 0}),
        429,
      ),
    );

    await expectLater(
      gateway.verifyPin('0000'),
      throwsA(
        isA<AppUnlockRefusal>()
            .having((r) => r.code, 'code', 'PIN_LOCKED')
            .having((r) => r.attemptsLeft, 'attemptsLeft', 0),
      ),
    );
  });

  test('an accepted PIN completes and reports nothing else', () async {
    final gateway = _gateway(
      (request) async => http.Response(
        jsonEncode({
          'success': true,
          'data': {'unlocked': true, 'method': 'pin'},
        }),
        200,
      ),
    );

    await expectLater(gateway.verifyPin('1234'), completes);
  });

  test('an SMS challenge carries the server mask, never the number', () async {
    final gateway = _gateway(
      (request) async => http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'challengeId': 'ch_1',
            'maskedPhone': '+233 •• •• 1234',
            'expiresAt': '2026-10-30T12:05:00.000Z',
          },
        }),
        200,
        // The real server sends charset=utf-8; a mock without it encodes the
        // bullets as latin1 and refuses to build at all.
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final challenge = await gateway.sendSmsChallenge();

    expect(challenge.challengeId, 'ch_1');
    expect(challenge.maskedPhone, '+233 •• •• 1234');
  });

  test(
    'a capabilities failure is a refusal, never empty capability claims',
    () async {
      final gateway = _gateway(
        (request) async => http.Response(
          jsonEncode({'success': false, 'code': 'CAPABILITIES_UNAVAILABLE'}),
          503,
        ),
      );

      await expectLater(
        gateway.capabilities(),
        throwsA(
          isA<AppUnlockRefusal>().having(
            (r) => r.code,
            'code',
            'CAPABILITIES_UNAVAILABLE',
          ),
        ),
      );
    },
  );
}
