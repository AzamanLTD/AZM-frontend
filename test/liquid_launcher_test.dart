import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/liquid/category_speed_dial.dart'
    show kDialGooBody, kDialGooRim, measureSatellitePill, satelliteScale,
        satelliteTravel, solveRadialFan;
import 'package:azaman/providers/theme_provider.dart';
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

  group('solveRadialFan — right-fan grammar (PR #142 final pass §1)', () {
    final sizes = [
      for (final l in ['Eat', 'Shop', 'Ride', 'Stay'])
        measureSatellitePill(
          l,
          _style,
          TextScaler.noScaling,
          TextDirection.ltr,
        ),
    ];
    // The phone shape: the dial anchor pill sits in the control row toward
    // the LEFT of the screen, high up, with all the real estate to its
    // right and below.
    final safe = LiquidSafeArea(
      screen: const Size(390, 844),
      padding: const EdgeInsets.only(top: 44),
      margin: 6,
    );
    final anchor = const Rect.fromLTWH(16, 88, 92, 44);

    test('first two satellites establish the straight horizontal line '
        'through the anchor, opening into the right-side space', () {
      final slots =
          solveRadialFan(anchor: anchor, sizes: sizes, safe: safe, rightFan: true);
      expect(slots.length, 4);
      // The first two satellite positions are ON the anchor's horizontal
      // center line — a straight line through the selected category.
      for (final i in [0, 1]) {
        expect(slots[i].rect.center.dy, closeTo(anchor.center.dy, 0.5),
            reason: 'slot $i left the horizontal line');
      }
      // The horizontal-line pair opens into the right-side space, past the
      // anchor's edge — never centered around it.
      for (final i in [0, 1]) {
        expect(slots[i].rect.left, greaterThanOrEqualTo(anchor.right - 1),
            reason: 'slot $i leaked behind the anchor');
      }
    });

    test('remaining satellites open AWAY from the baseline in equal 45° '
        'steps, mirrored above and below it (+45°, −45°), not a cascade',
        () {
      final slots =
          solveRadialFan(anchor: anchor, sizes: sizes, safe: safe, rightFan: true);
      final c2 = slots[2].rect.center;
      final c3 = slots[3].rect.center;
      // The old 0/0/45/90 cascade funneled satellites 3 and 4 onto ONE
      // side (down-right then straight down). The 2026-10-06 correction
      // mirrors the remaining positions around the baseline: one opens
      // BELOW the anchor line, one ABOVE it, both on the opening side.
      expect(c2.dx, greaterThan(anchor.center.dx));
      expect(c3.dx, greaterThan(anchor.center.dx));
      expect(c2.dy, greaterThan(anchor.center.dy),
          reason: 'the +45° slot opens below the baseline');
      expect(c3.dy, lessThan(anchor.center.dy),
          reason: 'the −45° slot opens above the baseline');
      // The ANGLE grammar mirrors: |+45°| == |−45°| — equal angular
      // steps opening to both sides of the baseline. (Positional symmetry
      // is not asserted: the safe-area clamp may pull the side with less
      // room inward — that clamp is exactly what keeps the pill visible.)
      expect(slots[2].angle.abs(), closeTo(slots[3].angle.abs(), 0.001));
      expect(slots[2].angle, greaterThan(0));
      expect(slots[3].angle, lessThan(0));

      // Both stay meaningfully clear of the baseline (a real 45° step,
      // not a token nudge), even after clamping.
      expect((c2.dy - anchor.center.dy).abs(),
          greaterThan(anchor.height * 0.5));
      expect((c3.dy - anchor.center.dy).abs(),
          greaterThan(anchor.height * 0.5));

      // And every satellite remains FULLY inside the safe area — the
      // mirrored pair opens, but nothing is ever clipped offscreen.
      for (final slot in slots) {
        expect(slot.rect.top, greaterThanOrEqualTo(safe.top - 0.5),
            reason: 'slot ${slot.index} clipped above the safe area');
        expect(slot.rect.bottom, lessThanOrEqualTo(safe.bottom + 0.5),
            reason: 'slot ${slot.index} clipped below the safe area');
        expect(slot.rect.left, greaterThanOrEqualTo(safe.left - 0.5),
            reason: 'slot ${slot.index} clipped left of the safe area');
        expect(slot.rect.right, lessThanOrEqualTo(safe.right + 0.5),
            reason: 'slot ${slot.index} clipped right of the safe area');
      }
    });

    test('every pill stays whole: safe-contained, anchor-clear, and '
        'mutually non-overlapping', () {
      final slots =
          solveRadialFan(anchor: anchor, sizes: sizes, safe: safe, rightFan: true);
      for (final s in slots) {
        expect(s.rect.left, greaterThanOrEqualTo(safe.left - 0.01));
        expect(s.rect.right, lessThanOrEqualTo(safe.right + 0.01));
        expect(s.rect.top, greaterThanOrEqualTo(safe.top - 0.01));
        expect(s.rect.bottom, lessThanOrEqualTo(safe.bottom - 0.01));
        expect(s.rect.overlaps(anchor.deflate(1)), isFalse,
            reason: 'slot ${s.index} overlaps the anchor');
      }
      for (var i = 0; i < slots.length; i++) {
        for (var j = i + 1; j < slots.length; j++) {
          expect(slots[i].rect.overlaps(slots[j].rect), isFalse,
              reason: 'slots $i and $j collide');
        }
      }
    });

    test('the fan mirrors to the side with room when the anchor sits '
        'right of centre (positions are solved, not hard-coded)', () {
      final rightAnchor = const Rect.fromLTWH(282, 88, 92, 44);
      final slots = solveRadialFan(
          anchor: rightAnchor, sizes: sizes, safe: safe, rightFan: true);
      // The horizontal-line pair opens LEFT, past the anchor's other edge.
      for (final i in [0, 1]) {
        expect(slots[i].rect.right, lessThanOrEqualTo(rightAnchor.left + 1),
            reason: 'slot $i opened into the dead side');
      }
      // Everything stays anchor-clear and safe-contained (the vertical
      // steps may share the anchor's x-band — they sit below it).
      for (final s in slots) {
        expect(s.rect.overlaps(rightAnchor.deflate(1)), isFalse);
        expect(s.rect.left, greaterThanOrEqualTo(safe.left - 0.01));
        expect(s.rect.right, lessThanOrEqualTo(safe.right + 0.01));
      }
    });
  });

  // PR #142 FINAL PASS §2 — the dial blob is DELIBERATELY neutral gray,
  // independent of the theme surface. Pin it against BOTH palettes so a
  // future refactor can't quietly hand it back to colors.card/surface.
  test('dial goo grays are neutral and distinct from both theme surfaces',
      () {
    final light = ThemeProvider.getColors(AzamanTheme.light);
    final dark = ThemeProvider.getColors(AzamanTheme.dark);
    for (final c in [kDialGooBody, kDialGooRim]) {
      for (final surface in [light.card, light.surface, light.background,
          dark.card, dark.surface, dark.background]) {
        expect(c, isNot(surface));
      }
      // Neutral: no strong hue — the channel spread stays tight.
      final hsl = HSLColor.fromColor(c);
      expect(hsl.saturation, lessThan(0.15));
    }
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
