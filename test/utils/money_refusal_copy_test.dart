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
    // Corrected: require2FA refuses before idempotency and the controller on
    // every audited mount, so a replay refusal IS definite and pre-economic.
    expect(isDefiniteMoneyRefusal('TOTP_REPLAYED'), isTrue,
        reason: 'replay is refused before any economic handler runs');
  });

  test('claim-store outage is a definite pre-economic refusal', () {
    // Corrected contract: the claim-store outage is thrown inside require2FA,
    // which is mounted before idempotency() and the controller on every
    // audited route (verified on backend 6a6f233). The economic handler cannot
    // have run, so this is NOT an ambiguous economic outcome — and the old
    // "it may already have gone through" wording contradicted the certainty
    // model. Both statements can no longer coexist.
    const code = 'TOTP_CLAIM_STORE_UNAVAILABLE';
    final copy = refusalCopyFor(code)!;
    expect(copy.certainty, RefusalCertainty.refusedBeforeMoney);
    expect(copy.retryIsSafe, isTrue);
    expect(isDefiniteMoneyRefusal(code), isTrue);
    expect(isAmbiguousMoneyRefusal(code), isFalse);
    expect(copy.message.toLowerCase(), isNot(contains('failed')));
    expect(copy.message.toLowerCase(), isNot(contains('may already')));
    expect(copy.display.toLowerCase(), contains('nothing was sent'));
  });

  test('unknown codes stay unhandled so callers keep their own copy', () {
    expect(moneyRefusalMessage(null), isNull);
    expect(moneyRefusalMessage('SOMETHING_ELSE'), isNull);
  });
}
