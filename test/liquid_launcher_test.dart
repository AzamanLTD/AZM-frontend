import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/liquid/category_speed_dial.dart'
    show measureSatellitePill, satelliteScale, satelliteTravel, solveRadialFan;
import 'package:azaman/widgets/liquid/liquid_launcher.dart';
import 'package:azaman/widgets/liquid/liquid_placement.dart';

// Must match the launcher's rendered satellite TextStyle metrics (Step 1).
const _style = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  decoration: TextDecoration.none,
);

List<LiquidLauncherItem> _items(List<String> picked) => [
  LiquidLauncherItem(
    icon: Icons.shopping_bag_outlined,
    label: 'Retail',
    onTap: () => picked.add('Retail'),
  ),
  LiquidLauncherItem(
    icon: Icons.restaurant_outlined,
    label: 'Restaurants',
    onTap: () => picked.add('Restaurants'),
  ),
  LiquidLauncherItem(
    icon: Icons.directions_bus_outlined,
    label: 'Transit',
    onTap: () => picked.add('Transit'),
  ),
  LiquidLauncherItem(
    icon: Icons.apartment_outlined,
    label: 'Hotels',
    onTap: () => picked.add('Hotels'),
  ),
];

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 390, height: 190, child: child)),
    ),
  ),
);

Widget _reducedHost(Widget child) => ProviderScope(
  child: MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        body: Center(child: SizedBox(width: 390, height: 190, child: child)),
      ),
    ),
  ),
);

