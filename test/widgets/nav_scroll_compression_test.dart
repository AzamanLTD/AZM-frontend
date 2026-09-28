// =============================================================================
// TASK-010 — Nav pill scroll-reactive compression: regression suite
//
// Pins the acceptance invariants of the build brief, not widget existence:
//
//   * the compression value is a pure function of the page's ABSOLUTE offset
//     (deterministic, bounded, reversible — the same depth always yields the
//     same pill state),
//   * pull-to-refresh (negative overscroll) never compresses the nav,
//   * horizontal scrollables (the balance deck, carousels) never compress it,
//   * the value is quantised to 10 steps and does not write when unchanged
//     (a scroll that lands on the same step costs zero rebuilds),
//   * rest → compressed → rest round-trips through the widget,
//   * labels collapse over the first 60% of travel and are gone before the
//     pill reaches minimum height,
//   * reduced motion freezes the pill at rest height and full opacity,
//   * tapping a different tab still works while compressed, and re-tapping
//     the active tab does not re-issue the selection,
//   * no ValueNotifier listeners leak after the nav is torn down.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FixedScrollMetrics;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

FixedScrollMetrics _metrics(
  double pixels, {
  AxisDirection axisDirection = AxisDirection.down,
}) {
  return FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 5000,
    pixels: pixels,
    viewportDimension: 400,
    devicePixelRatio: 1,
    axisDirection: axisDirection,
  );
}

ScrollUpdateNotification _scroll(
  BuildContext context,
  double pixels, {
  AxisDirection axisDirection = AxisDirection.down,
}) {
  return ScrollUpdateNotification(
    metrics: _metrics(pixels, axisDirection: axisDirection),
    context: context,
    scrollDelta: 12.0,
  );
}

Widget _host(Widget child, {bool reduceMotion = false}) {
  return ProviderScope(
    // The badge providers' real bodies are async and hit the API; in a test
    // they resolve after the container is disposed. Pin them to inert values
    // so the nav under test never leaves the container's lifetime.
    overrides: [
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, navigatorChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: navigatorChild ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: child,
      ),
    ),
  );
}

Future<void> _pumpNav(
  WidgetTester tester, {
  int selectedIndex = 0,
  List<int> selections = const [],
  bool reduceMotion = false,
}) {
  return tester.pumpWidget(
    _host(
      PremiumBottomNav(
        selectedIndex: selectedIndex,
        onItemSelected: selections.add,
      ),
      reduceMotion: reduceMotion,
    ),
  );
}

final _navFinder = find.byType(PremiumBottomNav);

/// The nav's outer Padding: pill height + the 16px bottom inset (no safe area
/// in the test surface), so rest == 62 + 16 and compressed == 52 + 16.
double _navHeight(WidgetTester tester) => tester.getSize(
      find.descendant(of: _navFinder, matching: find.byType(Padding)).first,
    ).height;

