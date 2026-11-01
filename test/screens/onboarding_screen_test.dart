// AUTHENTICATED ACCOUNT SETUP — CONTRACT TESTS.
//
// This screen replaced a four-page feature showcase that replayed the public
// tour after registration. These tests pin what the replacement must never do
// again: claim things the product cannot support, advance on a failed
// completion call, or collect a deposit / KYC / permission at first login.
//
// It also pins what must NOT be lost: the POST /users/onboarding/complete
// contract, the null-use-case path the old Skip provided, and the hand-off to
// primary-phone verification.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/onboarding_screen.dart';
import 'package:azaman/services/api_client.dart';

/// Records what the screen actually sent, so the completion contract is
/// asserted from the wire rather than from the widget tree.
class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  Map<String, dynamic> get body =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
}

Future<void> _pump(
  WidgetTester tester, {
  required _Recorder recorder,
  int status = 200,
  String body = '{"success":true}',
}) async {
  final client = MockClient((request) async {
    recorder.requests.add(request);
    return http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
    );
  });

  final router = GoRouter(
    initialLocation: AzRoutes.onboarding,
    routes: [
      GoRoute(
        path: AzRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AzRoutes.verifyPhone,
        builder: (context, state) =>
            const Scaffold(body: Text('PHONE VERIFICATION DESTINATION')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWith((ref) => ApiClient(client: client)),
        themeProvider.overrideWith((ref) => ThemeProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // ApiClient reads its auth token from secure storage. Without this the
    // read hits an unmocked platform channel, the request future never
    // completes, and the completion button spins forever.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('1. it is one setup step, not a second tour', (tester) async {
    await _pump(tester, recorder: _Recorder());

    expect(find.text('Set up your account'), findsOneWidget);
    expect(find.text('P2P trading'), findsOneWidget);
    expect(find.text('Susu savings'), findsOneWidget);

    // The showcase pages are gone, and with them the claims that cannot be
    // supported from this build.
    for (final retired in <String>[
      "Ghana's Fastest P2P Platform",
      'Zero gas fees',
      'No fraud, no chargebacks — just safe, instant settlement.',
      'Every Trade is Escrow-Protected',
    ]) {
      expect(
        find.textContaining(retired, findRichText: true),
        findsNothing,
        reason: 'unsupported claim survived: $retired',
      );
    }

    // And the artwork those pages used is not being smuggled back in.
    final images = tester.widgetList<Image>(find.byType(Image));
    for (final image in images) {
      if (image.image is AssetImage) {
        final asset = (image.image as AssetImage).assetName;
        expect(asset.contains('images/1.webp'), isFalse);
        expect(asset.contains('images/2.webp'), isFalse);
        expect(asset.contains('images/3.webp'), isFalse);
      }
    }
  });

  testWidgets('2. no deposit, no KYC, no permission prompt at first login', (
    tester,
  ) async {
    await _pump(tester, recorder: _Recorder());

    for (final absent in <String>['deposit', 'KYC', 'Verify your identity']) {
      expect(find.textContaining(absent, findRichText: true), findsNothing);
    }
    // The only forward promise is the real next step.
    expect(find.textContaining('confirm your phone number'), findsOneWidget);
  });

  testWidgets('3. Continue stays disabled until a use case is chosen', (
    tester,
  ) async {
    await _pump(tester, recorder: _Recorder());

    ElevatedButton button() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );

    expect(button().onPressed, isNull);

    await tester.tap(find.text('P2P trading'));
    await tester.pumpAndSettle();

    expect(button().onPressed, isNotNull);
  });

  testWidgets('4. it posts the chosen use case and hands off to phone', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder: recorder);

    await tester.tap(find.text('Susu savings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(recorder.requests, hasLength(1));
    expect(recorder.requests.single.method, 'POST');
    expect(
      recorder.requests.single.url.path,
      endsWith('/users/onboarding/complete'),
    );
    expect(recorder.body['primaryUseCase'], 'Susu savings');
    expect(find.text('PHONE VERIFICATION DESTINATION'), findsOneWidget);
  });

  testWidgets('5. a failed completion never looks like a finished setup', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(
      tester,
      recorder: recorder,
      status: 500,
      body: '{"error":"boom"}',
    );

    await tester.tap(find.text('Remittances'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(recorder.requests, hasLength(1));
    expect(find.text('PHONE VERIFICATION DESTINATION'), findsNothing);
    expect(find.text('Set up your account'), findsOneWidget);
    expect(
      find.text('Could not save your setup. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    // The button is usable again, so the person can actually retry.
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Continue'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('6. "Decide later" keeps the old Skip contract: null use case', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pump(tester, recorder: recorder);

    await tester.tap(find.text('Decide later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(recorder.requests, hasLength(1));
    expect(
      recorder.requests.single.url.path,
      endsWith('/users/onboarding/complete'),
    );
    expect(recorder.body.containsKey('primaryUseCase'), isTrue);
    expect(recorder.body['primaryUseCase'], isNull);
    expect(find.text('PHONE VERIFICATION DESTINATION'), findsOneWidget);
  });

  testWidgets('7. a dead connection is not reported as success', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AzRoutes.onboarding,
      routes: [
        GoRoute(
          path: AzRoutes.onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: AzRoutes.verifyPhone,
          builder: (context, state) =>
              const Scaffold(body: Text('PHONE VERIFICATION DESTINATION')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              client: MockClient((_) async => throw const SocketishFailure()),
            ),
          ),
          themeProvider.overrideWith((ref) => ThemeProvider()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PHONE VERIFICATION DESTINATION'), findsNothing);
    expect(
      find.text('Could not save your setup. Check your connection.'),
      findsOneWidget,
    );
  });
}

/// A transport failure that is not an [http.Response]: the client never got an
/// answer at all.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => 'connection refused';
}
