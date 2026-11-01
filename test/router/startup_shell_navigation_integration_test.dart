// =============================================================================
// STARTUP / SHELL / NAVIGATION — REAL INTEGRATION CONTRACT
//
// The defect this suite pins (reported on multiple physical devices, Flutter
// Web, demo mode AND real login): the app starts fine, the user opens
// Convert / Send / Settings / a Marketplace screen, and roughly two seconds
// later the app returns to Home without the user asking. Repeated attempts
// sometimes stick; other times controls stop responding; occasionally a
// screen reports that part of Azaman did not load.
//
// THE HARNESS IS THE REAL THING: the app's own global `appRouter` (GoRouter
// with the real route table, redirect and observers), the REAL SplashScreen
// waterfall (real branding floor, real auth check), and the REAL MainWrapper
// shell — pumped exactly the way `AzamanApp` mounts them. No fabricated
// GoRouter: the splash-to-shell handoff under test is the production one.
//
// Contracts:
//   1.  demo boot: splash → shell, ONCE.
//   2.  Home → Convert → wait WELL past the 2s window → STILL on Convert,
//       and a control on it stays interactive.
//   3.  Home → Send → wait → STILL on Send.
//   4.  Home → Settings → wait → STILL on Settings.
//   5.  Home → a Marketplace destination → wait → STILL there.
//   6.  BACK from a destination returns DIRECTLY to the shell (no splash
//       re-entry, no 2s branding floor, same shell instance).
//   7.  Repeated navigation keeps working (the "sometimes works" case
//       must become "always works").
//   8.  Auth semantics stay distinct: a VALID session survives a transient
//       backend failure (no silent logout, no bounce); a GENUINE auth
//       rejection (AuthGuard false) redirects protected routes to the
//       boot flow instead.
//   9.  Exactly ONE MainWrapper instance ever exists.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data' show ByteData, Uint8List;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/main.dart' show MainWrapper;
import 'package:go_router/go_router.dart';
import 'package:azaman/router/app_router.dart' show createAppRouter;
import 'package:azaman/router/auth_guard.dart';
import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/splash_screen.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/theme_picker_screen.dart';
import 'package:azaman/screens/wallet/convert_screen.dart';
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/services/business_service.dart';

import '../support/money_access_test_support.dart';

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
  _fontsLoaded = true;
}

class _InertSearchNotifier extends BusinessSearchNotifier {
  _InertSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    // Recorded, not fired — no network in this guard.
  }
}

/// The REAL app mount: the app's own GoRouter with the real route table.
/// The test-local router: a FRESH instance per test, built from the
/// app's own route table + redirect via [createAppRouter] (the same
/// wiring the global appRouter uses) — the real splash-to-shell
/// handoff, with no singleton state leaking between tests.
late GoRouter router;

