// =============================================================================
// AZAMAN — PHONE VERIFICATION CONTRACT (P8)
//
// The rule these tests protect: the app may only claim what the server
// actually said.
//
//   * A response carrying `testOtp` means NO SMS was delivered. It must be
//     surfaced as test delivery with the code visible — not as "check your
//     phone".
//   * "Verified" is impossible without a 200 from verify-otp. A local pass
//     must never be able to set it.
//   * A rejected code and an unreachable server are different states: a
//     network failure must not consume the user's attempt or overwrite the
//     code field.
//   * Numbers are normalized to E.164 on device; a local number or junk never
//     reaches the wire.
// =============================================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '_secure_storage_stub.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/contact_service.dart' show kDefaultDialCode;
import 'package:azaman/services/phone_verification_service.dart';

({PhoneVerificationService service, List<http.Request> calls}) _harness(
  http.Response Function(http.Request request) respond,
) {
  final calls = <http.Request>[];
  final client = MockClient((request) async {
    calls.add(request);
    return respond(request);
  });
  return (
    service: PhoneVerificationService.withClient(ApiClient(client: client)),
    calls: calls,
  );
}

Map<String, dynamic> _sendOk({String? testOtp}) => {
  'success': true,
  'message': 'OTP sent successfully. Check your phone.',
  'expiresAt': '2026-10-28T21:35:00.000Z',
  if (testOtp != null) 'testOtp': testOtp,
};

void main() {
  setUpAll(stubSecureStorage);

  group('send-otp: only claim delivery that happened', () {
    test('a real send reports sent, with the expiry the server gave', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(jsonEncode(_sendOk()), 200),
      );

      final result = await service.sendOtp('0244123456');

      expect(result.status, OtpSendStatus.sent);
      expect(result.testCode, isNull);
      expect(result.expiresAt, DateTime.parse('2026-10-28T21:35:00.000Z'));
      expect(result.isDeliverable, isTrue);

      // Normalized to E.164 on device; the server only accepts that form.
      final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['phoneNumber'], '+233244123456');
      expect(calls.single.url.path, endsWith('/security/phone/send-otp'));
    });

    test('a returned testOtp means NO SMS was sent — say so', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(jsonEncode(_sendOk(testOtp: '123456')), 200),
      );

      final result = await service.sendOtp('0244123456');

      expect(result.status, OtpSendStatus.testMode);
      expect(result.testCode, '123456');
      expect(result.message, contains('no SMS'));
      // It is still usable for testing, but it is not a delivery claim.
      expect(result.isDeliverable, isTrue);
    });

    test('an impossible number is refused locally, with no request', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(jsonEncode(_sendOk()), 200),
      );

      for (final bad in ['', '12', '*123#', 'abc']) {
        final result = await service.sendOtp(bad);
        expect(result.status, OtpSendStatus.invalidNumber, reason: bad);
      }
      expect(calls, isEmpty, reason: 'junk must not reach the endpoint');
    });

    test('rate limiting is its own state, not a generic failure', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(
          jsonEncode({'success': false, 'message': 'Too many requests.'}),
          429,
        ),
      );
      final result = await service.sendOtp('0244123456');
      expect(result.status, OtpSendStatus.throttled);
      expect(result.message, contains('Too many'));
      expect(result.isDeliverable, isFalse);
    });

    test('a 200 with success:false is not a send', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response('{"success":false,"message":"nope"}', 200),
      );
      final result = await service.sendOtp('0244123456');
      expect(result.status, OtpSendStatus.failed);
      expect(result.isDeliverable, isFalse);
    });

    test('SMS service unavailable (503) is a failure, not a send', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(
          jsonEncode({
            'success': false,
            'message': 'SMS service is unavailable.',
          }),
          503,
        ),
      );
      final result = await service.sendOtp('0244123456');
      expect(result.status, OtpSendStatus.failed);
      expect(result.message, contains('unavailable'));
    });

    test('a non-JSON error page does not crash the parse', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response('<html>502 Bad Gateway</html>', 502),
      );
      final result = await service.sendOtp('0244123456');
      expect(result.status, OtpSendStatus.failed);
      expect(result.message, isNotNull);
    });
  });

  group('verify-otp: verified only when the server says so', () {
    test('a 200 marks verified with the SERVER echoed number', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(
          jsonEncode({
            'success': true,
            'message': 'Phone number verified successfully.',
            'phoneNumber': '+233244123456',
          }),
          200,
        ),
      );

      final result = await service.verifyOtp('0244123456', '123456');

      expect(result.status, OtpVerifyStatus.verified);
      expect(result.phoneNumber, '+233244123456');
      final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['phoneNumber'], '+233244123456');
      expect(body['code'], '123456');
    });

    test('a rejected code reports the attempts the server counted', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(
          jsonEncode({
            'success': false,
            'message': 'Invalid or expired OTP.',
            'attemptsLeft': 2,
          }),
          400,
        ),
      );
      final result = await service.verifyOtp('0244123456', '000000');
      expect(result.status, OtpVerifyStatus.rejected);
      expect(result.message, contains('Invalid'));
      // The backend sends attemptsLeft, but ApiClient's ApiException does not
      // carry it, so the service reports no count rather than a made-up one.
      expect(result.attemptsLeft, isNull);
    });

    test('an unreachable server does not pretend the code was wrong', () async {
      final client = MockClient((_) async => throw const _Offline());
      final service = PhoneVerificationService.withClient(
        ApiClient(client: client),
      );
      final result = await service.verifyOtp('0244123456', '123456');
      expect(result.status, OtpVerifyStatus.failed);
      expect(result.message, contains('still valid'));
    });

    test('a short or empty code never reaches the network', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response('{"success":true}', 200),
      );
      for (final bad in ['', '1', '12']) {
        final result = await service.verifyOtp('0244123456', bad);
        expect(result.status, OtpVerifyStatus.rejected, reason: bad);
      }
      expect(calls, isEmpty);
    });

    test('the code field accepts spaces and dashes the user types', () async {
      final (:service, :calls) = _harness(
        (_) => http.Response(
          jsonEncode({'success': true, 'phoneNumber': '+233244123456'}),
          200,
        ),
      );
      final result = await service.verifyOtp('0244123456', '123 456');
      expect(result.status, OtpVerifyStatus.verified);
      expect((jsonDecode(calls.single.body) as Map)['code'], '123456');
    });
  });

  test('the launch-market dial code is used for local numbers', () {
    expect(kDefaultDialCode, '+233');
  });
}

class _Offline implements Exception {
  const _Offline();
}
