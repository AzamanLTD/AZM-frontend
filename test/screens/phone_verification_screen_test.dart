// =============================================================================
// AZAMAN — PHONE VERIFICATION SCREEN (P8)
//
// What these tests protect, in the order a person meets them:
//
//   * The number stage asks for a number and offers "Do this later". Leaving
//     without verifying is possible and the app does not punish it.
//   * A test-mode response shows a banner saying NO SMS was sent, plus the
//     code. The old behaviour would have said "check your phone" at a phone
//     that never rang.
//   * A refusal on send keeps the person on the number stage with the reason
//     visible — not a code box for a code that was never issued.
//   * "Number verified" appears only after the service reports verified. A
//     rejected code shows the error and stays on the code stage.
//   * Verification is described as the number, never as wallet ownership.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/screens/auth/phone_verification_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/phone_verification_service.dart';

import '../support/secure_storage_stub.dart';

PhoneVerificationService _serviceThat(
  http.Response Function(http.Request request) respond,
) {
  return PhoneVerificationService.withClient(
    ApiClient(client: MockClient((r) async => respond(r))),
  );
}

Future<void> _pump(
  WidgetTester tester,
  PhoneVerificationService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: PhoneVerificationScreen(service: service)),
    ),
  );
  await tester.pump();
}

/// Path-aware fake: send-otp and verify-otp answered independently.
PhoneVerificationService _routed({
  required http.Response Function() onSend,
  http.Response Function()? onVerify,
}) {
  return _serviceThat((request) {
    if (request.url.path.endsWith('/send-otp')) return onSend();
    if (request.url.path.endsWith('/verify-otp')) {
      return (onVerify ?? () => http.Response('{"success":true}', 200))();
    }
    return http.Response('{}', 404);
  });
}

void main() {
  setUpAll(stubSecureStorage);

  group('number stage', () {
    testWidgets('asks for a number and explains why, with a way out', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(onSend: () => http.Response('{"success":true}', 200)),
      );

      expect(find.text('Add your phone number'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
      // Leaving is allowed: no verified phone is not a dead end.
      expect(find.text('Do this later'), findsOneWidget);
      // Local numbers are understood; the prefix is shown, not demanded.
      expect(
        find.textContaining('We use it to secure your account'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a refused number keeps the number stage and shows the reason',
      (tester) async {
        await _pump(
          tester,
          _routed(
            onSend: () => http.Response(
              jsonEncode({
                'success': false,
                'message': 'Invalid phone number format.',
              }),
              400,
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '0244123456');
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();

        // Still on the number stage: no code box for a code never issued.
        expect(find.text('Add your phone number'), findsOneWidget);
        expect(find.text('Enter your code'), findsNothing);
        expect(find.textContaining('Invalid phone number'), findsOneWidget);
      },
    );

    testWidgets('rate limiting is reported as such, not as a bad number', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(
          onSend: () => http.Response(
            jsonEncode({'success': false, 'message': 'Too many requests.'}),
            429,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many'), findsOneWidget);
    });
  });

  group('code stage', () {
    testWidgets('a real send moves to the code stage without a test banner', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(
          onSend: () => http.Response(
            jsonEncode({'success': true, 'expiresAt': '2026-10-28T21:50:00Z'}),
            200,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.byKey(const Key('phone-test-delivery-banner')), findsNothing);
      // The number is shown in the form it will be stored in.
      expect(find.textContaining('+233 244123456'), findsOneWidget);
      // Resend is offered, but not instantly: the cooldown is real.
      expect(find.textContaining('Resend code in'), findsOneWidget);
    });

    testWidgets('test delivery is announced as NOT sent, with the code shown', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(
          onSend: () => http.Response(
            jsonEncode({'success': true, 'testOtp': '123456'}),
            200,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('phone-test-delivery-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('no SMS was sent'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Your code is 123456'), findsOneWidget);
    });

    testWidgets('a wrong code stays on the stage and does not claim success', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(
          onSend: () => http.Response(jsonEncode({'success': true}), 200),
          onVerify: () => http.Response(
            jsonEncode({
              'success': false,
              'message': 'Invalid or expired OTP.',
            }),
            400,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Verify number'));
      await tester.pumpAndSettle();

      expect(find.text('Number verified'), findsNothing);
      expect(find.textContaining('Invalid or expired'), findsOneWidget);
      expect(find.text('Verify number'), findsOneWidget);
    });

    testWidgets('verified is only shown after the server confirms', (
      tester,
    ) async {
      await _pump(
        tester,
        _routed(
          onSend: () => http.Response(jsonEncode({'success': true}), 200),
          onVerify: () => http.Response(
            jsonEncode({
              'success': true,
              'phoneNumber': '+233244123456',
              'message': 'Phone number verified successfully.',
            }),
            200,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify number'));
      await tester.pumpAndSettle();

      expect(find.text('Number verified'), findsOneWidget);
      expect(find.text('+233 244123456'), findsOneWidget);
      // The limit of the claim, stated on the screen that makes it.
      expect(find.textContaining('not who owns any wallet'), findsOneWidget);
    });

    testWidgets('a network failure does not call the code wrong', (
      tester,
    ) async {
      var verifyCalls = 0;
      final service = _serviceThat((request) {
        if (request.url.path.endsWith('/send-otp')) {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        verifyCalls++;
        throw const _Offline();
      });

      await _pump(tester, service);
      await tester.enterText(find.byType(TextField), '0244123456');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify number'));
      await tester.pumpAndSettle();

      expect(verifyCalls, 1);
      expect(find.text('Number verified'), findsNothing);
      // Says the code is still good rather than blaming the user's typing.
      expect(find.textContaining('still valid'), findsOneWidget);
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}
