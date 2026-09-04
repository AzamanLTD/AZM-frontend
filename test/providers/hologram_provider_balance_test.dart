import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/providers/hologram_provider.dart';

void main() {
  group('BalanceData.fromJson', () {
    test('parses numeric and decimal-string ledger fields without losing zeroes', () {
      final balance = BalanceData.fromJson({
        'availableBalance': '125.50',
        'vendorUnallocatedBalance': 10,
        'escrowLockedBalance': '0',
        'disputeEscrowBalance': 4.25,
        'azmBalance': '900.75',
      });

      expect(balance.availableBalance, 125.50);
      expect(balance.vendorUnallocatedBalance, 10);
      expect(balance.escrowLockedBalance, 0);
      expect(balance.disputeEscrowBalance, 4.25);
      expect(balance.azmBalance, 900.75);
      expect(balance.totalBalance, 135.50);
      expect(balance.totalLocked, 4.25);
    });

    test('missing or malformed fields resolve to zero instead of inventing state', () {
      final balance = BalanceData.fromJson({
        'availableBalance': 'not-a-number',
        'vendorUnallocatedBalance': null,
        'escrowLockedBalance': false,
        'disputeEscrowBalance': '3.5',
      });

      expect(balance.availableBalance, 0);
      expect(balance.vendorUnallocatedBalance, 0);
      expect(balance.escrowLockedBalance, 0);
      expect(balance.disputeEscrowBalance, 3.5);
      expect(balance.azmBalance, 0);
    });
  });

  group('parseOracleGhsRate', () {
    test('reads wrapped canonical oracle response and uses liveRetailRate', () {
      expect(
        parseOracleGhsRate({
          'success': true,
          'data': {
            'pair': 'USDC/GHS',
            'settlementCurrency': 'USDC',
            'displayCurrency': 'GHS',
            'liveRetailRate': 13.42,
            'liveUsdToGhs': 13.10,
            'rateSource': 'KOTANI_PAY',
          },
        }),
        13.42,
      );
    });

    test('rejects legacy or metadata-free oracle shapes', () {
      expect(
        parseOracleGhsRate({
          'liveUsdToGhs': 12.88,
          'rate': 12.77,
        }),
        0,
      );
      expect(
        parseOracleGhsRate({
          'success': true,
          'data': {
            'pair': 'USD/GHS',
            'settlementCurrency': 'USD',
            'displayCurrency': 'GHS',
            'liveRetailRate': 13.42,
          },
        }),
        0,
      );
    });

    test('rejects invalid canonical retail rates without falling back to headline rate', () {
      expect(
        parseOracleGhsRate({
          'success': true,
          'data': {
            'pair': 'USDC/GHS',
            'settlementCurrency': 'USDC',
            'displayCurrency': 'GHS',
            'liveRetailRate': 'not-a-number',
            'liveUsdToGhs': '13.21',
          },
        }),
        0,
      );
    });

    test('rejects missing or non-positive canonical retail rate', () {
      expect(
        parseOracleGhsRate({
          'success': true,
          'data': {
            'pair': 'USDC/GHS',
            'settlementCurrency': 'USDC',
            'displayCurrency': 'GHS',
          },
        }),
        0,
      );
      expect(
        parseOracleGhsRate({
          'success': true,
          'data': {
            'pair': 'USDC/GHS',
            'settlementCurrency': 'USDC',
            'displayCurrency': 'GHS',
            'liveRetailRate': -1,
          },
        }),
        0,
      );
    });
  });
}
