// =============================================================================
// PR-B — depth-aware contextual nav band regression suite
//
// Pins the band's behavior against the REAL router stack:
//
//   * invisible at depth 0 (root) while the shell is engaged,
//   * at depth ≥ 1 the bar shows the current route's TITLE + back
//     chevron ONLY (the "…" pill-reopen affordance was removed on
//     review — no dead hit target remains, and the band never renders
//     a tab pill),
//   * the back chevron runs the ONE back contract and pops ONE router
//     page (depth 2 → depth 1 → root),
//   * a sanctioned imperative route pushed ABOVE the top router page
//     hides the band; popping it restores the band,
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
          )
          as AnimatedOpacity)
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

  testWidgets('invisible at depth 0 while the shell is engaged', (
    tester,
  ) async {
    appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
    await _pumpApp(tester);
    expect(_bandOpacity(tester), 0.0); // root: the shell's pill owns the edge
  });

  testWidgets(
    'at depth ≥ 1 the bar shows the route title + back chevron, and NO "…"',
    (tester) async {
      appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
      await _pumpApp(tester);

      final router = _routerOf(tester);
      router.push('/transactions');
      await tester.pumpAndSettle();

      expect(_bandOpacity(tester), 1.0);
      expect(find.byKey(const Key('contextual-nav-back')), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget); // the bar's title
      // PR-B: the ellipsis is GONE — no dead hit target, no hidden affordance.
      expect(find.byKey(const Key('contextual-nav-toggle')), findsNothing);
      expect(find.text('…'), findsNothing);
      // The band never renders a tab pill any more: exactly the bar.
      expect(find.byType(PremiumBottomNav), findsNothing);
      // A11y honesty: the bar's semantics describe exactly the two
      // remaining controls — back + title text. No 'Show tabs' stop.
      expect(
        find.bySemanticsLabel(RegExp('Show tabs|Hide tabs')),
        findsNothing,
      );
    },
  );

  testWidgets('the back chevron pops ONE router page per tap', (tester) async {
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
    expect(_stackOf(tester), ['home', 'transactions']);

    await tester.tap(find.byKey(const Key('contextual-nav-back')));
    await tester.pumpAndSettle();
    expect(_bandOpacity(tester), 0.0); // back at the root: no chrome
    expect(_stackOf(tester), ['home']);
  });

  testWidgets(
    'rapid repeated back presses consume exactly one level per press',
    (tester) async {
      appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
      await _pumpApp(tester);

      final router = _routerOf(tester);
      router.push('/transactions');
      await tester.pumpAndSettle();
      router.push('/deep/leaf');
      await tester.pumpAndSettle();

      expect(_stackOf(tester), ['home', 'transactions', 'story-editor']);

      // Three rapid presses, asserted after EACH: every press consumes
      // exactly one level (leaf → transactions → root). If a single press
      // ever double-applied, the first assertion would already see 'home'.
      await tester.tap(find.byKey(const Key('contextual-nav-back')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_stackOf(tester), [
        'home',
        'transactions',
      ], reason: 'press one pops exactly the leaf page');
      expect(find.text('TXN PAGE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('contextual-nav-back')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_stackOf(tester), [
        'home',
      ], reason: 'press two pops exactly the transactions page');

      // At the root base there is nothing more to pop; the next press is
      // the honest root fallback (stack stays ['home']), never a phantom
      // pop or a crash.
      await tester.tap(find.byKey(const Key('contextual-nav-back')));
      await tester.pumpAndSettle();
      expect(_stackOf(tester), ['home']);
    },
  );

  testWidgets(
    'a sanctioned imperative route above the top router page hides the band',
    (tester) async {
      var pushed = false;
      appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
      await _pumpApp(
        tester,
        onImperativePush: () {
          pushed = true;
        },
      );

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
    },
  );

  testWidgets('no shell engaged: the band stays honest and hidden', (
    tester,
  ) async {
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

      await tester.tap(find.byKey(const Key('contextual-nav-back')));
      await tester.pumpAndSettle();
      expect(_stackOf(tester), ['home']); // went home instead of stalling
      expect(_bandOpacity(tester), 0.0);
    },
  );
}

/// The live navigator's page stack, by route name — the truthful
/// route-stack read (GoRouter's currentConfiguration.uri can lag the
/// navigator's own page list).
List<String> _stackOf(WidgetTester tester) {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  return nav.widget.pages.map((pg) => pg.name ?? '?').toList();
}

// ── helpers that read the LIVE app from the tester ─────────────────────────

/// The live router, resolved through the band (always under the tracker
/// host, whatever the current route stack is).
GoRouter _routerOf(WidgetTester tester) => RouteDepthTrackerHost.of(
  tester.element(find.byType(ContextualNavBand)),
).router;
