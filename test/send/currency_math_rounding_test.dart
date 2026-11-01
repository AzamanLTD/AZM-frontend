// =============================================================================
// AZAMAN — CURRENCY MATH ROUNDING CONTRACT (PR #165 review §3)
//
// The exact reviewed amount and the actual wire amount must match. This
// suite pins the decimal-safe rounding against the r2 failure modes:
//   • an already-exact large value is never nudged by an epsilon
//   • both directions round half-up on true decimal digits
//   • amounts near the minimum non-zero wire amount fail closed at zero
//   • repeat conversions are precision-stable (no drift through cycles)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/utils/currency_math.dart';

void main() {
  group('roundTo — exact values stay exact', () {
    test('large exact values are never nudged (the r2 regression)', () {
      // The previous relative-epsilon approach turned this into
      // 9,999,999.01 — a materially different wire amount.
      expect(CurrencyMath.roundTo(9999999.00, 2), 9999999.00);
      expect(CurrencyMath.roundTo(9999999.99, 2), 9999999.99);
      expect(CurrencyMath.roundTo(12345678.90, 2), 12345678.90);
      expect(CurrencyMath.roundTo(1000000.00, 2), 1000000.00);
    });

    test('exact values at other precisions', () {
      expect(CurrencyMath.roundTo(2.30, 2), 2.30);
      expect(CurrencyMath.roundTo(0.01, 2), 0.01);
      expect(CurrencyMath.roundTo(4, 2), 4.0);
      expect(CurrencyMath.roundTo(9999999.0, 0), 9999999.0);
    });

    test('half-up boundaries round UP on true halves', () {
      expect(CurrencyMath.roundTo(2.005, 2), 2.01);
      expect(CurrencyMath.roundTo(0.125, 2), 0.13);
      expect(CurrencyMath.roundTo(0.135, 2), 0.14);
      expect(CurrencyMath.roundTo(1.005, 2), 1.01);
    });

    test('below the half boundary stays DOWN', () {
      expect(CurrencyMath.roundTo(2.004, 2), 2.00);
      expect(CurrencyMath.roundTo(2.004999999999999, 2), 2.00);
      expect(CurrencyMath.roundTo(9.994999, 2), 9.99);
    });

    test('non-finite and zero safe-fail to 0', () {
      expect(CurrencyMath.roundTo(double.nan, 2), 0);
      expect(CurrencyMath.roundTo(double.infinity, 2), 0);
      expect(CurrencyMath.roundTo(0, 2), 0);
    });
  });

  group('convert — both directions', () {
    const rate = 15.38; // GHS per USDC

    test('GHS → USDC at the documented rate', () {
      // 5.00 / 15.38 = 0.325097... → 0.33
      expect(
        CurrencyMath.convert(
          amount: 5.0,
          from: CurrencyCatalog.ghs,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: rate,
        ),
        0.33,
      );
    });

    test('USDC → GHS at the documented rate', () {
      // 0.33 * 15.38 = 5.0754 → 5.08
      expect(
        CurrencyMath.convert(
          amount: 0.33,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.ghs,
          ghsPerUsdc: rate,
        ),
        5.08,
      );
    });

    test('large GHS amounts convert without epsilon distortion', () {
      final usdc = CurrencyMath.convert(
        amount: 9999999.00,
        from: CurrencyCatalog.ghs,
        to: CurrencyCatalog.usdc,
        ghsPerUsdc: rate,
      );
      expect(usdc, isNotNull);
      // 9999999 / 15.38 = 650194.99349... → 650194.99
      expect(usdc, 650194.99);
      // And the SAME rate back is exact decimal math on the same grid:
      final back = CurrencyMath.convert(
        amount: usdc!,
        from: CurrencyCatalog.usdc,
        to: CurrencyCatalog.ghs,
        ghsPerUsdc: rate,
      );
      expect(back, 9999998.95); // 650194.99 * 15.38 exactly
    });

    test('unusable rate never converts cross-unit', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          CurrencyMath.convert(
            amount: 5.0,
            from: CurrencyCatalog.ghs,
            to: CurrencyCatalog.usdc,
            ghsPerUsdc: bad,
          ),
          isNull,
          reason: 'rate $bad must fail closed',
        );
      }
    });
  });

  group('convert — same unit needs no rate (§1)', () {
    test('a direct USDC entry is the wire amount with NO usable rate', () {
      // The FX equivalent being unavailable must never block a direct
      // USDC transfer — the amount is already in the wire unit.
      expect(
        CurrencyMath.convert(
          amount: 5.0,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 0,
        ),
        5.0,
      );
      expect(
        CurrencyMath.convert(
          amount: 5.0,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: double.nan,
        ),
        5.0,
      );
    });

    test('same-unit values normalise to wire precision exactly', () {
      expect(
        CurrencyMath.convert(
          amount: 9999999.00,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 0,
        ),
        9999999.00,
      );
      expect(
        CurrencyMath.convert(
          amount: 5.001,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        ),
        5.0,
      );
    });
  });

  group('convert — the zero-round fail-closed rule', () {
    test('amounts below the smallest unit never become a wire amount', () {
      // 0.01 GHS at 15.38 = 0.00065 USDC → rounds to 0.00 → null.
      expect(
        CurrencyMath.convert(
          amount: 0.01,
          from: CurrencyCatalog.ghs,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        ),
        isNull,
      );
      // 0.001 USDC direct → rounds to 0.00 → null (no zero wire).
      expect(
        CurrencyMath.convert(
          amount: 0.001,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        ),
        isNull,
      );
    });

    test('amounts just above the minimum DO convert', () {
      // 0.16 GHS at 15.38 = 0.01040... → 0.01 USDC — the smallest wire.
      expect(
        CurrencyMath.convert(
          amount: 0.16,
          from: CurrencyCatalog.ghs,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        ),
        0.01,
      );
      expect(
        CurrencyMath.convert(
          amount: 0.01,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        ),
        0.01,
      );
    });
  });

  group('precision stability across repeated conversions (§3)', () {
    test('repeated GHS→USDC→GHS cycles are stable from the third cycle on', () {
      var current = 100.00;
      final seen = <double>[];
      for (var i = 0; i < 8; i++) {
        final usdc = CurrencyMath.convert(
          amount: current,
          from: CurrencyCatalog.ghs,
          to: CurrencyCatalog.usdc,
          ghsPerUsdc: 15.38,
        );
        final back = CurrencyMath.convert(
          amount: usdc!,
          from: CurrencyCatalog.usdc,
          to: CurrencyCatalog.ghs,
          ghsPerUsdc: 15.38,
        );
        expect(back, isNotNull);
        current = back!;
        seen.add(back);
      }
      // After the first rounding slip the cycle value must be a fixed
      // point — no creeping drift through repeated conversion.
      for (var i = 2; i < seen.length; i++) {
        expect(
          seen[i],
          seen[i - 1],
          reason: 'conversion cycle drifted at iteration $i',
        );
      }
    });

    test('the same input always produces the same output', () {
      for (var i = 0; i < 50; i++) {
        expect(
          CurrencyMath.convert(
            amount: 1234.56,
            from: CurrencyCatalog.ghs,
            to: CurrencyCatalog.usdc,
            ghsPerUsdc: 15.38,
          ),
          80.27,
        );
      }
    });
  });
}
