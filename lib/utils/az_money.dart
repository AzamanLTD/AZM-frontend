// =============================================================================
// AZAMAN — MONEY FORMATTING
//
// ONE formatter for every currency string in the app.
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// The app had THREE independent hand-rolled thousands-separator helpers:
//   fmtGhs()                in hologram_balance_card.dart
//   _BalanceLine._fmt()     in flippable_balance_card.dart
//   _BalanceNumber._format() in hologram_balance_card.dart  (dead code)
// Three implementations means three chances to disagree, and they did: the cedi
// symbol appeared as both "GH₵" and "GHC" in different screens.
//
// ── CONVENTIONS (do not deviate) ─────────────────────────────────────────────
//   Cedis    : "GH₵ 1,240.42"   — symbol, SPACE, grouped amount
//   Dollars  : "1,240.42 USDC"  — grouped amount, SPACE, ticker (suffix)
//   Compact  : "1.24M" / "2.40B" — ONLY for millions and above
//   Delta    : "+GH₵ 0.42" / "−GH₵ 0.42"  (U+2212 MINUS, not a hyphen)
//   Rate     : "1.0842"          (4 decimals by default)
//
// ── DELIBERATE NON-BEHAVIOURS ────────────────────────────────────────────────
// • `compact()` does NOT abbreviate thousands. "1,240.42" stays "1,240.42" — it
//   does not become "1.2K". Abbreviating a *balance* loses precision the user
//   needs; the existing code already only abbreviated at 1e6+, and that
//   threshold is preserved exactly.
// • `delta()` uses U+2212 MINUS SIGN rather than an ASCII hyphen. A hyphen is
//   a text character; a minus is a mathematical operator and is optically
//   aligned with digits. This is the kind of detail that separates a designed
//   interface from an assembled one.
// • `amount()` uses an ASCII hyphen for negatives so that downstream parsers and
//   tests are not surprised. Only `delta()` uses U+2212.
//
// ── TABULAR FIGURES ──────────────────────────────────────────────────────────
// This file formats STRINGS only; it does not style them. Every caller must
// render the result with a tabular-figure style (`AzText.money(...)` sets
// `FontFeature.tabularFigures()`), or a counting balance will jitter
// horizontally as digits change width.
// =============================================================================

/// Currency formatting. Pure functions, no state, no Flutter dependency.
abstract final class AzMoney {
  /// The Ghanaian cedi. Uses the proper cedi glyph — NOT "GHC", NOT "GHS".
  static const String ghsSymbol = 'GH₵';

  /// USD Coin ticker. Rendered as a suffix: "1,240.42 USDC".
  static const String usdcSymbol = 'USDC';

  /// U+2212 MINUS SIGN. Optically aligned with digits, unlike a hyphen.
  static const String minusSign = '\u2212';

  /// U+00A0 NO-BREAK SPACE. Used between a symbol and its amount so the two can
  /// never be separated by a line break.
  static const String nbsp = '\u00A0';

  // ── CORE ───────────────────────────────────────────────────────────────

  /// Grouped amount with no currency symbol. `1240.4` → `"1,240.40"`.
  ///
  /// Negatives keep an ASCII hyphen: `-1240.4` → `"-1,240.40"`.
  static String amount(double value, {int decimals = 2}) {
    final safe = value.isFinite ? value : 0.0;
    final negative = safe < 0;
    final text = safe.abs().toStringAsFixed(decimals);

    final dot = text.indexOf('.');
    final intPart = dot == -1 ? text : text.substring(0, dot);
    final fracPart = dot == -1 ? '' : text.substring(dot);

    final grouped = _group(intPart);
    return '${negative ? '-' : ''}$grouped$fracPart';
  }

  /// Abbreviated amount for headline figures. Only abbreviates at ≥ 1e6:
  /// `1240.42` → `"1,240.42"`, `1240000` → `"1.24M"`, `2400000000` → `"2.40B"`.
  ///
  /// The 1e6 threshold deliberately matches the behaviour of the formatter this
  /// replaces, so no existing figure changes value.
  static String compact(double value, {int decimals = 2}) {
    final safe = value.isFinite ? value : 0.0;
    final abs = safe.abs();
    final negative = safe < 0;
    final sign = negative ? '-' : '';

    if (abs >= 1000000000) {
      return '$sign${(abs / 1000000000).toStringAsFixed(decimals)}B';
    }
    if (abs >= 1000000) {
      return '$sign${(abs / 1000000).toStringAsFixed(decimals)}M';
    }
    return amount(safe, decimals: decimals);
  }

  // ── CURRENCY-QUALIFIED ─────────────────────────────────────────────────

  /// `"GH₵ 1,240.42"`. [compact] switches to `"GH₵ 1.24M"` for ≥ 1e6.
  static String ghs(double value, {bool compact = false, int decimals = 2}) {
    final body = compact
        ? AzMoney.compact(value, decimals: decimals)
        : amount(value, decimals: decimals);
    return '$ghsSymbol$nbsp$body';
  }

  /// `"1,240.42 USDC"`. [compact] switches to `"1.24M USDC"` for ≥ 1e6.
  static String usdc(double value, {bool compact = false, int decimals = 2}) {
    final body = compact
        ? AzMoney.compact(value, decimals: decimals)
        : amount(value, decimals: decimals);
    return '$body$nbsp$usdcSymbol';
  }

  // ── CHANGE ─────────────────────────────────────────────────────────────

  /// A signed change chip: `"+GH₵ 0.42"`, `"−GH₵ 0.42"`, or `""` for zero.
  ///
  /// Returns an EMPTY STRING when [value] rounds to zero and [showZero] is false,
  /// so callers can render the result unconditionally and simply get nothing —
  /// that is what makes the delta chip safe to place in a layout without an
  /// `if` at every call site.
  ///
  /// Uses U+2212 MINUS for negatives.
  static String delta(
    double value, {
    String symbol = ghsSymbol,
    int decimals = 2,
    bool showZero = false,
  }) {
    final safe = value.isFinite ? value : 0.0;
    final rounded = double.parse(safe.toStringAsFixed(decimals));
    if (rounded == 0 && !showZero) return '';
    final sign = rounded < 0 ? minusSign : '+';
    return '$sign$symbol$nbsp${amount(rounded.abs(), decimals: decimals)}';
  }

  /// An exchange rate: `"1.0842"`. Rates need more precision than money, so the
  /// default is 4 decimals.
  static String rate(double value, {int decimals = 4}) =>
      amount(value, decimals: decimals);

  /// A rate change as a percentage: `"+1.24%"` / `"−0.80%"`.
  static String rateDelta(double value, {int decimals = 2}) {
    final safe = value.isFinite ? value : 0.0;
    final rounded = double.parse(safe.toStringAsFixed(decimals));
    if (rounded == 0) return '';
    final sign = rounded < 0 ? minusSign : '+';
    return '$sign${rounded.abs().toStringAsFixed(decimals)}%';
  }

  // ── INTERNALS ──────────────────────────────────────────────────────────

  /// Inserts a comma every three digits from the right.
  /// `"1240"` → `"1,240"`, `"124"` → `"124"`, `"1234567"` → `"1,234,567"`.
  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    final length = digits.length;
    for (var i = 0; i < length; i++) {
      // Insert a separator when the number of digits still to come is a
      // multiple of three — i.e. before positions 3, 6, 9 from the right.
      if (i > 0 && (length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
