// =============================================================================
// AZAMAN — AMOUNT INPUT STATE MACHINE
//
// The Add Cash keypad cannot type an invalid cedi amount into being — because
// every rule lives HERE, in a pure function, applied before any state exists.
//
//   • at most ONE decimal point
//   • at most TWO fractional digits        (pesewas are the smallest unit)
//   • no leading-zero buildup              ('0' + '5' → '5', never '05')
//   • no negative values                   (no sign key exists to press)
//   • at most 7 integer digits             (GH₵ 9,999,999.99 — far above
//                                          every product cap)
//
// The function is pure: same input, same key, same output. The deposit screen
// feeds it its raw string; the tests exercise it without pumping any widget.
// =============================================================================

import 'package:azaman/utils/az_money.dart';

abstract final class AmountInput {
  const AmountInput._();

  /// Apply one keypad key to [raw] and return the new raw string.
  ///
  /// [key] is `'0'`..`'9'`, `'.'` (decimal point) or `'del'` (backspace).
  /// Keys that would produce an invalid amount are no-ops — they return
  /// [raw] unchanged, so no intermediate illegal state can ever be observed.
  static String applyKey(String raw, String key) {
    if (key == 'del') {
      if (raw.isEmpty) return raw;
      return raw.substring(0, raw.length - 1);
    }
    if (key == '.') {
      if (raw.contains('.')) return raw; // one decimal point only
      return '${raw.isEmpty ? '0' : raw}.';
    }
    // digit
    if (key.length != 1 ||
        key.codeUnitAt(0) < 0x30 ||
        key.codeUnitAt(0) > 0x39) {
      return raw; // not a digit key — no-op
    }
    final dot = raw.indexOf('.');
    if (dot != -1) {
      final frac = raw.substring(dot + 1);
      if (frac.length >= 2) return raw; // two fractional digits max
      return raw + key;
    }
    if (raw.length >= 7) return raw; // integer cap
    if (raw == '0') return key; // leading zero replaced, never "05"
    return raw + key;
  }

  /// The numeric value the user has entered, or null when there is no
  /// meaningful amount (empty, or zero).
  static double? value(String raw) {
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    return (v != null && v > 0) ? v : null;
  }

  /// The display string: grouped integer part, fraction exactly as typed.
  /// Empty input displays as `'0'` — a resting instrument reads zero, it does
  /// not read blank.
  static String display(String raw) {
    if (raw.isEmpty) return '0';
    final dot = raw.indexOf('.');
    if (dot == -1) {
      // Pure integer — group it, no decimal point.
      return AzMoney.amount(double.parse(raw), decimals: 0);
    }
    // Preserve the fraction EXACTLY as typed — including a bare trailing
    // point ("12." renders "12.", not "12.0" or "12"): the display tells
    // the truth about what the user entered.
    final intPart = raw.substring(0, dot);
    final frac = raw.substring(dot + 1);
    final grouped = AzMoney.amount(
      double.parse(intPart.isEmpty ? '0' : intPart),
      decimals: 0,
    );
    return frac.isEmpty ? '$grouped.' : '$grouped.$frac';
  }
}
