// =============================================================================
// COMPACT-NAV — the wrap-to-content tab pill (PR: compact bottom navigation).
//
// Pins the four contracts of the compact pill:
//   1. LABEL STATE — the SELECTED segment shows its label (Home / Chat /
//      Market) at full rendered opacity; inactive segments are compact icon
//      controls (their labels are in-tree at zero width and never render).
//   2. CONTENT-BASED WIDTH — the pill wraps to its content instead of
//      stretching across the band; the + launcher sits beside it.
//   3. NARROW SCREENS — the label decision is responsive (measured, not a
//      fixed phone width): on a surface too narrow for the labeled pill the
//      selected tab degrades to its icon identity instead of clipping or
//      overflowing; every segment keeps a 44dp touch target.
//   4. REDUCED MOTION — the label state lands instantly (no width tween),
//      and the pill keeps full height and opacity under compression.
//   5. SWITCH TABS FROM A PUSHED PAGE — the contextual bar's EXPLICIT
//      "Tabs" control (never an ellipsis) reopens the real pill, pops the
//      router stack, and hands the tab to the shell.
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
import 'package:azaman/router/top_route_observer.dart';
import 'package:azaman/widgets/contextual_nav_band.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

Widget _harness({required int selectedIndex, Size size = const Size(430, 200), Widget? trailing}) {
  return ProviderScope(
    overrides: [
      // Inert badges: geometry is under test, not unread state.
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          bottomNavigationBar: PremiumBottomNav(
            selectedIndex: selectedIndex,
            onItemSelected: (_) {},
            trailing: trailing ??
                const SizedBox(key: ValueKey('plus-stand-in'), width: 54, height: 54),
          ),
        ),
      ),
    ),
  );
}

