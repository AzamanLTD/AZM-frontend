// =============================================================================
// AZAMAN — EXACT USDC AMOUNT (client half of §r42.2)
//
// The customer's decimal text is the money. This parser turns it into an
// exact fixed-point value and NOTHING else in the flow is allowed to turn it
// back into a binary float.
//
// WHY: the vendor internal-transfer used to parse the field with
// `double.tryParse`, validate that double, and put that double in the JSON
// body. Two defects followed:
//   • a 9-dp entry was accepted by the client and then rounded by the server's
//     NUMERIC(20,8) column AFTER it had already been compared as a double;
//   • the confirmed amount was re-formatted with `toStringAsFixed(2)`, so a
//     member who entered 0.12345678 saw "0.12" and a request for less money
//     than they asked to move.
//
// CONTRACT MIRRORED FROM THE SERVER (AZM-backend PR #399, toExactUsdcAmount):
//   • a DECIMAL STRING is authoritative and parsed exactly;
//   • the amount must be > 0;
//   • at most 8 decimal places — a sub-8dp figure is REFUSED, never rounded;
//   • strictly below 1,000,000,000,000 USDC (Decimal(20,8) holds 12 integer
//     digits, so the 13-digit bound is a deterministic refusal rather than a
//     database error mid-transaction).
//
// Deliberately STRICTER than the server in two places, because the client can
// afford to be and a refusal here is always safe:
//   • exponent notation ("1e-7") is refused outright. decimal.js would accept
//     it; a customer typing money should never send it.
//   • whitespace inside the figure is refused.
//
// This file adds no dependency: the arithmetic is BigInt base units at 1e-8.
// =============================================================================

import 'package:flutter/foundation.dart' show immutable;

/// Why an entered amount was refused. Every reason has customer-facing copy —
/// a member must never have to guess which precision was rejected.
enum UsdcAmountRefusal {
  /// Nothing entered (or only whitespace).
  empty,

  /// Not an ordinary decimal figure (letters, signs, repeated points).
  malformed,

  /// Exponent notation ("1e-7") — never a money amount a customer types.
  exponentNotation,

  /// More than 8 decimal places. REFUSED, never truncated.
  tooManyDecimals,

  /// Zero or negative.
  notPositive,

  /// At or beyond the wallet's representable maximum.
  outOfRange,
}

/// The outcome of parsing one entry: either an exact [value] or a [refusal].
@immutable
class ExactUsdcParse {
  final ExactUsdcAmount? value;
  final UsdcAmountRefusal? refusal;

  const ExactUsdcParse._(this.value, this.refusal);

  factory ExactUsdcParse.valid(ExactUsdcAmount value) =>
      ExactUsdcParse._(value, null);

  factory ExactUsdcParse.refused(UsdcAmountRefusal refusal) =>
      ExactUsdcParse._(null, refusal);

  bool get isValid => value != null;

  /// Customer-facing explanation of the refusal. Empty input keeps the
  /// screen's established "Enter amount to continue" voice.
  String get message => switch (refusal) {
    UsdcAmountRefusal.empty => 'Enter amount to continue',
    UsdcAmountRefusal.malformed => 'Use digits only, e.g. 12.34',
    UsdcAmountRefusal.exponentNotation => 'Enter a plain amount, e.g. 12.34',
    UsdcAmountRefusal.tooManyDecimals => 'USDC takes at most 8 decimal places',
    UsdcAmountRefusal.notPositive => 'Enter an amount greater than zero',
    UsdcAmountRefusal.outOfRange => 'Amount is larger than this wallet allows',
    null => '',
  };
}

/// An exact USDC amount: the customer's decimal text plus its fixed-point
/// value in 1e-8 base units. Immutable and exact — no double is ever created.
@immutable
class ExactUsdcAmount {
  /// USDC minor-unit scale. The backend column is NUMERIC(20,8).
  static const int scale = 8;

  /// One whole USDC, in base units.
  static final BigInt unitsPerUsdc = BigInt.from(100000000);

  /// The wire maximum, EXCLUSIVE: 1,000,000,000,000 USDC.
  static final BigInt maxExclusiveUnits =
      BigInt.from(1000000000000) * unitsPerUsdc;

  /// The canonical decimal text — exactly what the customer entered, minus
  /// cosmetic noise (surrounding spaces, leading zeros). This is the string
  /// that goes on the wire and into the success message.
  final String text;

  /// The same value in exact 1e-8 base units.
  final BigInt baseUnits;

  const ExactUsdcAmount._(this.text, this.baseUnits);

  /// The authoritative wire value. A STRING, never a JSON number.
  String get wireAmount => text;

  int compareTo(ExactUsdcAmount other) => baseUnits.compareTo(other.baseUnits);

  bool operator >(ExactUsdcAmount other) => baseUnits > other.baseUnits;

  bool operator >=(ExactUsdcAmount other) => baseUnits >= other.baseUnits;

  bool operator <(ExactUsdcAmount other) => baseUnits < other.baseUnits;

  bool operator <=(ExactUsdcAmount other) => baseUnits <= other.baseUnits;

  @override
  bool operator ==(Object other) =>
      other is ExactUsdcAmount && other.baseUnits == baseUnits;

  @override
  int get hashCode => baseUnits.hashCode;

  @override
  String toString() => 'ExactUsdcAmount($text, units=$baseUnits)';

