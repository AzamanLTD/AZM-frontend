// WP-L — every required refusal code must map to financially honest copy.
// These assert the *meaning*: no invented conversion, no claimed settlement,
// no permanent-failure claim for an ambiguous outcome.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

void main() {
  group('required refusal codes have distinct, honest copy', () {
    const codes = <String>[
      'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE',
      'TOTP_REPLAYED',
      'TOTP_CLAIM_STORE_UNAVAILABLE',
      'USDC_INSUFFICIENT_BALANCE',
      'NATIVE_GHS_QUOTE_INTENT_CHANGED',
      'NATIVE_GHS_QUOTE_INVALID',
      'IDEMPOTENCY_IN_PROGRESS',
    ];

    test('each code maps to non-empty copy', () {
      for (final c in codes) {
        expect(moneyRefusalMessage(c), isNotNull, reason: c);
        expect(moneyRefusalMessage(c)!.trim(), isNotEmpty, reason: c);
      }
    });

    test('the codes do not collapse into one generic message', () {
      final seen = <String>{};
      for (final c in codes) {
        seen.add(moneyRefusalMessage(c)!);
      }
      // Distinctness proves the UI can tell a replay from an outage from a
      // shortfall.
      expect(seen.length, codes.length);
    });

    test('GHS shortfall copy never claims a conversion happened', () {
      final t = moneyRefusalMessage('NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE')!
          .toLowerCase();
      // Honest copy NEGATES the conversion; it must never assert one.
      expect(t.contains('no conversion'), isTrue);
      expect(t.contains('was converted'), isFalse);
      expect(t.contains('has been sent'), isFalse);
    });

    test('TOTP replay tells the customer to use a fresh code', () {
      final t = moneyRefusalMessage('TOTP_REPLAYED')!.toLowerCase();
      expect(t.contains('code'), isTrue);
      expect(t.contains('used') || t.contains('wait') || t.contains('next'),
          isTrue);
    });

    test('claim-store outage does not read as a permanent failure', () {
      final t = moneyRefusalMessage('TOTP_CLAIM_STORE_UNAVAILABLE')!
          .toLowerCase();
      expect(
        t.contains('try again') ||
            t.contains('trying again') ||
            t.contains('may already'),
        isTrue,
      );
    });

    test('unknown codes stay unhandled so each screen keeps its own copy', () {
      expect(moneyRefusalMessage('SOME_FUTURE_CODE'), isNull);
    });
  });
}