/// The pill's rendered width: the AnimatedContainer inside the nav.
double _pillWidth(WidgetTester tester) => tester.getSize(
      find
          .descendant(
            of: find.byType(PremiumBottomNav),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    ).width;

/// A nav label's rendered opacity (zero-width labels exist in-tree).
double _labelOpacity(WidgetTester tester, String label) => tester.widget<Opacity>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Opacity))
          .first,
    ).opacity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    navScrollCompression.value = 0;
  });

  group('1. label state', () {
    testWidgets('the selected tab shows its label; inactive tabs are '
        'compact icon controls', (tester) async {
      for (final entry in [0, 1, 2]) {
        await tester.pumpWidget(_harness(selectedIndex: entry));
        await tester.pumpAndSettle();

        final labels = ['Home', 'Chat', 'Market'];
        for (var i = 0; i < 3; i++) {
          final opacity = _labelOpacity(tester, labels[i]);
          if (i == entry) {
            expect(opacity, 1.0, reason: '${labels[i]} is selected: visible');
          } else {
            expect(opacity, 0.0,
                reason: '${labels[i]} is inactive: NOT rendered');
          }
        }
      }
    });

    testWidgets('the Market label is the short word (the tab identity), '
        'on screen and on Semantics', (tester) async {
      await tester.pumpWidget(_harness(selectedIndex: 2));
      await tester.pumpAndSettle();
      expect(find.text('Market'), findsOneWidget);
      expect(_labelOpacity(tester, 'Market'), 1.0);
      expect(find.bySemanticsLabel('Market'), findsOneWidget);
      // The long word is not what the pill shows.
      expect(find.text('Marketplace'), findsNothing);
    });
  });

  group('2. content-based width', () {
    testWidgets('the pill wraps to its content, not the band', (tester) async {
      await tester.pumpWidget(_harness(selectedIndex: 0));
      await tester.pumpAndSettle();

      final pill = _pillWidth(tester);
      // 3 segments + padding + label must fit FAR below the 430 surface:
      // a stretched pill would be ~400 wide; content is ~200-260.
      expect(pill, lessThan(300), reason: 'the pill must not stretch');
      expect(pill, greaterThan(120), reason: 'three 44dp segments minimum');

      // The + launcher sits BESIDE the pill (both visible, side by side).
      final plusRect = tester.getRect(find.byKey(const ValueKey('plus-stand-in')));
      final pillRect = tester.getRect(
        find.descendant(
            of: find.byType(PremiumBottomNav),
            matching: find.byType(AnimatedContainer)).first,
      );
      expect(plusRect.left, greaterThan(pillRect.right),
          reason: 'the + sits to the pill’s right');
    });

    testWidgets('labeled and icon-only pills differ (responsive content)',
        (tester) async {
      await tester.pumpWidget(_harness(selectedIndex: 0));
      await tester.pumpAndSettle();
      final labeled = _pillWidth(tester);

      // A narrow surface WITHOUT the trailing + (a bare pill mount) forces
      // the icon-only fallback for the SAME selected state. 240 logical
      // px: room for the three 44dp anchors, NOT for the label.
      tester.view.physicalSize = const Size(240, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(
        selectedIndex: 0,
        size: const Size(240, 200),
        trailing: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();
      final iconOnly = _pillWidth(tester);
      expect(iconOnly, lessThan(labeled),
          reason: 'a labeled pill is wider than an icon-only one');
      expect(_labelOpacity(tester, 'Home'), 0.0,
          reason: 'no room for the label: icon-only fallback');
    });
  });

  group('3. narrow screens', () {
    testWidgets('a narrow 320px phone keeps the +, the 44dp targets and '
        'no overflow (label falls back only if it cannot fit)', (tester) async {
      tester.view.physicalSize = const Size(320, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(
        selectedIndex: 0,
        size: const Size(320, 200),
      ));
      await tester.pumpAndSettle();

      // No overflow exceptions, no clipped geometry.
      expect(tester.takeException(), isNull);
      // The label decision is MEASURED against the real remaining width:
      // it shows only when the labeled pill genuinely fits (the test font
      // runs wide, so at 320px with the launcher it may fall back).
      final labelFits =
          tester.getSize(find.text('Home')).width + 151 <= 190;
      expect(_labelOpacity(tester, 'Home'), labelFits ? 1.0 : 0.0);
      // The + launcher is still beside the pill.
      expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
      // Every segment keeps its 44dp touch target.
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(find.byKey(ValueKey('nav-item-$i')));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
      final pill = _pillWidth(tester);
      expect(pill, lessThan(320), reason: 'the pill never touches both edges');
    });

    testWidgets('a sub-label surface (bare pill) degrades to the '
        'icon-only identity instead of clipping', (tester) async {
      // 240 logical px: the three 44dp anchors fit; the label cannot.
      tester.view.physicalSize = const Size(240, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(
        selectedIndex: 0,
        size: const Size(240, 200),
        trailing: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_labelOpacity(tester, 'Home'), 0.0,
          reason: 'no room for the label: the compact icon identity wins');
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(find.byKey(ValueKey('nav-item-$i')));
        expect(rect.width, greaterThanOrEqualTo(44));
      }
      expect(_pillWidth(tester), lessThanOrEqualTo(240));
    });

    testWidgets('a roomy surface shows the label (the decision is '
        'measured, not a fixed breakpoint)', (tester) async {
      await tester.pumpWidget(_harness(selectedIndex: 1));
      await tester.pumpAndSettle();
      expect(_labelOpacity(tester, 'Chat'), 1.0);
    });
  });

  group('4. reduced motion', () {
    testWidgets('the label lands instantly — no width tween, no pending '
        'animation', (tester) async {
      // The app's explicit reduce-motion override, the same seam the
      // sensory settings write.
      AzSensory.apply(const SensoryPreferences(forceReduceMotion: true));
      addTearDown(
          () => AzSensory.apply(const SensoryPreferences()));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            totalUnreadChatCountProvider.overrideWith((ref) async => 0),
            activeTradeCountProvider.overrideWith((ref) async => 0),
            unreadCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: PremiumBottomNav(
                selectedIndex: 0,
                onItemSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      // ONE frame: reduced motion must be settled immediately — the
      // expanding label snaps (Duration.zero), nothing is left animating.
      await tester.pump();
      expect(_labelOpacity(tester, 'Home'), 1.0,
          reason: 'reduced motion: the label is instant, not animated');
      await tester.pump(const Duration(milliseconds: 50));
      expect(_labelOpacity(tester, 'Home'), 1.0);
    });
  });

  group('5. switching tabs from a pushed page', () {
    testWidgets('the bar shows an EXPLICIT "Tabs" control — never an '
        'ellipsis — and it reopens the real pill', (tester) async {
      final requested = <int>[];
      appShellBus.engage(onTabRequest: requested.add, initialTab: 0);
      addTearDown(appShellBus.debugReset);

      final router = GoRouter(
        observers: [topRouteObserver],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: SizedBox()),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
          ),
        ],
      );
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
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
        ),
      );
      router.push('/transactions');
      await tester.pumpAndSettle();

      // The explicit control: the word "Tabs", semantics "Switch tabs".
      expect(find.text('Tabs'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch tabs'), findsOneWidget);
      expect(find.text('…'), findsNothing, reason: 'no ellipsis affordance');

      // It reopens the REAL pill.
      await tester.tap(find.byKey(const Key('contextual-nav-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contextual-nav-pill')), findsOneWidget);

      // A tab tap pops the pushed page and hands the tab to the shell.
      await tester.tap(find.byKey(const ValueKey('nav-item-2')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/',
        reason: 'the pushed page was popped back to the shell base',
      );
      expect(requested, [2], reason: 'the shell bus got the tab switch');
    });
  });
}
