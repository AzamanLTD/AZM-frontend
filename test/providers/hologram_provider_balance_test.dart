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

  group('BalanceData.tryParseValidPayload — the strict refresh law', () {
    test('a fully valid payload parses, and a GENUINE zero stays zero', () {
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': 0,
        'vendorUnallocatedBalance': '0',
        'escrowLockedBalance': 0.0,
        'disputeEscrowBalance': '0.00',
        'azmBalance': 0,
      });
      expect(b, isNotNull,
          reason: 'a valid server-confirmed zero is a confirmed balance');
      expect(b!.availableBalance, 0);
      expect(b.azmBalance, 0);
      expect(b.valuationFieldPresent, isFalse,
          reason: 'legacy responses carry no valuation key');
      expect(b.valuationRaw, isNull);
    });

    test('numeric strings are accepted (Prisma Decimals serialize as strings)', () {
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': '125.50',
        'vendorUnallocatedBalance': '10',
        'escrowLockedBalance': '0',
        'disputeEscrowBalance': '4.25',
        'azmBalance': '900.75',
      });
      expect(b!.availableBalance, 125.50);
      expect(b.azmBalance, 900.75);
    });

    test('ANY missing legacy field → the payload is INVALID (null)', () {
      for (final missing in [
        'availableBalance',
        'vendorUnallocatedBalance',
        'escrowLockedBalance',
        'disputeEscrowBalance',
        'azmBalance',
      ]) {
        final payload = <String, dynamic>{
          'availableBalance': 1,
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        };
        payload.remove(missing);
        expect(BalanceData.tryParseValidPayload(payload), isNull,
            reason: 'a payload without $missing must not be read as a '
                'confirmed balance');
      }
    });

    test('ANY malformed legacy field → the payload is INVALID (null), '
        'never a fabricated zero', () {
      for (final key in [
        'availableBalance',
        'vendorUnallocatedBalance',
        'escrowLockedBalance',
        'disputeEscrowBalance',
        'azmBalance',
      ]) {
        final payload = <String, dynamic>{
          'availableBalance': 1,
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        };
        payload[key] = 'not-a-number';
        expect(BalanceData.tryParseValidPayload(payload), isNull,
            reason: '$key malformed must fail the whole payload — the '
                'lenient 0.0 of fromJson would display a fabricated '
                'balance as though the server confirmed it');
      }
    });

    test('booleans and nulls are malformed, not zero', () {
      expect(
        BalanceData.tryParseValidPayload({
          'availableBalance': false,
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        }),
        isNull,
      );
      expect(
        BalanceData.tryParseValidPayload({
          'availableBalance': null,
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        }),
        isNull,
      );
    });

    test('non-finite numbers are malformed (NaN / Infinity)', () {
      expect(
        BalanceData.tryParseValidPayload({
          'availableBalance': double.nan,
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        }),
        isNull,
      );
      expect(
        BalanceData.tryParseValidPayload({
          'availableBalance': 'Infinity',
          'vendorUnallocatedBalance': 2,
          'escrowLockedBalance': 3,
          'disputeEscrowBalance': 4,
          'azmBalance': 5,
        }),
        isNull,
      );
    });

    test('valuation: ABSENT key → legacy state', () {
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': 1,
        'vendorUnallocatedBalance': 2,
        'escrowLockedBalance': 3,
        'disputeEscrowBalance': 4,
        'azmBalance': 5,
      });
      expect(b!.valuationFieldPresent, isFalse);
      expect(b.valuationRaw, isNull);
    });

    test('valuation: EXPLICIT null → present + unavailable', () {
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': 1,
        'vendorUnallocatedBalance': 2,
        'escrowLockedBalance': 3,
        'disputeEscrowBalance': 4,
        'azmBalance': 5,
        'valuation': null,
      });
      expect(b!.valuationFieldPresent, isTrue);
      expect(b.valuationRaw, isNull,
          reason: 'explicit null means the backend SAYS the valuation is '
              'unavailable — distinct from the field being absent');
    });

    test('valuation: a Map → carried raw for the typed strict parse', () {
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': 1,
        'vendorUnallocatedBalance': 2,
        'escrowLockedBalance': 3,
        'disputeEscrowBalance': 4,
        'azmBalance': 5,
        'valuation': {'pair': 'USDC/GHS'},
      });
      expect(b!.valuationFieldPresent, isTrue);
      expect(b.valuationRaw, isA<Map<String, dynamic>>());
      expect(b.valuationRaw!['pair'], 'USDC/GHS');
    });

    test('a malformed VALUATION does not invalidate the LEGACY fields', () {
      // The valuation block rides ALONGSIDE valid ledger figures: even a
      // garbage valuation value keeps the balance confirmed — the
      // adapter treats a malformed valuation as an explicit
      // unavailability, not a ledger failure.
      final b = BalanceData.tryParseValidPayload({
        'availableBalance': 1,
        'vendorUnallocatedBalance': 2,
        'escrowLockedBalance': 3,
        'disputeEscrowBalance': 4,
        'azmBalance': 5,
        'valuation': 'garbage-not-a-map',
      });
      expect(b, isNotNull);
      expect(b!.valuationFieldPresent, isTrue);
      expect(b.valuationRaw, isNull,
          reason: 'a non-Map valuation is carried as explicit '
              'unavailability');
    });
  });
}