double _pillOpacity(WidgetTester tester) => (tester.widget(
      find.descendant(of: _navFinder, matching: find.byType(Opacity)).first,
    ) as Opacity).opacity;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The notifier is global; keep each test's starting state honest.
    navScrollCompression.value = 0;
  });

  group('NavScrollCompression.fromPixels (the absolute-offset law)', () {
    test('rest and mid-travel map deterministically', () {
      expect(NavScrollCompression.fromPixels(0), 0);
      expect(NavScrollCompression.fromPixels(45), 0.5);
      expect(NavScrollCompression.fromPixels(90), 1);
    });

    test('bounded beyond the travel distance', () {
      expect(NavScrollCompression.fromPixels(1000), 1);
      expect(NavScrollCompression.fromPixels(1e9), 1);
    });

    test('pull-to-refresh overscroll (negative pixels) never compresses', () {
      expect(NavScrollCompression.fromPixels(-40), 0);
      expect(NavScrollCompression.fromPixels(-0.1), 0);
      expect(NavScrollCompression.fromPixels(double.nan), 0);
    });

    test('values are quantised to 10 steps', () {
      // 44px is 0.489 of travel — snaps to the 0.5 step, never to 0.489.
      expect(NavScrollCompression.fromPixels(44), 0.5);
      // 4px is below half a step — stays at rest.
      expect(NavScrollCompression.fromPixels(4), 0);
      // 9px crosses the first step boundary.
      expect(NavScrollCompression.fromPixels(9), 0.1);
    });

  });

  group('applyTo — the MainWrapper writer policy', () {
    // Notifications need a non-null BuildContext; pump a stub to obtain one.
    Future<BuildContext> _context(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      return tester.element(find.byType(Scaffold));
    }

    testWidgets('reversible: scrolling down and back lands on the same value',
        (tester) async {
      final ctx = await _context(tester);
      // Through the STATEFUL writer: 30px down, then to 60, then back to 30.
      // The value at a given depth must be identical however the user got
      // there — the property the old per-frame delta accumulator lost.
      NavScrollCompression.applyTo(_scroll(ctx, 30));
      expect(navScrollCompression.value, NavScrollCompression.fromPixels(30));
      NavScrollCompression.applyTo(_scroll(ctx, 60));
      NavScrollCompression.applyTo(_scroll(ctx, 30));
      expect(navScrollCompression.value, NavScrollCompression.fromPixels(30));

      // And a full down-and-up roundtrip ends exactly at rest.
      NavScrollCompression.applyTo(_scroll(ctx, 90));
      NavScrollCompression.applyTo(_scroll(ctx, 45));
      NavScrollCompression.applyTo(_scroll(ctx, 0));
      expect(navScrollCompression.value, 0);
    });

    testWidgets('a vertical scroll writes the quantised compression',
        (tester) async {
      final ctx = await _context(tester);
      final consumed = NavScrollCompression.applyTo(_scroll(ctx, 45));
      expect(consumed, isFalse, reason: 'notifications must keep bubbling');
      expect(navScrollCompression.value, 0.5);
    });

    testWidgets('the same step writes nothing (quantisation caps rebuilds)',
        (tester) async {
      final ctx = await _context(tester);
      NavScrollCompression.applyTo(_scroll(ctx, 45));
      var writes = 0;
      void listener() => writes++;
      navScrollCompression.addListener(listener);
      // Same depth again → identical step → no notification.
      NavScrollCompression.applyTo(_scroll(ctx, 46));
      NavScrollCompression.applyTo(_scroll(ctx, 47));
      expect(writes, 0);
      // Crossing into the next step → exactly one write.
      NavScrollCompression.applyTo(_scroll(ctx, 54)); // 0.6 of travel
      expect(writes, 1);
      navScrollCompression.removeListener(listener);
    });

    testWidgets('returning to the top restores rest (recovery)',
        (tester) async {
      final ctx = await _context(tester);
      NavScrollCompression.applyTo(_scroll(ctx, 90));
      expect(navScrollCompression.value, 1);
      NavScrollCompression.applyTo(_scroll(ctx, 0));
      expect(navScrollCompression.value, 0);
    });

    testWidgets(
      'horizontal scrollables never compress the vertical chrome',
      (tester) async {
        final ctx = await _context(tester);
        NavScrollCompression.applyTo(
          _scroll(ctx, 400, axisDirection: AxisDirection.right),
        );
        expect(navScrollCompression.value, 0);
      },
    );

    testWidgets('pull-to-refresh overscroll at the top does not compress',
        (tester) async {
      final ctx = await _context(tester);
      NavScrollCompression.applyTo(_scroll(ctx, -25));
      expect(navScrollCompression.value, 0);
    });
  });

  group('PremiumBottomNav widget', () {
    testWidgets('at rest: full height, full opacity, four labels', (tester) async {
      await _pumpNav(tester);
      await tester.pumpAndSettle();

      expect(_navHeight(tester), 62 + 16);
      expect(_pillOpacity(tester), 1.0);
      for (final label in ['Home', 'Chat', 'P2P', 'Market']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('fully compressed: 52px, 0.92 opacity, icon-only', (tester) async {
      await _pumpNav(tester);
      navScrollCompression.value = 1;
      await tester.pumpAndSettle();

      expect(_navHeight(tester), 52 + 16);
      expect(_pillOpacity(tester), closeTo(0.92, 0.001));
      for (final label in ['Home', 'Chat', 'P2P', 'Market']) {
        expect(find.text(label), findsNothing);
      }
      // Icons survive the compression — the pill is icon-only, not empty.
      expect(find.byIcon(HugeIconsSolid.home01), findsOneWidget);
    });

    testWidgets(
      'labels collapse over the first 60% of travel',
      (tester) async {
        await _pumpNav(tester);

        // Halfway: label opacity is 1 - 0.5/0.6 ≈ 0.17 — still mounted.
        navScrollCompression.value = 0.5;
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);

        // Past 60%: labels are gone well before minimum height.
        navScrollCompression.value = 0.7;
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsNothing);
        // …and the pill has NOT reached its compressed height yet.
        expect(_navHeight(tester), greaterThan(52 + 16));
      },
    );

    testWidgets('scrolling back to the top restores the pill', (tester) async {
      await _pumpNav(tester);
      navScrollCompression.value = 1;
      await tester.pumpAndSettle();
      expect(_navHeight(tester), 52 + 16);

      navScrollCompression.value = 0;
      await tester.pumpAndSettle();
      expect(_navHeight(tester), 62 + 16);
      expect(_pillOpacity(tester), 1.0);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets(
      'unrelated rebuilds do not restart or jitter the compression',
      (tester) async {
        await _pumpNav(tester);
        navScrollCompression.value = 0.5;
        await tester.pumpAndSettle();
        final settled = _navHeight(tester);

        // Same compression, different selected tab: an unrelated rebuild must
        // not snap the pill back to rest or replay the transition.
        await _pumpNav(tester, selectedIndex: 2);
        expect(_navHeight(tester), settled);

        // Re-writing the same quantised value: still no restart.
        navScrollCompression.value = 0.5;
        await tester.pump();
        expect(_navHeight(tester), settled);
      },
    );

    testWidgets(
      'reduced motion freezes the pill at rest height and full opacity',
      (tester) async {
        await _pumpNav(tester, reduceMotion: true);
        navScrollCompression.value = 1;
        await tester.pumpAndSettle();

        expect(_navHeight(tester), 62 + 16);
        expect(_pillOpacity(tester), 1.0);
        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping another tab works while compressed; re-tapping the active '
      'tab does not re-issue the selection',
      (tester) async {
        final selections = <int>[];
        await tester.pumpWidget(
          _host(
            PremiumBottomNav(
              selectedIndex: 0,
              onItemSelected: selections.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Compress, then tap the (unselected) Chat icon.
        navScrollCompression.value = 1;
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(HugeIconsStroke.message01));
        await tester.pump();
        expect(selections, [1]);

        // The app answers the selection by rebuilding the nav with the new
        // index. Re-tapping the NOW-ACTIVE Chat tab must not re-issue the
        // selection: it is an acknowledgment, not another selection.
        await tester.pumpWidget(
          _host(
            PremiumBottomNav(
              selectedIndex: 1,
              onItemSelected: selections.add,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(HugeIconsSolid.message01));
        await tester.pump();
        expect(selections, [1], reason: 'active-tab re-tap must be a no-op');
      },
    );

    testWidgets(
      'layout safety: no overflow at a small surface',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpNav(tester);
        navScrollCompression.value = 1;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tearing the nav down removes its notifier listeners', (tester) async {
      expect(navScrollCompression.hasListeners, isFalse,
          reason: 'tests must not leak listeners into each other');
      await _pumpNav(tester);
      await tester.pumpAndSettle();
      expect(navScrollCompression.hasListeners, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(navScrollCompression.hasListeners, isFalse);
    });
  });
}
