// WP-L — the certainty model, tested as a contract.
//
// Each case pins the classification to backend evidence (cited in
// money_refusal_copy.dart) and asserts the customer copy never contradicts it.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

/// Every code the copy layer speaks about, with its proven certainty.
const _expected = <String, RefusalCertainty>{
  // require2FA runs before idempotency and the handler on all 19 mounts.
  '2FA_REQUIRED': RefusalCertainty.refusedBeforeMoney,
  'PASSWORD_REQUIRED': RefusalCertainty.refusedBeforeMoney,
  'TOTP_INVALID': RefusalCertainty.refusedBeforeMoney,
  'TOTP_REPLAYED': RefusalCertainty.refusedBeforeMoney,
  'TOTP_LOCKED': RefusalCertainty.refusedBeforeMoney,
  'TOTP_CLAIM_STORE_UNAVAILABLE': RefusalCertainty.refusedBeforeMoney,
  // idempotency.js:211 — rejected before a claim exists.
  'IDEMPOTENCY_KEY_REQUIRED': RefusalCertainty.refusedBeforeMoney,
  // Thrown before $transaction / inside a rolling-back transaction.
  'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE':
      RefusalCertainty.refusedBeforeMoney,
  'NATIVE_GHS_QUOTE_INTENT_CHANGED': RefusalCertainty.refusedBeforeMoney,
  'NATIVE_GHS_QUOTE_INTENT_MISMATCH': RefusalCertainty.refusedBeforeMoney,
  'NATIVE_GHS_QUOTE_INVALID': RefusalCertainty.refusedBeforeMoney,
  'INSUFFICIENT_FUNDS': RefusalCertainty.refusedBeforeMoney,
  'INSUFFICIENT_BALANCE': RefusalCertainty.refusedBeforeMoney,
  // A claim exists and is mid-flight.
  'IDEMPOTENCY_IN_PROGRESS': RefusalCertainty.stillProcessing,
  // The prior operation committed.
  'IDEMPOTENCY_PAYLOAD_CONFLICT': RefusalCertainty.priorOperationCommitted,
};

void main() {
  group('classification is explicit per code (no broad default)', () {
    for (final entry in _expected.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        final copy = refusalCopyFor(entry.key);
        expect(copy, isNotNull, reason: '${entry.key} must be classified');
        expect(copy!.certainty, entry.value);
      });
    }

    test('unmapped codes are never classified', () {
      for (final code in const [
        'SOME_UNKNOWN_CODE',
        'AUTHENTICATION_VERIFICATION_FAILED',
        'PROVIDER_TIMEOUT',
        'INTERNAL_SERVER_ERROR',
        'AUTHORITY_STATE_UNAVAILABLE',
        '',
      ]) {
        expect(refusalCopyFor(code), isNull,
            reason: '$code has no proven certainty');
      }
      expect(refusalCopyFor(null), isNull);
    });
  });

  group('IDEMPOTENCY_PAYLOAD_CONFLICT is a committed-operation case', () {
    final copy = refusalCopyFor('IDEMPOTENCY_PAYLOAD_CONFLICT')!;

    test('it is never the generic "nothing was sent" refusal', () {
      expect(copy.certainty, isNot(RefusalCertainty.refusedBeforeMoney));
      expect(copy.certainty, RefusalCertainty.priorOperationCommitted);
      expect('${copy.message} ${copy.nextStep}'.toLowerCase(),
          isNot(contains('nothing was sent')));
    });

    test('it says the earlier payment completed and this one was not started',
        () {
      expect(copy.message.toLowerCase(), contains('already completed'));
      expect(copy.message.toLowerCase(), contains('was not started'));
    });

    test('it points at Activity and forbids a new payment', () {
      expect(copy.nextStep.toLowerCase(), contains('activity'));
      expect(copy.nextStep.toLowerCase(), contains('do not start a new payment'));
    });

    test('it never invents an operation reference', () {
      expect(RegExp(r'\b[A-Z0-9]{10,}\b').hasMatch(copy.nextStep), isFalse);
      expect(copy.nextStep.toLowerCase(), contains('if you cannot find it'));
    });
  });

  group('definite pre-economic refusals are labelled as such', () {
    for (final code in _expected.entries
        .where((e) => e.value == RefusalCertainty.refusedBeforeMoney)
        .map((e) => e.key)) {
      test('$code says nothing was sent and never claims success', () {
        final copy = refusalCopyFor(code)!;
        expect(copy.nextStep.toLowerCase(), contains('nothing was sent'));
        final all = '${copy.message} ${copy.nextStep}'.toLowerCase();
        expect(all, isNot(contains('failed')));
        expect(all, isNot(contains('was transferred')));
        expect(all, isNot(contains('has been paid')));
      });
    }

    test('a consumed TOTP code is never reused for the retry', () {
      final copy = refusalCopyFor('TOTP_REPLAYED')!;
      expect(copy.nextStep.toLowerCase(), contains('fresh authenticator code'));
    });

    test('a claim-store outage is pre-economic, not "unknown"', () {
      // require2FA() owns this refusal and runs before idempotency/handler.
      expect(refusalCopyFor('TOTP_CLAIM_STORE_UNAVAILABLE')!.certainty,
          RefusalCertainty.refusedBeforeMoney);
    });

    test('the shortfall refusal never implies a conversion happened', () {
      final copy =
          refusalCopyFor('NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE')!;
      expect(copy.message.toLowerCase(), contains('no conversion'));
      expect(copy.nextStep.toLowerCase(), contains('existing ghs balance'));
    });
  });

  group('in-flight work never reads as failed', () {
    test('IDEMPOTENCY_IN_PROGRESS blocks a second attempt', () {
      final copy = refusalCopyFor('IDEMPOTENCY_IN_PROGRESS')!;
      expect(copy.certainty, RefusalCertainty.stillProcessing);
      expect(copy.nextStep.toLowerCase(), contains('activity'));
      expect(copy.nextStep.toLowerCase(), contains('sending it again is not'));
      expect('${copy.message} ${copy.nextStep}'.toLowerCase(),
          isNot(contains('failed')));
    });
  });

  test('the prepared authority state is not a live backend code', () {
    expect(refusalCopyFor('AUTHORITY_STATE_UNAVAILABLE'), isNull);
    final prepared = preparedAuthorityUnavailableCopy();
    expect(prepared.certainty, RefusalCertainty.unknownOutcome);
    expect(prepared.message.toLowerCase(), contains('either way'));
  });

  test('the error resolver reads a code off a thrown object', () {
    final copy = refusalCopyFrom(StateError('x "code":"TOTP_REPLAYED"'));
    expect(copy?.certainty, RefusalCertainty.refusedBeforeMoney);
  });
}
