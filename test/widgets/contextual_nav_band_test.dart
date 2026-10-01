// =============================================================================
// NEW-C — depth-aware contextual nav band regression suite (§2.3)
//
// Pins the band's behavior against the REAL router stack:
//
//   * invisible at depth 0 (root) while the shell is engaged,
//   * at depth ≥ 1 the bar shows the current route's TITLE + back chevron
//     and the "…" affordance,
//   * the back chevron pops ONE router page (depth 2 → depth 1 → root),
//   * "…" reopens the REAL PremiumBottomNav; tapping a tab pops back to the
//     shell and hands the tab to the shell bus,
//   * a sanctioned imperative route pushed ABOVE the top router page hides
//     the band; popping it restores the band,
//   * no shell engaged (cold deep link before the shell mounts, or a
//     shell-less state) keeps the app honest: no chrome,
//   * a deep-link-only stack (nothing to pop under it) backs out to the
//     canonical root instead of stalling.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/router/top_route_observer.dart';
import 'package:azaman/widgets/contextual_nav_band.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

GoRouter _testRouter({
  String initialLocation = '/',
  VoidCallback? onImperativePush,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: [topRouteObserver],
    routes: [
      GoRoute(
        path: '/',
        name: AzRouteNames.home,
        builder: (_, __) => const Scaffold(body: Center(child: Text('ROOT'))),
      ),
      GoRoute(
        path: '/transactions',
        name: AzRouteNames.transactions,
        builder: (ctx, __) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TXN PAGE'),
                // A SANCTIONED imperative route — the pattern the brief
                // permits for hand-rolled flows that must own the screen.
                TextButton(
                  onPressed: () {
                    onImperativePush?.call();
                    Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('IMPERATIVE PAGE'),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('POP'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('IMPERATIVE'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/deep/leaf',
        name: AzRouteNames.storyEditor,
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('LEAF PAGE'))),
      ),
    ],
  );
}

Widget _host(GoRouter router, RouteDepthTracker tracker) {
  return ProviderScope(
    overrides: [
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // Mirrors the app: the tracker host wraps the navigator AND the band
      // (band mounts above the navigator in the MaterialApp builder).
      builder: (context, child) => RouteDepthTrackerHost(
        tracker: tracker,
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ContextualNavBand(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The band's presence: 1 = on screen, 0 = slid/faded out.
double _bandOpacity(WidgetTester tester) {
  final band = find.byType(ContextualNavBand);
  return (tester.widget(
    find.descendant(of: band, matching: find.byType(AnimatedOpacity)),
  ) as AnimatedOpacity)
      .opacity;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  String initialLocation = '/',
  VoidCallback? onImperativePush,
}) async {
  final router = _testRouter(
    initialLocation: initialLocation,
    onImperativePush: onImperativePush,
  );
  final tracker = RouteDepthTracker(router);
  addTearDown(tracker.dispose);
  await tester.pumpWidget(_host(router, tracker));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.apply(const SensoryPreferences());
    appShellBus.debugReset();
    navScrollCompression.value = 0;
  });
  tearDown(appShellBus.debugReset);

  testWidgets('invisible at depth 0 while the shell is engaged',
      (tester) async {
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester);
    expect(_bandOpacity(tester), 0.0); // root: the shell's pill owns the edge
  });

  testWidgets(
      'at depth ≥ 1 the bar shows the route title + back chevron + "…"',
      (tester) async {
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester);

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();

    expect(_bandOpacity(tester), 1.0);
    expect(find.byKey(const Key('contextual-nav-back')), findsOneWidget);
    expect(find.byKey(const Key('contextual-nav-toggle')), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget); // the bar's title
  });

  testWidgets('the back chevron pops ONE router page per tap',
      (tester) async {
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester);

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();
    router.push('/deep/leaf');
    await tester.pumpAndSettle();
    expect(find.text('Story Editor'), findsOneWidget); // depth 2 title

    await tester.tap(find.byKey(const Key('contextual-nav-back')));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget); // one level up

    await tester.tap(find.byKey(const Key('contextual-nav-back')));
    await tester.pumpAndSettle();
    expect(_bandOpacity(tester), 0.0); // back at the root: no chrome
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
  });

  testWidgets(
      '"…" reopens the real pill; a tab tap returns to the shell and hands the tab over',
      (tester) async {
    final requested = <int>[];
    appShellBus.engage(onTabRequest: requested.add, initialTab: 0);
    await _pumpApp(tester);

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contextual-nav-toggle')));
    await tester.pumpAndSettle();

    // The REAL nav — the same widget type the shell hosts, key asserted
    // on it directly (the pill IS the nav, not a wrapper around one).
    final pill = find.byKey(const Key('contextual-nav-pill'));
    expect(pill, findsOneWidget);
    expect(tester.widget(pill), isA<PremiumBottomNav>());
    expect(find.text('Marketplace'), findsOneWidget);

    await tester.tap(find.text('Marketplace'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/'); // popped back to the shell base
    expect(requested, [2]); // the shell bus got the tab
    expect(_bandOpacity(tester), 0.0); // the band left with the depth
  });

  // Review-blocker regression: inside the REOPENED pill, a tap on the
  // already-selected tab must return to the shell (pop + bus hand-off),
  // not merely collapse the pill in place.
  testWidgets(
      'the reopened pill: tapping the ALREADY-SELECTED tab still returns to the shell',
      (tester) async {
    final requested = <int>[];
    appShellBus.engage(onTabRequest: requested.add, initialTab: 0);
    await _pumpApp(tester);

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contextual-nav-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contextual-nav-pill')), findsOneWidget);

    // Active tab is Home (0) — the same tab the pill marks selected.
    final pill = tester.widget<PremiumBottomNav>(
      find.byKey(const Key('contextual-nav-pill')),
    );
    expect(pill.selectedIndex, 0);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/'); // shell base
    expect(requested, [0]); // same tab handed to the shell bus
    expect(_bandOpacity(tester), 0.0); // the band left with the depth
    expect(find.byKey(const Key('contextual-nav-pill')), findsNothing); // pill gone with it
  });

  testWidgets(
      'a sanctioned imperative route above the top router page hides the band',
      (tester) async {
    var pushed = false;
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester, onImperativePush: () {
      pushed = true;
    });

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();
    expect(_bandOpacity(tester), 1.0);

    await tester.tap(find.text('IMPERATIVE'));
    await tester.pumpAndSettle();
    expect(pushed, isTrue);
    expect(_bandOpacity(tester), 0.0); // imperative owns the screen

    await tester.tap(find.text('POP'));
    await tester.pumpAndSettle();
    expect(_bandOpacity(tester), 1.0); // back on the router page: restored
  });

  testWidgets('no shell engaged: the band stays honest and hidden',
      (tester) async {
    await _pumpApp(tester);
    expect(appShellBus.engaged, isFalse);

    final router = _routerOf(tester);
    router.push('/transactions');
    await tester.pumpAndSettle();
    expect(find.text('TXN PAGE'), findsOneWidget);
    expect(_bandOpacity(tester), 0.0); // a shell-less state shows no chrome
  });

  testWidgets(
      'a deep-link-only stack (nothing to pop) backs out to the canonical root',
      (tester) async {
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester, initialLocation: '/transactions');
    await tester.pumpAndSettle();

    // Deep-link parity: the route's structural depth is 1 even though
    // nothing sits under it in this test stack.
    expect(_bandOpacity(tester), 1.0);
    expect(find.text('Transactions'), findsOneWidget);

    final router = _routerOf(tester);
    await tester.tap(find.byKey(const Key('contextual-nav-back')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/'); // went home instead of stalling
    expect(_bandOpacity(tester), 0.0);
  });
}

// ── helpers that read the LIVE app from the tester ─────────────────────────

/// The live router, resolved through the band (always under the tracker
/// host, whatever the current route stack is).
GoRouter _routerOf(WidgetTester tester) =>
    RouteDepthTrackerHost.of(tester.element(find.byType(ContextualNavBand)))
        .router;
