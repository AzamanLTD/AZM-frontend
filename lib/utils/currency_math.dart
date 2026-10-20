// =============================================================================
// AZAMAN — CURRENCY MATH (decimal-safe conversions, 2026-10-20 r2)
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
//     (2 for both GHS and USDC — pesewas / cents). The rounding runs on
//     the EXACT DECIMAL DIGITS of the double (its shortest round-trip
//     string), never on a re-scaled binary float — so no epsilon guard is
//     needed and an already-exact value can never be nudged: 9,999,999.00
//     stays 9,999,999.00, while a true half (2.005 entered as 2.005)
//     rounds up as documented. (r2, PR #165 review §3: the previous
//     relative-epsilon approach could round exact large values up by a
//     minor unit.)
//   • Rounding is VISIBLE by construction: the rounded value is the one
//     shown on Review and the one sent on the wire — they are the same
//     number, so a rounded display can never differ from the payload.
//   • A conversion that rounds to zero is NOT a valid money amount:
//     [convert] returns null (fail closed) — a GH₵ 0.01 entry can never
//     silently become a 0.00 USDC transfer, and a 0.001 USDC direct
//     entry cannot become a 0.00 wire either.
//   • A non-positive / non-finite / unusable rate never converts a
//     CROSS-unit amount. A SAME-UNIT amount needs no rate at all: a
//     direct USDC entry is already the USDC wire amount and must not be
//     blocked because the optional FX equivalent cannot be displayed
//     (PR #165 review §1).
// =============================================================================

import 'package:azaman/models/currency_catalog.dart';

abstract final class CurrencyMath {
  const CurrencyMath._();

  /// True when the rate can drive a conversion at all. The ONLY gate for
  /// cross-unit paths; every converting call site must check it first.
  static bool isUsableRate(double ghsPerUsdc) =>
      ghsPerUsdc.isFinite && ghsPerUsdc > 0;

  /// Half-up rounding to [decimals] minor digits, on the EXACT decimal
  /// digits of [value].
  ///
  /// `roundTo(2.345, 2)` → 2.35; `roundTo(2.005, 2)` → 2.01; and — the r2
  /// contract — `roundTo(9999999.00, 2)` → 9999999.00 exactly (no epsilon
  /// can move an already-exact amount).
  ///
  /// Method: the double's shortest round-trip string is the honest decimal
  /// the value represents (Dart's `toString()` never invents digits). The
  /// string is cut at the requested precision and half-up applied to the
  /// first dropped digit — pure decimal-string arithmetic, immune to both
  /// the `1.005 * 100 == 100.49999999999999` scaling artefact and to any
  /// epsilon guesswork.
  static double roundTo(double value, int decimals) {
    if (!value.isFinite) return 0;
    if (decimals < 0) return 0;
    if (value < 0) return -roundTo(-value, decimals);

    // Normalise the shortest round-trip string into plain digits:
    // mantissa + optional exponent → [intDigits, fracDigits].
    var mantissa = value.abs().toString();
    var exponent = 0;
    if (mantissa.contains('e') || mantissa.contains('E')) {
      final parts = mantissa.split(RegExp('[eE]'));
      mantissa = parts[0];
      exponent = int.tryParse(parts[1]) ?? 0;
    }
    final dot = mantissa.indexOf('.');
    var intDigits = dot == -1 ? mantissa : mantissa.substring(0, dot);
    var fracDigits = dot == -1 ? '' : mantissa.substring(dot + 1);

    if (exponent > 0) {
      if (fracDigits.length <= exponent) {
        intDigits = intDigits + fracDigits + '0' * (exponent - fracDigits.length);
        fracDigits = '';
      } else {
        intDigits = intDigits + fracDigits.substring(0, exponent);
        fracDigits = fracDigits.substring(exponent);
      }
    } else if (exponent < 0) {
      final shift = -exponent;
      if (intDigits.length > shift) {
        fracDigits =
            intDigits.substring(intDigits.length - shift) + fracDigits;
        intDigits = intDigits.substring(0, intDigits.length - shift);
      } else {
        fracDigits =
            '0' * (shift - intDigits.length) + intDigits + fracDigits;
        intDigits = '0';
      }
    }

    // Exact half-up on the first dropped decimal digit.
    final kept = intDigits +
        (fracDigits.length > decimals
            ? fracDigits.substring(0, decimals)
            : fracDigits.padRight(decimals, '0'));
    final rest = fracDigits.length > decimals
        ? fracDigits.substring(decimals)
        : '';
    final roundedUp = rest.isNotEmpty && rest.codeUnitAt(0) >= 0x35; // '5'

    var digits = roundedUp ? _incrementDecimal(kept) : kept;
    if (digits.isEmpty) digits = '0';

    if (decimals == 0) return double.parse(digits);
    if (digits.length <= decimals) {
      digits = digits.padLeft(decimals + 1, '0');
    }
    final cut = digits.length - decimals;
    return double.parse('${digits.substring(0, cut)}.${digits.substring(cut)}');
  }

  /// Adds one to a plain decimal digit string, carrying: '199' → '200',
  /// '999' → '1000'. Only used on already-normalised digit runs.
  static String _incrementDecimal(String digits) {
    final chars = digits.split('');
    var i = chars.length - 1;
    while (i >= 0) {
      if (chars[i] == '9') {
        chars[i] = '0';
        i--;
      } else {
        chars[i] = String.fromCharCode(chars[i].codeUnitAt(0) + 1);
        return chars.join();
      }
    }
    return '1${chars.join()}';
  }

  /// Converts [amount] from [from] to [to].
  ///
  /// Same-unit conversions ([from] == [to]) need NO rate: a direct USDC
  /// entry is already the USDC wire amount and must not be blocked because
  /// the optional GHS equivalent cannot be displayed (PR #165 review §1).
  /// The amount is still normalised to the unit's wire precision and
  /// still fails closed when it rounds to zero.
  ///
  /// Cross-unit conversions require a validated rate and return the EXACT
  /// reviewed number (already rounded to the destination unit's minor
  /// digits), or null when the conversion cannot be established safely
  /// (unusable rate, non-finite amount, or a result that rounds to zero).
  static double? convert({
    required double amount,
    required AzCurrency from,
    required AzCurrency to,
    required double ghsPerUsdc,
  }) {
    if (!amount.isFinite || amount <= 0) return null;

    if (from.code == to.code) {
      final normalized = roundTo(amount, to.wireDecimals);
      return normalized > 0 ? normalized : null;
    }

    if (!isUsableRate(ghsPerUsdc)) return null;

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
