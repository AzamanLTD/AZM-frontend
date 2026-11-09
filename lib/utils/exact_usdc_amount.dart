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
  /// How far a reconstructed balance can sit from the DATABASE decimal, in
  /// 1e-8 base units.
  ///
  /// The stored value D and the double's shortest round-trip text T each sit
  /// within half an ulp of the SAME double, so |T - D| <= ulp, and for normal
  /// magnitudes ulp <= |x| * 2^-52. Doubling that, then adding two units for
  /// the integer floor and sub-denormal fuzz, gives a bound that is generous by
  /// construction — it is a safety margin, not a measurement.
  static BigInt presentationErrorBoundUnits(num balance) {
    if (!balance.isFinite || balance <= 0) return BigInt.zero;
    final magnitudeUnits = balance * 100000000;
    final relative = (magnitudeUnits * 4.440892098500626e-16).ceil();
    return BigInt.from(relative + 2);
  }

  /// The two directional answers an amount field needs from a lossy balance,
  /// each with the bound that makes it safe.
  static PresentationBalanceLimit limitFromPresentationBalance(num balance) {
    final reconstructed = ceilingUnitsFromPresentation(balance);
    final bound = presentationErrorBoundUnits(balance);
    final ceiling = maxExclusiveUnits - BigInt.one;

    var accept = reconstructed + bound;
    if (accept > ceiling) accept = ceiling;

    var hundred = reconstructed - bound;
    if (hundred < BigInt.zero) hundred = BigInt.zero;
    // A positive balance always has at least one unit; never offer "100%" as
    // zero while the member holds something.
    if (reconstructed > BigInt.zero && hundred == BigInt.zero) {
      hundred = BigInt.one;
    }

    return PresentationBalanceLimit(
      reconstructedUnits: reconstructed,
      errorBoundUnits: bound,
      acceptUpToUnits: accept,
      hundredPercentUnits: hundred,
    );
  }

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
  ///   • when that text is a plain decimal, its value is the best
  ///     reconstruction available;
  ///   • otherwise (exponent form, or more than 8 decimal places) fall back to
  ///     the floor of the double's scaled value.
  ///
  /// NEITHER branch is exact. The text is the shortest decimal that round-trips
  /// to the same double, and the double is itself the nearest double to the
  /// database decimal, so the reconstruction can sit ABOVE or BELOW the real
  /// balance by up to [presentationErrorBoundUnits] — measured at up to 445
  /// units (0.00000445 USDC) above and 210 below around 1e11 USDC. Use
  /// [limitFromPresentationBalance] for the two questions that need a
  /// direction (what the field may accept, what 100% may submit).
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
  ///   • it never exceeds the VALUE OF THE DOUBLE it was given (a floor, so at
  ///     worst one 1e-8 unit low);
  ///   • it makes no claim about the DATABASE decimal. That double is itself
  ///     only the nearest double to the stored value, so flooring it bounds the
  ///     double, not the balance — see [presentationErrorBoundUnits].
  static BigInt floorUnitsFromPresentation(num balance) {
    if (!balance.isFinite || balance <= 0) return BigInt.zero;
    final scaled = balance * 100000000;
    // Above ~9e15 the double no longer carries 8-dp fidelity and `floor()`
    // would be inventing digits. Cap at the wire maximum instead.
    if (scaled >= 9.0e15) return maxExclusiveUnits - BigInt.one;
    return BigInt.from(scaled.floor());
  }
}

/// A lossy numeric balance turned into the two limits an amount field needs.
///
/// Kept as a value type so the DIRECTION of each decision is explicit: the
/// field accepts up to the upper bound (never refusing what the server would
/// accept), while a 100% shortcut submits at most the lower bound (never asking
/// the server for more than the member holds).
@immutable
class PresentationBalanceLimit {
  const PresentationBalanceLimit({
    required this.reconstructedUnits,
    required this.errorBoundUnits,
    required this.acceptUpToUnits,
    required this.hundredPercentUnits,
  });

  /// Best reconstruction of the balance, in 1e-8 units. A presentation hint.
  final BigInt reconstructedUnits;

  /// The maximum plausible gap between [reconstructedUnits] and the database
  /// decimal, in 1e-8 units.
  final BigInt errorBoundUnits;

  /// The largest amount the input field may accept. Never below the database
  /// balance, so a member typing their whole balance is never refused.
  final BigInt acceptUpToUnits;

  /// The largest amount a 100% shortcut may submit. Never above the database
  /// balance, so the server never refuses it as insufficient.
  final BigInt hundredPercentUnits;
}
