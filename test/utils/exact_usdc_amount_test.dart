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
    test('an 8dp balance is recovered EXACTLY from its double text', () {
      // This is the UX-critical case: a member typing their full balance must
      // not be told it exceeds the balance.
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

    test('the ceiling never exceeds the balance it came from', () {
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
}
