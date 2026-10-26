// =============================================================================
// AZAMAN — WORKSTREAM C: WITHDRAW SURFACE CAPTURE EVIDENCE GENERATOR
//
// Generates the capture set for the withdraw surface redesign:
//   docs/captures/withdraw/withdraw_<state>_<theme>_<width>dp.png
//
//   • state: empty (fresh MoMo page) | prepared (saved account picked,
//     amount composed, reference visible, fee preview, live commit)
//   • theme: light | dark (the app's two identities)
//   • width: 320 | 360 | 390 dp
//
// THIS FILE LIVES IN tool/captures — NOT under test/ — ON PURPOSE:
//   1. It is an evidence generator, not a regression suite. `flutter test`
//      (what CI runs for the quality battery) only discovers test/ and
//      the twelve full-app pumps + PNG rasterisations here cost many
//      minutes, which pushed the CI "Test with coverage" step past its
//      15-minute job timeout (first run of PR #193: cancelled at 15:18).
//   2. Some local harnesses deadlock on the SECOND image capture within
//      one process; the matrix is generated one combo per invocation.
//
// Run (one combo at a time; a plain `flutter test` bare would pick up
// nothing from this directory):
//   flutter test tool/captures/withdraw_captures_test.dart \
//     --plain-name "capture 320 light empty"
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomands.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
}

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

Future<void> _mockSecureStorage() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('base-marker'),
                onPressed: () => GoRouter.of(c).push(AzRoutes.withdraw()),
                child: const Text('base'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/withdraw',
          name: AzRouteNames.withdraw,
          pageBuilder: (c, s) => risePage(
            key: s.pageKey,
            restorationId: s.name,
            child: const WithdrawalScreen(),
          ),
        ),
      ],
    );

Future<void> _capture(
  WidgetTester tester, {
  required double logicalWidth,
  required int themeIdx,
  required String themeName,
  required String stateName,
  bool prepared = false,
}) async {
  const logicalHeight = 800.0;
  tester.view.physicalSize =
      Size(logicalWidth * 2, logicalHeight * 2); // DPR 2 → crisp evidence
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  // Runs under the flutter_test binding (it IS a test file — it just
  // lives in tool/ so CI's battery never picks it up), so the mock
  // preferences API is exactly the right tool here.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(
      {'azaman_theme': themeIdx, 'biometric_lock_enabled': false});
  await _mockSecureStorage();

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FixedAuth(_user())),
          themeProvider.overrideWith((ref) => ThemeProvider()),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('base-marker')));
  await tester.pumpAndSettle();

  if (prepared) {
    // Saved account picked + amount composed: the reference affordance,
    // the fee preview and the live slide-to-confirm all visible. The
    // payout account is picked through the Add-Cash-style selector
    // sheet (the owner-corrected grammar — one row, never stacked
    // wallets).
    await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
    await tester.pumpAndSettle();
    for (final key in const ['1', '2', '.', '5']) {
      await tester.tap(
        find
            .descendant(of: find.byType(AmountKeypad), matching: find.text(key))
            .first,
        warnIfMissed: false,
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  final boundary = boundaryKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('docs/captures/withdraw');
  dir.createSync(recursive: true);
  final file = File(
      '${dir.path}/withdraw_${stateName}_$themeName-${logicalWidth.toInt()}dp.png');
  file.writeAsBytesSync(data!.buffer.asUint8List());
  expect(file.existsSync(), isTrue, reason: 'capture written: ${file.path}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.enableDemoMode();

  // Twelve separately-named captures. The test harness in this sandbox
  // deadlocks on the SECOND image capture within one process, so the
  // capture set is generated one invocation at a time:
  //   flutter test test/widgets/withdraw_captures_test.dart \
  //     --plain-name "capture 320 light empty"
  // Each test exercises exactly one combo.
  const combos = [
    (320.0, '320', 0, 'light', 'empty', false),
    (320.0, '320', 1, 'dark', 'empty', false),
    (320.0, '320', 0, 'light', 'prepared', true),
    (320.0, '320', 1, 'dark', 'prepared', true),
    (360.0, '360', 0, 'light', 'empty', false),
    (360.0, '360', 1, 'dark', 'empty', false),
    (360.0, '360', 0, 'light', 'prepared', true),
    (360.0, '360', 1, 'dark', 'prepared', true),
    (390.0, '390', 0, 'light', 'empty', false),
    (390.0, '390', 1, 'dark', 'empty', false),
    (390.0, '390', 0, 'light', 'prepared', true),
    (390.0, '390', 1, 'dark', 'prepared', true),
  ];
  for (final c in combos) {
    final name = 'capture ${c.$2} ${c.$4} ${c.$5}';
    testWidgets(name, (tester) async {
      await _capture(
        tester,
        logicalWidth: c.$1,
        themeIdx: c.$3,
        themeName: c.$4,
        stateName: c.$5,
        prepared: c.$6,
      );
    });
  }
}
