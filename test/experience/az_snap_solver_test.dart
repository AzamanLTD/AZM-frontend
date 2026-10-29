import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/motion/az_snap_solver.dart';

void main() {
  group('AzSnapSolver two detents', () {
    const s = AzSnapSolver(detents: [0, 120]);

    test('below commit fraction returns lower', () {
      expect(s.resolve(40, 0), 0);
    });

    test('at/above commit fraction returns upper', () {
      expect(s.resolve(48, 0), 120);
      expect(s.resolve(100, 0), 120);
    });

    test('fling up overrides position', () {
      expect(s.resolve(10, 900), 120);
    });

    test('fling down overrides position', () {
      expect(s.resolve(110, -900), 0);
    });

    test('exact detent stays', () {
      expect(s.resolve(120, 0), 120);
      expect(s.resolve(0, 0), 0);
    });

    test('fling past the end clamps to the end detent', () {
      expect(s.resolve(120, 900), 120);
      expect(s.resolve(0, -900), 0);
    });

    test('out-of-range positions are clamped before resolving', () {
      expect(s.resolve(-50, 0), 0);
      expect(s.resolve(500, 0), 120);
    });
  });

  group('AzSnapSolver multi detent (storefront fractions)', () {
    const s = AzSnapSolver(detents: [0.46, 0.62, 0.78]);

    test('nearest-with-bias picks neighbouring detents only', () {
      expect(s.resolve(0.50, 0), 0.46);
      expect(s.resolve(0.56, 0), 0.62);
      expect(s.resolve(0.70, 0), 0.78);
    });

    test('a fling moves exactly one detent in its direction', () {
      expect(s.resolve(0.62, 700), 0.78);
      expect(s.resolve(0.62, -700), 0.46);
      // Even from just past a detent the fling targets the *next* one.
      expect(s.resolve(0.63, 700), 0.78);
      expect(s.resolve(0.61, -700), 0.46);
    });

    test('clamp bounds to the detent range', () {
      expect(s.clamp(0.1), 0.46);
      expect(s.clamp(0.9), 0.78);
      expect(s.clamp(0.6), 0.6);
    });
  });

  test('commitFraction is respected', () {
    const strict = AzSnapSolver(detents: [0, 100], commitFraction: 0.8);
    expect(strict.resolve(70, 0), 0);
    expect(strict.resolve(80, 0), 100);
  });
}