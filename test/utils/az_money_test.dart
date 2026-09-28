import 'package:azaman/utils/az_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AzMoney.amount', () {
    test('groups thousands and keeps two decimals', () {
      expect(AzMoney.amount(1240.4), '1,240.40');
      expect(AzMoney.amount(1240), '1,240.00');
      expect(AzMoney.amount(0), '0.00');
    });

    test('groups millions and billions', () {
      expect(AzMoney.amount(1234567.891), '1,234,567.89');
      expect(AzMoney.amount(1234567891.2), '1,234,567,891.20');
    });

    test('uses an ASCII hyphen for negatives', () {
      expect(AzMoney.amount(-1240.5), '-1,240.50');
      expect(AzMoney.amount(-0.5), '-0.50');
    });

    test('respects the decimals argument', () {
      expect(AzMoney.amount(1240.4567, decimals: 0), '1,240');
      expect(AzMoney.amount(1240.4567, decimals: 4), '1,240.4567');
    });

    test('collapses non-finite input to zero', () {
      expect(AzMoney.amount(double.nan), '0.00');
      expect(AzMoney.amount(double.infinity), '0.00');
    });
  });

  group('AzMoney.compact', () {
    test('does not abbreviate below one million', () {
      expect(AzMoney.compact(1240.42), '1,240.42');
      expect(AzMoney.compact(999999.99), '999,999.99');
    });

    test('abbreviates millions and billions', () {
      expect(AzMoney.compact(1240000), '1.24M');
      expect(AzMoney.compact(2400000000), '2.40B');
    });

    test('preserves sign and the ASCII hyphen', () {
      expect(AzMoney.compact(-1240000), '-1.24M');
    });
  });

  group('AzMoney.ghs', () {
    test('renders symbol, non-breaking space and grouped amount', () {
      expect(AzMoney.ghs(1240.42), 'GH₵\u00A01,240.42');
    });

    test('compacts only when asked', () {
      expect(AzMoney.ghs(1240000, compact: true), 'GH₵\u00A01.24M');
      expect(AzMoney.ghs(1240000), 'GH₵\u00A01,240,000.00');
    });
  });

  group('AzMoney.usdc', () {
    test('renders the ticker as a suffix', () {
      expect(AzMoney.usdc(1240.42), '1,240.42\u00A0USDC');
      expect(AzMoney.usdc(1240000, compact: true), '1.24M\u00A0USDC');
    });
  });

  group('AzMoney.delta', () {
    test('uses plus for gains and U+2212 for losses', () {
      expect(AzMoney.delta(0.42), '+GH₵\u00A00.42');
      expect(AzMoney.delta(-0.42), '\u2212GH₵\u00A00.42');
    });

    test('returns an empty string for a zero change by default', () {
      expect(AzMoney.delta(0), '');
      expect(AzMoney.delta(0.001), '');
    });

    test('renders a signed zero when showZero is set', () {
      expect(AzMoney.delta(0, showZero: true), '+GH₵\u00A00.00');
    });

    test('accepts a custom symbol', () {
      expect(AzMoney.delta(1, symbol: AzMoney.usdcSymbol), '+USDC\u00A01.00');
    });
  });

  group('AzMoney.rate', () {
    test('defaults to four decimals', () {
      expect(AzMoney.rate(1.0842), '1.0842');
    });

    test('groups whole numbers beyond the decimal point', () {
      expect(AzMoney.rate(1234.5), '1,234.5000');
    });
  });

  group('AzMoney.rateDelta', () {
    test('renders a signed percentage', () {
      expect(AzMoney.rateDelta(1.234), '+1.23%');
      expect(AzMoney.rateDelta(-0.8), '\u22120.80%');
    });

    test('returns an empty string for zero', () {
      expect(AzMoney.rateDelta(0), '');
    });
  });
}
