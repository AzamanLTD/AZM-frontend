import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/marketplace_tempo.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('MarketplaceTempo — the commit ladder', () {
    test('preserves the shipped RestaurantCommitSurface values', () {
      expect(
        MarketplaceTempo.commit(MarketplaceMotionTempo.relaxed),
        const Duration(milliseconds: 820),
      );
      expect(
        MarketplaceTempo.commit(MarketplaceMotionTempo.balanced),
        const Duration(milliseconds: 720),
      );
      expect(
        MarketplaceTempo.commit(MarketplaceMotionTempo.quick),
        const Duration(milliseconds: 560),
      );
    });
  });

  group('MarketplaceTempo — the standard ladder', () {
    testWidgets('preserves the shipped blueprint.motionDuration values',
        (tester) async {
      await tester.pumpWidget(_host(const SizedBox(key: Key('tempo-context'))));
      final context = tester.element(find.byKey(const Key('tempo-context')));

      expect(
        MarketplaceTempo.standard(context, MarketplaceMotionTempo.relaxed),
        const Duration(milliseconds: 450),
      );
      expect(
        MarketplaceTempo.standard(context, MarketplaceMotionTempo.balanced),
        const Duration(milliseconds: 220),
      );
      expect(
        MarketplaceTempo.standard(context, MarketplaceMotionTempo.quick),
        const Duration(milliseconds: 180),
      );
    });
  });

  group('MarketplaceTempo — reduced motion', () {
    testWidgets('collapses durations to zero', (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(key: Key('tempo-context')),
        disableAnimations: true,
      ));
      final context = tester.element(find.byKey(const Key('tempo-context')));

      expect(
        MarketplaceTempo.standard(context, MarketplaceMotionTempo.relaxed),
        Duration.zero,
      );
      expect(
        MarketplaceTempo.scaled(
          context,
          MarketplaceMotionTempo.quick,
          const Duration(milliseconds: 1000),
        ),
        Duration.zero,
      );
    });
  });

  group('MarketplaceTempo — the multiplier', () {
    test('is monotonic: relaxed > balanced > quick', () {
      final relaxed =
          MarketplaceTempo.multiplierOf(MarketplaceMotionTempo.relaxed);
      final balanced =
          MarketplaceTempo.multiplierOf(MarketplaceMotionTempo.balanced);
      final quick = MarketplaceTempo.multiplierOf(MarketplaceMotionTempo.quick);
      expect(relaxed, greaterThan(balanced));
      expect(balanced, greaterThan(quick));
    });

    testWidgets('scaled() applies the multiplier to any duration',
        (tester) async {
      await tester.pumpWidget(_host(const SizedBox(key: Key('tempo-context'))));
      final context = tester.element(find.byKey(const Key('tempo-context')));

      expect(
        MarketplaceTempo.scaled(
          context,
          MarketplaceMotionTempo.relaxed,
          const Duration(milliseconds: 200),
        ),
        const Duration(milliseconds: 250),
      );
      expect(
        MarketplaceTempo.scaled(
          context,
          MarketplaceMotionTempo.quick,
          const Duration(milliseconds: 200),
        ),
        const Duration(milliseconds: 144),
      );
    });

    testWidgets('stagger() is tempo-aware and monotonic per index',
        (tester) async {
      await tester.pumpWidget(_host(const SizedBox(key: Key('tempo-context'))));
      final context = tester.element(find.byKey(const Key('tempo-context')));

      // Index 0 is deliberately EXCLUDED. `MotionTokens.staggerDelay(0)` is
      // `Duration.zero` for every tempo — the first item in a sequence is
      // never delayed, whatever the multiplier. Comparing tempos at index 0
      // asserts that a multiplier applies to zero, which is meaningless.
      expect(
        MarketplaceTempo.stagger(context, MarketplaceMotionTempo.relaxed, 0),
        Duration.zero,
        reason: 'index 0 is undelayed for every tempo',
      );

      for (var i = 1; i < 4; i++) {
        final quick = MarketplaceTempo.stagger(context, MarketplaceMotionTempo.quick, i);
        final balanced =
            MarketplaceTempo.stagger(context, MarketplaceMotionTempo.balanced, i);
        final relaxed =
            MarketplaceTempo.stagger(context, MarketplaceMotionTempo.relaxed, i);
        expect(relaxed > balanced, isTrue, reason: 'index $i');
        expect(balanced > quick, isTrue, reason: 'index $i');
      }
    });
  });

  group('MarketplaceTempo — curves', () {
    test('every tempo returns a curve for enter and exit', () {
      for (final tempo in MarketplaceMotionTempo.values) {
        expect(MarketplaceTempo.enterCurve(tempo), isA<Curve>());
        expect(MarketplaceTempo.exitCurve(tempo), isA<Curve>());
      }
    });
  });
}
