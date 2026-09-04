import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/currency_provider.dart';

void main() {
  group('parseFxRateSnapshot', () {
    test('uses liveRetailRate as the canonical USDC/GHS display rate', () {
      final snapshot = parseFxRateSnapshot({
        'pair': 'USDC/GHS',
        'settlementCurrency': 'USDC',
        'displayCurrency': 'GHS',
        'liveRetailRate': 13.42,
        'liveUsdToGhs': 13.10,
        'rateSource': 'KOTANI_PAY',
        'lastSync': '2026-09-04T11:30:00.000Z',
      });

      expect(snapshot.ghsPerUsdc, 13.42);
      expect(snapshot.isCanonical, isTrue);
      expect(snapshot.isUsable, isTrue);
      expect(snapshot.pair, 'USDC/GHS');
      expect(snapshot.settlementCurrency, 'USDC');
      expect(snapshot.displayCurrency, 'GHS');
      expect(snapshot.source, 'KOTANI_PAY');
    });

    test('legacy USD/GHS fallback is not considered canonical', () {
      final snapshot = parseFxRateSnapshot({
        'liveUsdToGhs': 13.10,
        'rateSource': 'LEGACY',
      });

      expect(snapshot.ghsPerUsdc, 13.10);
      expect(snapshot.isCanonical, isFalse);
      expect(snapshot.isUsable, isFalse);
    });

    test('zero or negative rates never become usable', () {
      final snapshot = parseFxRateSnapshot({
        'pair': 'USDC/GHS',
        'settlementCurrency': 'USDC',
        'displayCurrency': 'GHS',
        'liveRetailRate': 0,
      });

      expect(snapshot.ghsPerUsdc, 0);
      expect(snapshot.isCanonical, isFalse);
      expect(snapshot.isUsable, isFalse);
    });
  });
}
