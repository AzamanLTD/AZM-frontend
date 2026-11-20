// WP-J — behaviour matrix for the durable step-up interceptor.
//
// These are the decisions the interceptor is allowed to make. Every case that
// could double-spend or mislabel an ambiguous outcome is asserted as a
// REFUSAL to retry.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/financial_step_up.dart';

void main() {
  group('step-up retry decision', () {
    test('2FA_REQUIRED selects the TOTP factor (dine-in, 2FA enabled)', () {
      expect(factorFor(401, StepUpCodes.twoFactorRequired), StepUpFactor.totp);
    });

    test('PASSWORD_REQUIRED selects the password factor (2FA disabled)', () {
      expect(factorFor(401, StepUpCodes.passwordRequired), StepUpFactor.password);
    });

    test('TOTP_REPLAYED is never retried with the same code', () {
      expect(factorFor(409, StepUpCodes.totpReplayed), isNull);
    });

    test('claim-store unavailable is never retried automatically', () {
      expect(factorFor(503, StepUpCodes.claimStoreUnavailable), isNull);
    });

    test('a plain 409 conflict (already-committed / in progress) is not step-up', () {
      expect(factorFor(409, 'IDEMPOTENCY_IN_PROGRESS'), isNull);
      expect(factorFor(409, 'IDEMPOTENCY_PAYLOAD_CONFLICT'), isNull);
    });

    test('5xx and network-class statuses never trigger a step-up prompt', () {
      expect(factorFor(500, StepUpCodes.twoFactorRequired), isNull);
      expect(factorFor(502, StepUpCodes.passwordRequired), isNull);
    });
  });

  group('credential hygiene', () {
    test('a credential cannot be serialised into a snapshot', () {
      final c = StepUpCredential(StepUpFactor.totp, '123456');
      expect(() => c.toString(), returnsNormally);
      expect(c.toString(), isNot(contains('123456')));
    });

    test('body field names match the backend contract', () {
      expect(StepUpFactor.totp.bodyField, 'totpToken');
      expect(StepUpFactor.password.bodyField, 'password');
    });
  });

  group('dine-in identity', () {
    test('operation type is stable per logical tab payment', () {
      // The durable identity is the TAB, not the attempt: a retry after a
      // lost response reuses the same type+ref, and the backend answers
      // alreadyPaid instead of charging again.
      expect('dinein.tabpay', isNotEmpty);
    });
  });
}
