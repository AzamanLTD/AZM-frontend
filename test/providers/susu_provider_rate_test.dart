import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/providers/susu_provider.dart';

void main() {
  group('parseSusuSuppliedRate', () {
    test('accepts canonical USDC/GHS retail snapshot', () {
      final rate = parseSusuSuppliedRate({
        'pair': 'USDC/GHS',
        'settlementCurrency': 'USDC',
        'displayCurrency': 'GHS',
        'liveRetailRate': 12.45,
        'rateSource': 'KOTANI_PAY',
      });
      expect(rate.usdcToGhs, 12.45);
      expect(rate.source, 'KOTANI_PAY');
    });

    test('rejects legacy headline rate', () {
      final rate = parseSusuSuppliedRate({
        'liveUsdToGhs': 12.50,
        'rateSource': 'ER_API',
      });
      expect(rate.usdcToGhs, 0);
      expect(rate.source, 'UNAVAILABLE');
    });

    test('never falls back when canonical retail is invalid', () {
      final rate = parseSusuSuppliedRate({
        'pair': 'USDC/GHS',
        'settlementCurrency': 'USDC',
        'displayCurrency': 'GHS',
        'liveRetailRate': 0,
        'liveUsdToGhs': 12.50,
      });
      expect(rate.usdcToGhs, 0);
    });

    test('rejects the wrong canonical pair', () {
      final rate = parseSusuSuppliedRate({
        'pair': 'USD/GHS',
        'settlementCurrency': 'USD',
        'displayCurrency': 'GHS',
        'liveRetailRate': 12.45,
      });
      expect(rate.usdcToGhs, 0);
    });
  });
}