  /// Parses customer entry into an exact amount, or a precise refusal.
  ///
  /// Digit handling is pure text + BigInt: `0.12345678` never becomes a
  /// double, so it cannot come back as anything but `0.12345678`.
  static ExactUsdcParse parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.empty);
    }
    // An empty string is the only forgiving case. Whitespace around the
    // figure is trimmed; whitespace INSIDE it is not a decimal representation.
    if (RegExp(r'\s').hasMatch(trimmed)) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.malformed);
    }
    if (trimmed.contains('e') || trimmed.contains('E')) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.exponentNotation);
    }
    if (trimmed.startsWith('-')) {
      // Refused as non-positive, whatever the magnitude: a negative transfer
      // is not "malformed text", it is the wrong direction of money.
      return ExactUsdcParse.refused(UsdcAmountRefusal.notPositive);
    }
    if (trimmed.startsWith('+')) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.malformed);
    }

    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(trimmed);
    if (match == null) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.malformed);
    }
    final intPart = match.group(1) ?? '';
    final fracPart = match.group(2) ?? '';
    if (intPart.isEmpty && fracPart.isEmpty) {
      // A bare "." — no digits at all.
      return ExactUsdcParse.refused(UsdcAmountRefusal.malformed);
    }
    if (fracPart.length > scale) {
      // Never truncate: 0.123456789 is refused, not quietly 0.12345678.
      return ExactUsdcParse.refused(UsdcAmountRefusal.tooManyDecimals);
    }

    final digits =
        (intPart.isEmpty ? '0' : intPart) + fracPart.padRight(scale, '0');
    final units = BigInt.parse(digits);
    if (units == BigInt.zero) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.notPositive);
    }
    if (units >= maxExclusiveUnits) {
      return ExactUsdcParse.refused(UsdcAmountRefusal.outOfRange);
    }

    final normalisedInt = intPart.isEmpty ? '0' : _stripLeadingZeros(intPart);
    final text = fracPart.isEmpty ? normalisedInt : '$normalisedInt.$fracPart';
    return ExactUsdcParse.valid(ExactUsdcAmount._(text, units));
  }

  /// Convenience for callers that only care whether the entry is usable.
  static ExactUsdcAmount? tryParse(String raw) => parse(raw).value;

  /// Renders base units back to exact decimal text (trailing fractional zeros
  /// removed). Used by the quick-amount shortcuts, which are computed in base
  /// units so they can never exceed the balance they were derived from.
  static String formatUnits(BigInt units) {
    if (units.isNegative) {
      throw ArgumentError.value(
        units,
        'units',
        'a USDC amount cannot be negative',
      );
    }
    final whole = units ~/ unitsPerUsdc;
    final frac = (units % unitsPerUsdc).toString().padLeft(scale, '0');
    final trimmedFrac = frac.replaceFirst(RegExp(r'0+$'), '');
    return trimmedFrac.isEmpty ? '$whole' : '$whole.$trimmedFrac';
  }

  static String _stripLeadingZeros(String digits) {
    final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }

  /// The ceiling the amount field offers for a PRESENTATION balance.
  ///
  /// The backend serialises its Decimal(20,8) columns as JSON *numbers*
  /// (`Decimal.prototype.toJSON` returns `Number(...)`), so the exact string is
  /// already gone by the time the client sees the balance. What survives is the
  /// double, whose shortest round-trip text is the decimal the server
  /// projected. So:
  ///
  ///   • when that text is already a plain <=8-dp decimal, its EXACT value is
  ///     the ceiling — a member typing their full balance is accepted, and the
  ///     100% shortcut lands on the balance rather than a unit below it;
  ///   • otherwise (exponent form, or more than 8 decimal places) fall back to
  ///     the conservative floor, which can sit at most 1e-8 below the balance
  ///     and therefore never overshoots.
  ///
  /// This is an input LIMIT, never an authorisation: the server's transactional
  /// balance check remains the authority on whether the funds exist.
  static BigInt ceilingUnitsFromPresentation(num balance) {
    if (!balance.isFinite || balance <= 0) return BigInt.zero;
    final direct = parse(balance.toString());
    if (direct.isValid) return direct.value!.baseUnits;
    return floorUnitsFromPresentation(balance);
  }

  /// Converts a PRESENTATION balance (a JSON number the backend serialised as
  /// a double — see the backend's `Decimal.prototype.toJSON`) into a
  /// floor-rounded base-unit ceiling.
  ///
  /// This is a LIMIT for the input field, never an authorisation: the server's
  /// transactional balance check stays authoritative. Two guarantees:
  ///   • it never exceeds the balance it was derived from (floor, so at worst
  ///     one 1e-8 unit low — a shortcut can never overshoot);
  ///   • it makes no claim of exactness. The exact decimal string was already
  ///     lost when the backend serialised the Decimal as a JSON number, so the
  ///     only honest reconstruction is a conservative ceiling.
  static BigInt floorUnitsFromPresentation(num balance) {
    if (!balance.isFinite || balance <= 0) return BigInt.zero;
    final scaled = balance * 100000000;
    // Above ~9e15 the double no longer carries 8-dp fidelity and `floor()`
    // would be inventing digits. Cap at the wire maximum instead.
    if (scaled >= 9.0e15) return maxExclusiveUnits - BigInt.one;
    return BigInt.from(scaled.floor());
  }
}
