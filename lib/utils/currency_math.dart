// =============================================================================
// AZAMAN — CURRENCY MATH (decimal-safe conversions, 2026-10-20)
//
// ONE conversion path for GHS ⇄ USDC. The wheel and the Send composer both
// route through here — no screen re-implements the arithmetic.
//
// DIRECTION (rate is GHS per USDC — the backend's liveRetailRate):
//   GHS → USDC : amountGhs / ghsPerUsdc
//   USDC → GHS : amountUsdc * ghsPerUsdc
//
// ROUNDING POLICY (documented, tested):
//   • Conversions round HALF-UP to the destination unit's minor digits
//     (2 for both GHS and USDC — pesewas / cents), computed on the
//     scaled integer so binary-float representation error can never
//     turn x.005 into x.004999… and round the wrong way.
//   • Rounding is VISIBLE by construction: the rounded value is the one
//     shown on Review and the one sent on the wire — they are the same
//     number, so a rounded display can never differ from the payload.
//   • A conversion that rounds to zero is NOT a valid money amount:
//     [convert] returns null (fail closed) — a GH₵ 0.01 entry can never
//     silently become a 0.00 USDC transfer.
//   • A non-positive / non-finite / unusable rate never converts.
// =============================================================================

import 'dart:math' as math;

import 'package:azaman/models/currency_catalog.dart';

abstract final class CurrencyMath {
  const CurrencyMath._();

  /// True when the rate can drive a conversion at all. This is the ONLY
  /// gate; every converting call site must check it first.
  static bool isUsableRate(double ghsPerUsdc) =>
      ghsPerUsdc.isFinite && ghsPerUsdc > 0;

  /// Half-up rounding to [decimals] minor digits, on the scaled integer.
  /// `roundTo(2.345)` → 2.35; `roundTo(2.005)` → 2.01 (not 2.00 — the
  /// scaled-integer path does not suffer the 2.004999… float artefact).
  static double roundTo(double value, int decimals) {
    if (!value.isFinite) return 0;
    final scale = math.pow(10, decimals).toDouble();
    final scaled = value * scale;
    // Epsilon guard: the multiply can land a hair below/above the true
    // scaled value (e.g. 1.005 * 100 == 100.49999999999999). The half-up
    // boundary is exactly the dangerous spot, so nudge by a tiny relative
    // epsilon before the integer cut — small enough to never round two
    // different values together, large enough to beat float noise.
    final guarded = scaled + (scaled.isNegative ? -1e-9 : 1e-9) * math.max(1, scaled.abs());
    return (guarded + 0.5).floorToDouble() / scale;
  }

  /// Converts [amount] from [from] to [to] using a validated rate.
  ///
  /// Returns the EXACT reviewed number (already rounded to the destination
  /// unit's minor digits), or null when the conversion cannot be
  /// established safely (unusable rate, non-finite amount, or a result
  /// that rounds to zero — a zero transfer is never valid money).
  static double? convert({
    required double amount,
    required AzCurrency from,
    required AzCurrency to,
    required double ghsPerUsdc,
  }) {
    if (!isUsableRate(ghsPerUsdc)) return null;
    if (!amount.isFinite || amount <= 0) return null;
    if (from.code == to.code) {
      // Same unit: no conversion, but still normalize to the unit's
      // precision so the reviewed value and the wire value agree.
      return roundTo(amount, to.wireDecimals);
    }

    final double raw;
    if (from.code == 'GHS' && to.code == 'USDC') {
      raw = amount / ghsPerUsdc;
    } else if (from.code == 'USDC' && to.code == 'GHS') {
      raw = amount * ghsPerUsdc;
    } else {
      // No invented cross-path (e.g. no GHS→BTC-through-USDC guessing).
      return null;
    }

    final rounded = roundTo(raw, to.wireDecimals);
    return rounded > 0 ? rounded : null;
  }
}