Future<void> _pumpRealApp(WidgetTester tester) async {
  AuthGuard.isAuthenticated = false;
  AppConfig.enableDemoMode();
  router = createAppRouter();
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'has_seen_drawer_peek_hint': true,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(const Size(400, 800));

  final container = ProviderContainer(
    overrides: [
      auth_pkg.authProvider.overrideWith((ref) => auth_pkg.AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      businessSearchProvider.overrideWith((ref) => _InertSearchNotifier()),
      // These journeys push money destinations (Send, Convert) and assert the
      // member STAYS on them; the money gate has its own suites, so start
      // these from an unlocked session rather than proxying the gate's state.
      unlockedMoneyAccess(),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

/// The top of the router's declarative match stack (GoRouter 14 reports
/// a pushed location through the matches, not through
/// currentConfiguration.uri).
String topMatch(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

/// Boot the REAL splash waterfall in demo mode and land on the shell.
Future<void> _bootDemoShell(WidgetTester tester) async {
  AppConfig.enableDemoMode();
  await _pumpRealApp(tester);
  // First frame: the real splash.
  await tester.pump();
  expect(find.byType(SplashScreen), findsOneWidget);
  // The real branding floor is 2 seconds; the demo waterfall then replaces
  // the route. Generous pumps through the floor + the transition.
  // The splash holds for the WHOLE launch sequence now, so the wait is derived
  // from it. A hardcoded ~3.1s here silently stopped reaching the shell the
  // moment the intro was retimed.
  await tester.pump(const Duration(milliseconds: 2300));
  await tester.pump(AzamanIntro.total);
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byType(MainWrapper), findsOneWidget);
}

Future<void> _openAndAssertStays(
  WidgetTester tester, {
  required String location,
  required Finder screen,
}) async {
  // The REAL navigation API the app's controls use (context.push on the
  // root router).
  router.push(location);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
  expect(screen, findsOneWidget, reason: 'pushed $location');
  // Wait WELL past the 2-second branding floor — the reported defect window.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 400));
  expect(screen, findsOneWidget, reason: 'still on $location after 3s+');
  // The defect's engine was a re-instantiated SplashScreen hiding beneath
  // the destination whose 2s exit disposed the screen the user was on.
  expect(
    find.byType(SplashScreen),
    findsNothing,
    reason:
        'a splash was re-instantiated under the destination — the '
        'bounce engine is back',
  );
  // Back through the router lands DIRECTLY on the canonical shell page:
  // no splash pass-through, no duplicate wrapper, location '/home'.
  router.pop();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(seconds: 2));
  expect(
    find.byType(SplashScreen),
    findsNothing,
    reason: 'back passed through the splash — the old broken exit',
  );
  expect(
    find.byType(MainWrapper),
    findsOneWidget,
    reason: 'back did not land on the shell',
  );
  expect(
    topMatch(router),
    '/home',
    reason: 'the declarative stack did not unwind to /home',
  );
}

void main() {
  testWidgets('demo boot: the shell is reached exactly once', (tester) async {
    await _bootDemoShell(tester);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(MainWrapper), findsOneWidget);
    // No second wrapper ever mounts while we idle past the floor.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MainWrapper), findsOneWidget);
  });

  testWidgets('Home → Convert → wait → STILL on Convert (no yank to Home)', (
    tester,
  ) async {
    await _bootDemoShell(tester);
    await _openAndAssertStays(
      tester,
      location: '/convert',
      screen: find.byType(ConvertScreen),
    );
  });

  testWidgets('Home → Send → wait → STILL on Send', (tester) async {
    await _bootDemoShell(tester);
    await _openAndAssertStays(
      tester,
      location: '/send',
      screen: find.byType(SendMoneyScreen),
    );
  });

  testWidgets('Home → Settings → wait → STILL on Settings', (tester) async {
    await _bootDemoShell(tester);
    await _openAndAssertStays(
      tester,
      location: '/settings',
      screen: find.byType(SettingsScreen),
    );
  });

  testWidgets('Home → a Marketplace destination → wait → STILL there', (
    tester,
  ) async {
    await _bootDemoShell(tester);
    await _openAndAssertStays(
      tester,
      location: '/biz/saved',
      screen: find.byType(SavedBusinessesScreen),
    );
  });

  testWidgets(
    'the Convert journey stays interactive (a real control responds)',
    (tester) async {
      await _bootDemoShell(tester);
      router.push('/convert');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ConvertScreen), findsOneWidget);

      // A real control that always exists: the X close responds to a
      // tap by popping through the router (the same route the shell
      // pushed). Interactive, not bounced.
      final close = find.byKey(const Key('convert_close'));
      expect(close, findsOneWidget);
      await tester.tap(close, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byType(ConvertScreen),
        findsNothing,
        reason: 'the real close control dismissed the surface',
      );
      expect(find.byType(MainWrapper), findsOneWidget);
    },
  );

  testWidgets(
    'Settings: a real control (the Theme picker) responds, surface survives',
    (tester) async {
      await _bootDemoShell(tester);
      router.push('/settings');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SettingsScreen), findsOneWidget);

      // The theme row is a REAL control — it pushes the theme picker.
      // It can sit below the fold, so scroll it into view first.
      await tester.scrollUntilVisible(
        find.text('Theme'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Theme').last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byType(ThemePickerScreen),
        findsOneWidget,
        reason: 'the real Theme control opened the theme picker',
      );

      // System back dismisses the picker; the settings surface below must
      // still be there, surviving past the 2s defect window.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason: 'the settings surface survives past the 2s window',
      );
      // No splash ever re-entered the stack during the interaction.
      expect(
        find.byType(SplashScreen),
        findsNothing,
        reason: 'the settings surface survived a real interaction',
      );
    },
  );

  testWidgets('BACK from a destination returns DIRECTLY to the same shell — '
      'no splash, no 2s floor, no recreated wrapper', (tester) async {
    await _bootDemoShell(tester);
    router.push('/convert');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ConvertScreen), findsOneWidget);

    // Back through the router (what the platform/chevron back does).
    // Settle: the exiting page stays mounted until its reverse
    // transition completes.
    router.pop();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(ConvertScreen), findsNothing);
    expect(
      find.byType(SplashScreen),
      findsNothing,
      reason: 'the old architecture re-entered the splash on back',
    );
    expect(
      find.byType(MainWrapper),
      findsOneWidget,
      reason: 'back must land on the shell, exactly once',
    );
    expect(
      topMatch(router),
      '/home',
      reason: 'back unwound the declarative stack to /home',
    );

    // And the shell keeps working: idle past the 2s window.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MainWrapper), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('repeated navigation keeps working (the "sometimes works" case '
      'becomes always)', (tester) async {
    await _bootDemoShell(tester);

    // First journey.
    router.push('/convert');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ConvertScreen), findsOneWidget);
    router.pop();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));

    // Second journey immediately after.
    router.push('/send');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SendMoneyScreen), findsOneWidget);

    // One shell — never two — and the stack is back at the shell.
    router.pop();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MainWrapper), findsOneWidget);
    expect(find.byType(SendMoneyScreen), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('auth semantics stay distinct: a transient backend failure never '
      'silently logs out; a GENUINE rejection redirects', (tester) async {
    // AUTHENTICATED MODE: guard set, straight to the guarded shell.
    AuthGuard.isAuthenticated = true;
    await _pumpRealApp(tester);
    router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MainWrapper), findsOneWidget);

    // A transient failure (this harness's blocked network IS one —
    // every backend call 400s, like a blip): the guard must survive
    // and navigation must keep working.
    router.push('/settings');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      AuthGuard.isAuthenticated,
      isTrue,
      reason: 'a transient failure must not silently log out',
    );

    // GENUINE rejection (401/logout semantics — the guard flips): the
    // protected route must NOT open; the boot resolver takes over.
    // Demo mode deliberately bypasses auth gating — clear the override
    // so the router's real redirect contract is under test.
    AppConfig.clearDemoModeOverrideForTest();
    AuthGuard.isAuthenticated = false;
    router.push('/settings');
    // The redirect replaces the stack with the splash resolver; the old
    // settings page exits over the reverse transition — settle fully.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.byType(SettingsScreen),
      findsNothing,
      reason: 'with the guard down, a protected route must not open',
    );
    expect(
      find.byType(SplashScreen),
      findsOneWidget,
      reason: 'the boot resolver owns the user after a real rejection',
    );
  });
}
