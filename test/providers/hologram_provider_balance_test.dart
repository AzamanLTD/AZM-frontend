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
}
