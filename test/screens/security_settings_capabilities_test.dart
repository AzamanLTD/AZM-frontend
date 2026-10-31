// AZAMAN — SECURITY SETTINGS REPORTS THE SERVER'S ANSWER, OR NONE.
//
// The screen used to open with every factor defaulted to "not configured" and
// never ask, so a member who HAD a PIN was shown an unconfigured account. There
// are three truthful answers here, not two:
//
//   loading  — we have not been told yet;
//   known    — the server said what this account can use;
//   unknown  — the question failed, which is NOT "you have nothing set up".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock_flow.dart';

/// Answers capabilities from a table, and can be made to fail.
class _Gateway implements AppUnlockGateway {
  _Gateway(this.caps, {this.fail = false, this.delay = Duration.zero});

  final AppUnlockCapabilities caps;
  final bool fail;
  final Duration delay;
  int calls = 0;

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw Exception('capabilities unavailable');
    return caps;
  }

  @override
  Future<void> verifyPin(String pin) async {}
  @override
  Future<void> verifyTotp(String token) async {}
  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async =>
      throw UnimplementedError();
  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {}
}

Widget _host(AppUnlockGateway gateway) => ProviderScope(
  overrides: [
    appUnlockGatewayProvider.overrideWithValue(gateway),
    securityApiClientProvider.overrideWithValue(
      ApiClient(client: MockClient((r) async => http.Response('{}', 200))),
    ),
    authProvider.overrideWith((ref) => AuthProvider()),
  ],
  child: const MaterialApp(home: SecuritySettingsScreen()),
);

void _sizeForEverything(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('a configured account is reported configured', (tester) async {
    _sizeForEverything(tester);
    final gateway = _Gateway(
      const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: true,
        phoneVerified: true,
        smsUnlockAvailable: true,
      ),
    );
    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Configured'), findsNWidgets(2));
    expect(find.text('Available'), findsOneWidget, reason: 'SMS row');
    expect(
      find.text('Not configured'),
      findsNothing,
      reason: 'this account has both factors',
    );
  });

  testWidgets('an unconfigured account is reported unconfigured, not unknown', (
    tester,
  ) async {
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(_Gateway(AppUnlockCapabilities.none)));
    await tester.pumpAndSettle();

    expect(find.text('Not configured'), findsNWidgets(2));
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Configured'), findsNothing);
  });

  testWidgets('a failed read is unknown, never unconfigured', (tester) async {
    _sizeForEverything(tester);
    await tester.pumpWidget(
      _host(_Gateway(AppUnlockCapabilities.none, fail: true)),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not confirm'),
      findsOneWidget,
      reason: 'unknown is its own answer',
    );
    expect(find.text('Not configured'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the retry asks the server again', (tester) async {
    _sizeForEverything(tester);
    final gateway = _Gateway(AppUnlockCapabilities.none, fail: true);
    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();
    final first = gateway.calls;

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(gateway.calls, greaterThan(first));
  });

  testWidgets('SMS is never offered when the server cannot send it', (
    tester,
  ) async {
    _sizeForEverything(tester);
    await tester.pumpWidget(
      _host(
        _Gateway(
          const AppUnlockCapabilities(
            pinConfigured: true,
            authenticatorConfigured: false,
            phoneVerified: false,
            smsUnlockAvailable: false,
            smsUnavailableReason: 'PHONE_UNVERIFIED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available'), findsNothing);
    expect(
      find.text('Not available — verify your phone number first'),
      findsOneWidget,
      reason: 'the server\'s own reason, in words a member can act on',
    );
  });

  testWidgets('loading is stated, then replaced by the answer', (tester) async {
    _sizeForEverything(tester);
    final gateway = _Gateway(
      const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
      delay: const Duration(milliseconds: 120),
    );
    await tester.pumpWidget(_host(gateway));
    await tester.pump();

    expect(
      find.textContaining('Checking what this account can use'),
      findsOneWidget,
    );
    expect(
      find.text('Not configured'),
      findsNothing,
      reason: 'nothing may be reported as unconfigured before the answer',
    );

    await tester.pumpAndSettle();
    expect(find.text('Configured'), findsOneWidget);
  });
}
