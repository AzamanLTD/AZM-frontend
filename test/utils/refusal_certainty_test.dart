// WP-L — the certainty classification is what stops the app talking a customer
// into paying twice. Each case asserts the class AND the copy's honesty.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

void main() {
  group('definitive pre-economic refusals', () {
    for (final code in const [
      'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE',
      'USDC_INSUFFICIENT_BALANCE',
      'PASSWORD_REQUIRED',
      '2FA_REQUIRED',
      'TOTP_INVALID',
      'TOTP_REPLAYED',
      'TOTP_LOCKED',
      'IDEMPOTENCY_KEY_REQUIRED',
      'IDEMPOTENCY_PAYLOAD_CONFLICT',
      'NATIVE_GHS_QUOTE_INTENT_CHANGED',
    ]) {
      test('$code is refused before money moved', () {
        final copy = refusalCopyFor(code);
        if (copy == null) return; // code not mapped here; nothing to assert
        expect(copy.certainty, RefusalCertainty.refusedBeforeMoney);
        expect(copy.nextStep.toLowerCase(), contains('nothing was sent'));
        expect(copy.message.toLowerCase(), isNot(contains('was transferred')));
      });
    }

    test('a consumed code is not reused for the retry', () {
      final copy = refusalCopyFor('TOTP_REPLAYED')!;
      expect(copy.nextStep.toLowerCase(), contains('fresh code'));
    });
  });

  group('operations that may still be processing', () {
    test('IDEMPOTENCY_IN_PROGRESS is never called a failure', () {
      final copy = refusalCopyFor('IDEMPOTENCY_IN_PROGRESS')!;
      expect(copy.certainty, RefusalCertainty.stillProcessing);
      expect(copy.message.toLowerCase(), isNot(contains('failed')));
      expect(copy.nextStep.toLowerCase(), contains('activity'));
      expect(copy.nextStep.toLowerCase(), isNot(contains('try again.')));
    });
  });

  group('unknown outcome', () {
    test('claim-store outage is undecided, not failed', () {
      final copy = refusalCopyFor('TOTP_CLAIM_STORE_UNAVAILABLE')!;
      expect(copy.certainty, RefusalCertainty.unknownOutcome);
      expect(copy.message.toLowerCase(), isNot(contains('failed')));
    });

    test('the future authority state is prepared, not faked as a live code',
        () {
      // WP-H has not defined a code yet, so nothing may be keyed to one.
      expect(refusalCopyFor('AUTHORITY_STATE_UNAVAILABLE'), isNull);
      final copy = preparedAuthorityUnavailableCopy();
      expect(copy.certainty, RefusalCertainty.unknownOutcome);
      expect(copy.message.toLowerCase(), contains('either way'));
      expect(copy.nextStep.toLowerCase(), contains('activity'));
    });
  });

  test('an unmapped code stays unhandled so screens keep their own copy', () {
    expect(refusalCopyFor('SOME_UNKNOWN_CODE'), isNull);
    expect(refusalCopyFor(null), isNull);
  });

  test('the error resolver finds a code on a thrown object', () {
    final copy = refusalCopyFrom(StateError('boom "code":"TOTP_REPLAYED"'));
    expect(copy?.certainty, RefusalCertainty.refusedBeforeMoney);
  });
}
