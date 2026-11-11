// WP-L — copy accuracy tests. These assert the NEGATIVE guarantees: the words
// must not claim a conversion, a failure, or a payment that did not happen.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

void main() {
  test('GHS shortfall never implies a conversion happened', () {
    const code = 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE';
    final msg = moneyRefusalMessage(code)!;
    expect(msg.toLowerCase(), contains('no'), reason: 'must state nothing was sent');
    expect(msg.toLowerCase(), isNot(contains('converted')));
    expect(msg.toLowerCase(), isNot(contains('we converted')));
    expect(isDefiniteMoneyRefusal(code), isTrue);
    expect(isAmbiguousMoneyRefusal(code), isFalse);
  });

  test('TOTP_REPLAYED says nothing was sent and asks for the next code', () {
    final msg = moneyRefusalMessage('TOTP_REPLAYED')!;
    expect(msg.toLowerCase(), contains('nothing was sent'));
    expect(isDefiniteMoneyRefusal('TOTP_REPLAYED'), isFalse,
        reason: 'replay is pre-economic but not one of the GHS classes');
  });

  test('claim-store outage is ambiguous, never a failure or a success', () {
    const code = 'TOTP_CLAIM_STORE_UNAVAILABLE';
    final msg = moneyRefusalMessage(code)!;
    expect(isAmbiguousMoneyRefusal(code), isTrue);
    expect(isDefiniteMoneyRefusal(code), isFalse);
    expect(msg.toLowerCase(), isNot(contains('failed')));
    expect(msg.toLowerCase(), contains('may already'));
  });

  test('unknown codes stay unhandled so callers keep their own copy', () {
    expect(moneyRefusalMessage(null), isNull);
    expect(moneyRefusalMessage('SOMETHING_ELSE'), isNull);
  });
}