void main() {
  group('satelliteScale', () {
    test('rests at the rest scale before its beat', () {
      final s = satelliteScale(0.0, 0);
      expect(s.sx, closeTo(0.12, 1e-9));
      expect(s.sy, closeTo(0.12, 1e-9));
    });

    test('mid-launch is between the ooze base and full scale', () {
      final s = satelliteScale(0.3, 0);
      expect(s.sy, greaterThan(0.42));
      expect(s.sy, lessThan(1.0));
    });

    test('fully launched at t = 1', () {
      // The damped-spring step response settles to 1 only to ~1e-4 — the
      // curve's endpoint residual, not a bug. Pin "fully launched" with an
      // honest tolerance.
      final s = satelliteScale(1.0, 0);
      expect(s.sx, closeTo(1.0, 1e-3));
      expect(s.sy, closeTo(1.0, 1e-3));
    });

    test('later indices launch later', () {
      final early = satelliteScale(0.3, 0);
      final late = satelliteScale(0.3, 3);
      expect(late.sy, lessThanOrEqualTo(early.sy));
    });
  });

  group('satelliteTravel', () {
    test('starts at zero and settles at one', () {
      expect(satelliteTravel(0.0, 0), 0.0);
      // Endpoint residual of the spring curve (~1e-4) — use a tolerance.
      expect(satelliteTravel(1.0, 0), closeTo(1.0, 1e-3));
      expect(satelliteTravel(1.0, 3), closeTo(1.0, 1e-3));
    });

    // satelliteTravel rides kHouseSpring, whose step response OVERSHOOTS
    // (~22%) before settling — it is deliberately NOT monotonic. Assert the
    // real contract: launch past the slot, then settle back onto it.
    test('springs past one mid-flight then settles to one', () {
      var peak = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        peak = math.max(peak, satelliteTravel(t, 1));
      }
      expect(peak, greaterThan(1.0));
      expect(satelliteTravel(0.95, 1), closeTo(1.0, 1e-3));
    });
  });

  group('solveRadialFan', () {
    const labels = ['Retail', 'Restaurants', 'Transit', 'Hotels'];
    final sizes = [
      for (final l in labels)
        measureSatellitePill(
          l,
          _style,
          TextScaler.noScaling,
          TextDirection.ltr,
        ),
    ];
    final safe = LiquidSafeArea(
      screen: const Size(390, 190),
      padding: EdgeInsets.zero,
      margin: 6,
    );
    final anchor = Rect.fromCenter(
      center: const Offset(195, 95),
      width: 44,
      height: 44,
    );

    test('returns one slot per item, all inside the safe area', () {
      final slots = solveRadialFan(anchor: anchor, sizes: sizes, safe: safe);
      expect(slots.length, 4);
      for (final s in slots) {
        expect(s.rect.left, greaterThanOrEqualTo(safe.left - 0.01));
        expect(s.rect.right, lessThanOrEqualTo(safe.right + 0.01));
        expect(s.rect.top, greaterThanOrEqualTo(safe.top - 0.01));
        expect(s.rect.bottom, lessThanOrEqualTo(safe.bottom + 0.01));
      }
    });

    // Structurally guaranteed by anchorClearance (≥ gap): assert it stays so.
    // Pairwise slot non-overlap is NOT asserted — the safe-area clamp may
    // nudge slots together on tight hosts (shipped dial behaviour).
    test('no slot overlaps the anchor', () {
      final slots = solveRadialFan(anchor: anchor, sizes: sizes, safe: safe);
      for (final s in slots) {
        expect(
          s.rect.overlaps(anchor.deflate(1)),
          isFalse,
          reason: 'slot ${s.index} overlaps the anchor',
        );
      }
    });

    test('empty input yields empty slots', () {
      expect(
        solveRadialFan(anchor: anchor, sizes: const [], safe: safe),
        isEmpty,
      );
    });

    // Production shape (audit 2026-09-29): the Market sheet hosts FIVE
    // satellites (the shipped kVerticalLauncherEntries incl. Hospitality)
    // in a tight host — pin that the clamp keeps them safe + anchor-clear.
    test('production shape: five satellites stay inside a tight host', () {
      final five = [
        for (final l in [
          'Restaurants',
          'Hotels',
          'Transit',
          'Retail',
          'Hospitality',
        ])
          measureSatellitePill(
            l,
            _style,
            TextScaler.noScaling,
            TextDirection.ltr,
          ),
      ];
      final tight = LiquidSafeArea(
        screen: const Size(358, 190),
        padding: EdgeInsets.zero,
        margin: 6,
      );
      final centre = Rect.fromCenter(
        center: const Offset(179, 95),
        width: 44,
        height: 44,
      );
      final slots = solveRadialFan(anchor: centre, sizes: five, safe: tight);
      expect(slots.length, 5);
      for (final s in slots) {
        expect(s.rect.left, greaterThanOrEqualTo(tight.left - 0.01));
        expect(s.rect.right, lessThanOrEqualTo(tight.right + 0.01));
        expect(s.rect.top, greaterThanOrEqualTo(tight.top - 0.01));
        expect(s.rect.bottom, lessThanOrEqualTo(tight.bottom + 0.01));
        expect(
          s.rect.overlaps(centre.deflate(1)),
          isFalse,
          reason: 'slot ${s.index} overlaps the anchor',
        );
      }
    });
  });

  group('LiquidLauncher widget', () {
    testWidgets('auto-opens: satellites burst and settle in place', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          LiquidLauncher(items: _items([]), semanticLabel: 'Market verticals'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retail'), findsOneWidget);
      expect(find.text('Restaurants'), findsOneWidget);
      expect(find.text('Transit'), findsOneWidget);
      expect(find.text('Hotels'), findsOneWidget);
      expect(find.bySemanticsLabel('Market verticals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the first item lands above the last item', (tester) async {
      await tester.pumpWidget(_host(LiquidLauncher(items: _items([]))));
      await tester.pumpAndSettle();

      final retailY = tester.getTopLeft(find.text('Retail')).dy;
      final hotelsY = tester.getTopLeft(find.text('Hotels')).dy;
      expect(retailY, lessThan(hotelsY));
    });

    testWidgets('a pick fires its callback exactly once', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(_host(LiquidLauncher(items: _items(picked))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transit'));
      await tester.pumpAndSettle();
      expect(picked, ['Transit']);
    });

    testWidgets('reduced motion renders the settled burst immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_reducedHost(LiquidLauncher(items: _items([]))));
      // Post-frame solve + one more frame; under reduced motion the burst
      // renders at t = 1 from the start.
      await tester.pump();
      await tester.pump();

      expect(find.text('Retail'), findsOneWidget);
      expect(find.text('Hotels'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('unbounded host does not crash and renders nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(children: [LiquidLauncher(items: _items([]))]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Retail'), findsNothing);
    });
  });
}
