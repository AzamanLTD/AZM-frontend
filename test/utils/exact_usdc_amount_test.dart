// =============================================================================
// EXACT USDC AMOUNT — §r42.2 client parser
//
// The point of these tests is the MONEY, not the parser's elegance: what the
// customer typed must be what is validated, confirmed and submitted, with no
// binary floating point anywhere on the path.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/utils/exact_usdc_amount.dart';

/// 1 USDC in base units.
const unit = 100000000;

void main() {
  group('accepted representations', () {
    test('0.1 parses exactly', () {
      final r = ExactUsdcAmount.parse('0.1');
      expect(r.isValid, isTrue);
      expect(r.value!.text, '0.1');
      expect(r.value!.baseUnits, BigInt.from(10000000));
    });

    test('1.00000001 — full 8dp precision survives', () {
      final r = ExactUsdcAmount.parse('1.00000001');
      expect(r.value!.text, '1.00000001');
      expect(r.value!.baseUnits, BigInt.from(100000001));
    });

    test('0.12345678 is preserved digit for digit', () {
      final r = ExactUsdcAmount.parse('0.12345678');
      expect(r.value!.text, '0.12345678');
      expect(r.value!.baseUnits, BigInt.from(12345678));
    });

    test('999999999999 (12 integer digits) is inside the supported range', () {
      final r = ExactUsdcAmount.parse('999999999999');
      expect(r.isValid, isTrue);
      expect(r.value!.baseUnits, BigInt.from(999999999999) * BigInt.from(unit));
    });

    test('the largest representable value is accepted', () {
      final r = ExactUsdcAmount.parse('999999999999.99999999');
      expect(r.isValid, isTrue);
      expect(
        r.value!.baseUnits,
        BigInt.from(999999999999) * BigInt.from(unit) + BigInt.from(99999999),
      );
    });

    test('seven and eight decimal places are accepted', () {
      expect(ExactUsdcAmount.parse('1.1234567').isValid, isTrue);
      expect(ExactUsdcAmount.parse('1.12345678').isValid, isTrue);
    });

    test('surrounding whitespace is tolerated', () {
      final r = ExactUsdcAmount.parse('  0.5  ');
      expect(r.isValid, isTrue);
      expect(r.value!.text, '0.5');
    });
  });

  group('canonicalisation never changes the economic value', () {
    test('leading zeros are stripped', () {
      expect(ExactUsdcAmount.parse('000.500').value!.text, '0.500');
      expect(
        ExactUsdcAmount.parse('000.500').value!.baseUnits,
        BigInt.from(50000000),
      );
    });

    test('a bare leading point gains its zero', () {
      expect(ExactUsdcAmount.parse('.5').value!.text, '0.5');
    });

    test('a trailing point is dropped', () {
      expect(ExactUsdcAmount.parse('5.').value!.text, '5');
    });

    test('0.10 and 0.1 are the SAME money', () {
      final a = ExactUsdcAmount.parse('0.10').value!;
      final b = ExactUsdcAmount.parse('0.1').value!;
      expect(a == b, isTrue);
      expect(a.compareTo(b), 0);
      // ...while each keeps the text the customer actually typed.
      expect(a.text, '0.10');
      expect(b.text, '0.1');
    });
  });

  group('refusals', () {
    void expectRefusal(String input, UsdcAmountRefusal refusal) {
      final r = ExactUsdcAmount.parse(input);
      expect(r.isValid, isFalse, reason: '"$input" must be refused');
      expect(r.refusal, refusal, reason: '"$input" refusal reason');
      expect(r.value, isNull);
    }

    test('empty input', () {
      expectRefusal('', UsdcAmountRefusal.empty);
      expectRefusal('   ', UsdcAmountRefusal.empty);
    });

    test('zero is not a transfer', () {
      expectRefusal('0', UsdcAmountRefusal.notPositive);
      expectRefusal('0.0', UsdcAmountRefusal.notPositive);
      expectRefusal('0.00000000', UsdcAmountRefusal.notPositive);
      expectRefusal('.0', UsdcAmountRefusal.notPositive);
    });

    test('negative input', () {
      expectRefusal('-1', UsdcAmountRefusal.notPositive);
      expectRefusal('-0.5', UsdcAmountRefusal.notPositive);
      expectRefusal('-0.00000001', UsdcAmountRefusal.notPositive);
    });

    test('nine decimal places are refused, never truncated', () {
      expectRefusal('0.123456789', UsdcAmountRefusal.tooManyDecimals);
      expectRefusal('1.000000001', UsdcAmountRefusal.tooManyDecimals);
      // The eight-dp prefix would have been a plausible silent truncation;
      // the parser must refuse instead. Prove the prefix differs.
      expect(ExactUsdcAmount.parse('0.12345678').value!.text, '0.12345678');
    });

    test('exponent notation', () {
      expectRefusal('1e-7', UsdcAmountRefusal.exponentNotation);
      expectRefusal('1E-7', UsdcAmountRefusal.exponentNotation);
      expectRefusal('2e3', UsdcAmountRefusal.exponentNotation);
    });

    test('whitespace inside the figure', () {
      expectRefusal('1 2', UsdcAmountRefusal.malformed);
      expectRefusal('1. 5', UsdcAmountRefusal.malformed);
    });

    test('invalid characters and shapes', () {
      expectRefusal('abc', UsdcAmountRefusal.malformed);
      expectRefusal('1,5', UsdcAmountRefusal.malformed);
      expectRefusal('1..2', UsdcAmountRefusal.malformed);
      expectRefusal('1.2.3', UsdcAmountRefusal.malformed);
      expectRefusal('.', UsdcAmountRefusal.malformed);
      expectRefusal('\$5', UsdcAmountRefusal.malformed);
      expectRefusal('+1', UsdcAmountRefusal.malformed);
      expectRefusal('NaN', UsdcAmountRefusal.malformed);
      expectRefusal('Infinity', UsdcAmountRefusal.malformed);
    });

    test('above the established range', () {
      // The backend refuses >= 1,000,000,000,000 (Decimal(20,8) holds 12
      // integer digits), so the client refuses it one step earlier in the UX.
      expectRefusal('1000000000000', UsdcAmountRefusal.outOfRange);
      expectRefusal('1000000000000.00000001', UsdcAmountRefusal.outOfRange);
      expectRefusal('9999999999999', UsdcAmountRefusal.outOfRange);
    });

    test('every refusal carries customer-facing copy', () {
      // One representative input per refusal, so the enum cannot grow a case
      // the member would meet as a blank explanation.
      const inputs = <String, UsdcAmountRefusal>{
        '': UsdcAmountRefusal.empty,
        'abc': UsdcAmountRefusal.malformed,
        '1e5': UsdcAmountRefusal.exponentNotation,
        '0.123456789': UsdcAmountRefusal.tooManyDecimals,
        '0': UsdcAmountRefusal.notPositive,
        '1000000000000': UsdcAmountRefusal.outOfRange,
      };
      expect(
        inputs.values.toSet(),
        UsdcAmountRefusal.values.toSet(),
        reason: 'every refusal must be exercised exactly once',
      );
      for (final entry in inputs.entries) {
        final parsed = ExactUsdcAmount.parse(entry.key);
        expect(parsed.refusal, entry.value, reason: entry.key);
        expect(parsed.message, isNotEmpty, reason: entry.key);
      }
      expect(ExactUsdcAmount.parse('').message, contains('Enter amount'));
      expect(
        ExactUsdcAmount.parse('1.123456789').message,
        contains('8 decimal places'),
      );
      expect(ExactUsdcAmount.parse('0').message, contains('greater than zero'));
    });
  });

  // ── §r42.4: the balance reaching the field is a JSON NUMBER, so the
  // reconstruction carries a bounded error in BOTH directions. These tests pin
  // the measured failures (dust: -1 unit; ~1e11 USDC: -210 and +445 units) and
  // the two directional guarantees that make the field safe anyway.
  group('presentation-balance limit (directional guarantees)', () {
    BigInt exactUnitsOf(String literal) =>
        ExactUsdcAmount.parse(literal).value!.baseUnits;

    PresentationBalanceLimit limitOf(String literal) =>
        ExactUsdcAmount.limitFromPresentationBalance(double.parse(literal));

    test('the reconstruction is NOT exact at large magnitudes', () {
      // 12 integer digits + 8 decimals = 20 significant digits; the double
      // cannot carry that, so the "exact" claim an earlier revision made is
      // false. The value is a hint, and this test says so out loud.
      const literal = '100000000999.76543210';
      final limit = limitOf(literal);
      expect(limit.reconstructedUnits, lessThan(exactUnitsOf(literal)));
      expect(
        limit.errorBoundUnits,
        greaterThan(exactUnitsOf(literal) - limit.reconstructedUnits),
        reason: 'the bound must cover the measured gap',
      );
    });

    test('a member typing their whole DUST balance is never refused', () {
      // 3e-8: the double takes the floor path and lands one unit low.
      const literal = '0.00000003';
      final limit = limitOf(literal);
      expect(limit.reconstructedUnits, lessThan(exactUnitsOf(literal)));
      expect(
        limit.acceptUpToUnits,
        greaterThanOrEqualTo(exactUnitsOf(literal)),
      );
    });

    test('the field never accepts less than the balance it represents', () {
      for (final literal in [
        '0.00000001',
        '0.00000003',
        '0.12345678',
        '9999999.12345678',
        '10000000.12345678',
        '123456789.12345678',
        '100000000999.55555555',
        '100000000999.76543210',
        '999999999999.99999999',
      ]) {
        expect(
          limitOf(literal).acceptUpToUnits,
          greaterThanOrEqualTo(exactUnitsOf(literal)),
          reason: literal,
        );
      }
    });

    test('100% can never submit more than the balance held', () {
      for (final literal in [
        '0.00000001',
        '0.00000003',
        '0.12345678',
        '1234.56789012',
        '10000000.12345678',
        '100000000999.55555555',
        '999999999999.99999999',
      ]) {
        final limit = limitOf(literal);
        expect(
          limit.hundredPercentUnits,
          lessThanOrEqualTo(exactUnitsOf(literal)),
          reason: literal,
        );
        expect(
          limit.hundredPercentUnits,
          greaterThan(BigInt.zero),
          reason: 'a positive balance must still offer something: $literal',
        );
      }
    });

    test('the bound grows with magnitude and is never zero', () {
      expect(
        ExactUsdcAmount.presentationErrorBoundUnits(0.00000003),
        greaterThan(BigInt.zero),
      );
      expect(
        ExactUsdcAmount.presentationErrorBoundUnits(1e11),
        greaterThan(ExactUsdcAmount.presentationErrorBoundUnits(1e3)),
      );
      expect(ExactUsdcAmount.presentationErrorBoundUnits(0), BigInt.zero);
      expect(ExactUsdcAmount.presentationErrorBoundUnits(-5), BigInt.zero);
    });

    test(
      'ordinary balances still reconstruct exactly (observed, not promised)',
      () {
        // Where the double's text round-trips to the same decimal the
        // reconstruction happens to be exact — true for every balance below
        // ~10 million USDC at 8dp. Asserted as observed behaviour, so a future
        // backend exact-string field is a strict improvement, not a fix.
        for (final literal in ['0.1', '0.12345678', '1234.56789012']) {
          expect(limitOf(literal).reconstructedUnits, exactUnitsOf(literal));
        }
      },
    );
  });

  group('base-unit rendering', () {
    test('formatUnits returns exact minimal decimal text', () {
      expect(ExactUsdcAmount.formatUnits(BigInt.from(10000000)), '0.1');
      expect(ExactUsdcAmount.formatUnits(BigInt.from(12345678)), '0.12345678');
      expect(ExactUsdcAmount.formatUnits(BigInt.from(unit)), '1');
      expect(ExactUsdcAmount.formatUnits(BigInt.from(1234000000)), '12.34');
      expect(
        ExactUsdcAmount.formatUnits(
          BigInt.from(999999999999) * BigInt.from(unit),
        ),
        '999999999999',
      );
    });

    test('formatUnits round-trips through the parser', () {
      for (final input in <String>[
        '0.1',
        '1.00000001',
        '0.12345678',
        '42.5',
        '999999999999.99999999',
      ]) {
        final v = ExactUsdcAmount.parse(input).value!;
        final roundTripped = ExactUsdcAmount.parse(
          ExactUsdcAmount.formatUnits(v.baseUnits),
        );
        expect(roundTripped.isValid, isTrue, reason: input);
        expect(roundTripped.value!.baseUnits, v.baseUnits, reason: input);
      }
    });
  });

  group('presentation-balance ceiling (input limit only)', () {
    test('an ordinary 8dp balance round-trips through its double text', () {
      // Observed, NOT promised: true for every balance whose decimal the
      // double's shortest text reproduces. §r42.4 documents where it stops
      // being true (>= ~10M USDC at 8dp) and wraps it in a bound.
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(0.12345678),
        BigInt.from(12345678),
      );
    });

    test('ordinary balances map to exact base units', () {
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(12.34),
        BigInt.from(1234000000),
      );
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(0.5),
        BigInt.from(50000000),
      );
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(100),
        BigInt.from(100) * BigInt.from(unit),
      );
    });

    // Renamed from "never exceeds the balance it came from": that claim is
    // FALSE in general (§r42.4, measured +445 units around 1e11 USDC). The
    // ceiling never exceeds the DOUBLE it was given; the double is not the
    // database decimal, which is why the directional limit exists.
    test('the ceiling never exceeds the double it came from', () {
      for (final balance in <double>[
        0.12345678,
        12.34,
        0.00000001,
        999.99999999,
        1234.5,
      ]) {
        final ceiling = ExactUsdcAmount.ceilingUnitsFromPresentation(balance);
        final ceilingValue = ceiling.toDouble() / unit;
        expect(
          ceilingValue,
          lessThanOrEqualTo(balance + 1e-9),
          reason: 'ceiling for $balance was $ceilingValue',
        );
      }
    });

    test(
      'exponent or over-precise text falls back to the conservative floor',
      () {
        // 1e-7 stringifies in exponent form; the floor branch keeps it safe and
        // still positive.
        final tiny = ExactUsdcAmount.ceilingUnitsFromPresentation(0.0000001);
        expect(tiny, greaterThanOrEqualTo(BigInt.zero));
        expect(tiny, lessThanOrEqualTo(BigInt.from(10)));
      },
    );

    test('zero and non-positive balances yield no ceiling', () {
      expect(ExactUsdcAmount.ceilingUnitsFromPresentation(0), BigInt.zero);
      expect(ExactUsdcAmount.ceilingUnitsFromPresentation(-5), BigInt.zero);
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(double.nan),
        BigInt.zero,
      );
      expect(
        ExactUsdcAmount.ceilingUnitsFromPresentation(double.infinity),
        BigInt.zero,
      );
    });
  });

  // ── §r42.5: the bound itself, and the shortcut guarantee. ──────────────
  group('presentation error bound', () {
    BigInt exactOf(String lit) => ExactUsdcAmount.parse(lit).value!.baseUnits;
    PresentationBalanceLimit limitOf(String lit) =>
        ExactUsdcAmount.limitFromPresentationBalance(double.parse(lit));

    test('the bound at the top of Decimal(20,8) is 44,411 units', () {
      // 0.00044411 USDC — the TRUE maximum uncertainty. An earlier report
      // claimed "below 0.000005", which was wrong by two orders of magnitude.
      expect(
        limitOf('999999999999.99999999').errorBoundUnits,
        BigInt.from(44411),
      );
      expect(limitOf('999999999999').errorBoundUnits, BigInt.from(44411));
    });

    test('the bound tracks magnitude and never drops below 3 units', () {
      expect(limitOf('0.00000003').errorBoundUnits, BigInt.from(3));
      expect(limitOf('1000000').errorBoundUnits, BigInt.from(3));
      expect(limitOf('100000000000').errorBoundUnits, BigInt.from(4443));
      // 2^39 and its neighbours: the exponent step must not undershoot.
      expect(limitOf('549755813888').errorBoundUnits, BigInt.from(24417));
    });

    test('the bound covers the measured reconstruction error everywhere', () {
      // Worst gap found by a 4000-sample sweep plus binade edges.
      const worst = <String, int>{
        '549755813888.12345678': 5678,
        '100000000999.55555555': 445,
        '100000000999.76543210': 210,
        '0.00000003': 1,
      };
      worst.forEach((lit, measured) {
        final lim = limitOf(lit);
        final error = (lim.reconstructedUnits - exactOf(lit)).abs();
        expect(error, BigInt.from(measured), reason: lit);
        expect(error, lessThanOrEqualTo(lim.errorBoundUnits), reason: lit);
        expect(
          lim.errorBoundUnits - error,
          greaterThan(BigInt.zero),
          reason: 'the bound must leave headroom at $lit',
        );
      });
    });
  });

  group('percentage shortcuts', () {
    BigInt exactOf(String lit) => ExactUsdcAmount.parse(lit).value!.baseUnits;
    PresentationBalanceLimit limitOf(String lit) =>
        ExactUsdcAmount.limitFromPresentationBalance(double.parse(lit));

    test('no shortcut can exceed the database balance', () {
      for (final lit in <String>[
        '0.00000001', '0.00000002', '0.00000003', '0.00000004',
        '0.00001234', '1.00000000', '1234.56789012',
        // reconstruction ABOVE the balance (+445) and BELOW it (-210)
        '100000000999.55555555', '100000000999.76543210',
        '999999999999.99999999',
      ]) {
        final exact = exactOf(lit);
        final lim = limitOf(lit);
        for (final pct in <int>[25, 50, 75, 100]) {
          final amount = lim.shortcutUnits(pct);
          expect(amount, lessThanOrEqualTo(exact), reason: '$pct% of $lit');
          expect(
            amount,
            greaterThanOrEqualTo(BigInt.zero),
            reason: '$pct% of $lit',
          );
        }
      }
    });

    test('a one-unit balance cannot be over-committed by 75%', () {
      // The case the old reconstruction-based formula could break: 75% of a
      // reconstruction sitting ABOVE a 1-unit balance.
      final lim = limitOf('0.00000001');
      expect(lim.shortcutUnits(25), BigInt.zero);
      expect(lim.shortcutUnits(50), BigInt.zero);
      expect(lim.shortcutUnits(75), BigInt.zero);
      expect(lim.shortcutUnits(100), BigInt.one);
    });

    test('every percentage derives from the lower bound, never the hint', () {
      final lim = limitOf('1234.56789012');
      for (final pct in <int>[25, 50, 75]) {
        expect(
          lim.shortcutUnits(pct),
          lim.hundredPercentUnits * BigInt.from(pct) ~/ BigInt.from(100),
          reason: '$pct%',
        );
      }
      expect(lim.shortcutUnits(100), lim.hundredPercentUnits);
      expect(lim.reconstructedUnits, greaterThan(lim.hundredPercentUnits));
    });

    test('nonsense percentages are refused rather than guessed', () {
      final lim = limitOf('1.00000000');
      expect(lim.shortcutUnits(0), BigInt.zero);
      expect(lim.shortcutUnits(-25), BigInt.zero);
    });
  });
}
