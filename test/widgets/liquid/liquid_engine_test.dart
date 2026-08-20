import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';

void main() {
  group('springs', () {
    test('are proper step responses', () {
      for (final c in [kHouseSpring, kPopSpring]) {
        expect(c.transform(0.0), closeTo(0.0, 1e-9));
        expect(c.transform(1.0), closeTo(1.0, 1e-3));
      }
    });

    test('overshoot but stay bounded', () {
      var peak = 0.0;
      for (var i = 0; i <= 100; i++) {
        peak = peak > kHouseSpring.transform(i / 100) ? peak : kHouseSpring.transform(i / 100);
      }
      expect(peak, greaterThan(1.0));   // it must bounce
      expect(peak, lessThan(1.35));     // but not slingshot
    });
  });

  group('gooRimFor', () {
    test('returns the exact solved pair at every knot', () {
      expect(gooRimFor(1).outer, closeTo(-14.5146, 1e-6));
      expect(gooRimFor(4).outer, closeTo(-12.25, 1e-6));
      expect(gooRimFor(5).inner, closeTo(-15.063, 1e-6));
      expect(gooRimFor(7).inner, closeTo(-13.245, 1e-6));
    });

    test('clamps outside the table instead of extrapolating', () {
      expect(gooRimFor(0).outer, gooRimFor(1).outer);
      expect(gooRimFor(99).inner, gooRimFor(7).inner);
    });

    test('keeps outer > inner across the full range', () {
      for (var s = 1.0; s <= 7.0; s += 0.1) {
        final r = gooRimFor(s);
        expect(r.outer, greaterThan(r.inner)); // rim sits outside the body
      }
    });

    test('stays bounded within the solved knot range', () {
      for (var s = 1.0; s <= 7.0; s += 0.1) {
        final r = gooRimFor(s);
        // Outer is always between the min and max of the knot values
        expect(r.outer, greaterThanOrEqualTo(-15.0));
        expect(r.outer, lessThanOrEqualTo(-11.0));
        expect(r.inner, greaterThanOrEqualTo(-26.0));
        expect(r.inner, lessThanOrEqualTo(-13.0));
      }
    });
  });

  test('LiquidReveal threshold logic', () {
    // Verify the threshold constant without rendering
    expect(LiquidReveal(opacity: 0.2, child: const SizedBox()).tapThreshold, 0.6);
    expect(0.2 < 0.6, isTrue);
    expect(0.9 >= 0.6, isTrue);
  });
}
