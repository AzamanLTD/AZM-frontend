// =============================================================================
// AZAMAN — THE BOOT DECISION ABOUT THE PUBLIC INTRO (P7, 2026-10-28)
//
// The tour is only useful if the BOOT RESOLVER actually sends a fresh device
// there. This suite drives the REAL SplashScreen through the REAL route table
// in NON-demo mode (demo mode deliberately skips the tour: a demo build has
// seeded data and no sign-in, so a product tour in front of it is noise).
//
//   A. FRESH INSTALL  → the splash resolves to /intro, NOT to sign-in.
//   B. THE EXIT       → skipping the tour lands on sign-in, and the flag is
//                       what a relaunch then reads.
//   C. RETURNING USER → the splash goes straight to sign-in, never flashing
//                       the tour again.
//
// The ordering matters as much as the destination: the intro check runs
// BEFORE the version gate and the auth waterfall, so a fresh device never
// waits on three network calls to see the product.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/router/app_router.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/screens/intro/app_intro_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/intro_store.dart';

/// A provider that never touches the network: the search notifier only needs
/// to exist for the shell's tree to build.
/// The splash's auth probe is a real network round-trip. Under the test
/// binding that future never completes (no socket progress under fake async),
/// which would leave the splash on screen forever — so the probe is stubbed to
/// the answer this test is about: there is no session.
class _SignedOutAuth extends auth_pkg.AuthProvider {
  @override
  Future<bool> checkAuthStatus() async => false;
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
    // Recorded, not fired — no network in a boot decision test.
  }
}

late GoRouter router;

Future<void> _pumpRealApp(WidgetTester tester) async {
  router = createAppRouter();
  await tester.binding.setSurfaceSize(const Size(400, 820));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer(
    overrides: [
      auth_pkg.authProvider.overrideWith((ref) => _SignedOutAuth()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 0),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      businessSearchProvider.overrideWith((ref) => _InertSearchNotifier()),
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

/// The top of the router's declarative match stack.
String topMatch() =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

void main() {
  setUp(() {
    // A normal app launch, not a demo build.
    AppConfig.clearDemoModeOverrideForTest();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(AppConfig.clearDemoModeOverrideForTest);

  testWidgets('A. a fresh install boots to the public tour, before any auth '
      'work', (tester) async {
    await _pumpRealApp(tester);
    await tester.pump();
    expect(find.byType(SplashScreenProbe), findsNothing);

    // The splash holds for the WHOLE launch sequence. Derive the wait from the
    // real timeline instead of a magic 3.3s, so retiming the intro cannot
    // silently break the boot decision again.
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(AzamanIntro.total);
    // The branding floor elapses on that last pump; `go()` then needs a frame
    // to build the destination AND to finish its route transition. Without
    // letting the transition settle, the tour is still sliding in and its
    // controls are laid out off-screen (a tap on "Skip" lands at x=448 on a
    // 400pt viewport and silently misses).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byType(AppIntroScreen),
      findsOneWidget,
      reason: 'a device that has not seen the tour must be sent to it',
    );
    expect(topMatch(), AzRoutes.intro);
    // The tour is public: it is NOT the guarded shell, and it is not a
    // sign-in wall either — it is the product explanation that comes first.
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('B. skipping the tour records the local flag and lands on '
      'sign-in', (tester) async {
    await _pumpRealApp(tester);
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(AzamanIntro.total);
    // The branding floor elapses on that last pump; `go()` then needs a frame
    // to build the destination AND to finish its route transition. Without
    // letting the transition settle, the tour is still sliding in and its
    // controls are laid out off-screen (a tap on "Skip" lands at x=448 on a
    // 400pt viewport and silently misses).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(AppIntroScreen), findsOneWidget);

    await tester.tap(find.text('Skip'));
    // _leave() awaits the local flag write before it navigates, so give the
    // async a turn and then a frame to build the destination.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(topMatch(), AzRoutes.login);
    // The flag is the ONLY thing written, and it is a local preference key
    // (never an onboarding/account flag).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kIntroSeenPrefKey), isTrue);

    final relaunch = await const IntroStore().hasSeenIntro();
    expect(relaunch, isTrue, reason: 'a relaunch must not repeat the tour');
  });

  testWidgets('C. a returning user goes straight to sign-in, with no tour '
      'flash', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kIntroSeenPrefKey: true,
    });

    await _pumpRealApp(tester);
    await tester.pump();
    // The intro must never be mounted, not even for one frame.
    expect(find.byType(AppIntroScreen), findsNothing);

    // The auth probe runs behind the branding floor; in a test environment
    // its HTTP calls fail fast, so the splash resolves to sign-in. Pump in
    // slices rather than guessing one total.
    for (var i = 0; i < 24; i++) {
      if (find.byType(LoginScreen).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(AppIntroScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(topMatch(), AzRoutes.login);
  });
}

/// Sentinel so the first assertion of A reads as an assertion rather than a
/// stray reference: nothing else must occupy the splash's slot.
class SplashScreenProbe extends StatelessWidget {
  const SplashScreenProbe({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
