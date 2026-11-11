// WP-J — step-up contract tests.
//
// These prove the parts that must never regress:
//   • which backend refusals count as a step-up challenge;
//   • that a spent/undecided TOTP outcome is NOT retried automatically;
//   • that a credential cannot be serialised, logged or stringified;
//   • that the prompt is optional and its absence never invents a value.

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/financial_step_up.dart';

void main() {
  group('factorFor — backend contract', () {
    test('401 + 2FA_REQUIRED asks for the authenticator code', () {
      expect(factorFor(401, StepUpCodes.twoFactorRequired), StepUpFactor.totp);
      expect(StepUpFactor.totp.bodyField, 'totpToken');
    });

    test('401 + PASSWORD_REQUIRED asks for the password', () {
      expect(factorFor(401, StepUpCodes.passwordRequired), StepUpFactor.password);
      expect(StepUpFactor.password.bodyField, 'password');
    });

    test('non-401 statuses never trigger a prompt', () {
      for (final status in [200, 400, 403, 409, 422, 429, 500, 503]) {
        expect(factorFor(status, StepUpCodes.twoFactorRequired), isNull,
            reason: 'status $status must not prompt');
      }
    });

    test('a 401 without a step-up code is not a challenge', () {
      expect(factorFor(401, null), isNull);
      expect(factorFor(401, 'INVALID_TOKEN'), isNull);
      expect(factorFor(401, 'SESSION_EXPIRED'), isNull);
    });

    test('TOTP_REPLAYED and claim-store outage are ambiguous, never challenges', () {
      expect(StepUpCodes.isChallenge(StepUpCodes.totpReplayed), isFalse);
      expect(StepUpCodes.isChallenge(StepUpCodes.claimStoreUnavailable), isFalse);
      expect(StepUpCodes.isAmbiguous(StepUpCodes.totpReplayed), isTrue);
      expect(StepUpCodes.isAmbiguous(StepUpCodes.claimStoreUnavailable), isTrue);
      // 409 replay and 503 unavailable never route through factorFor.
      expect(factorFor(409, StepUpCodes.totpReplayed), isNull);
      expect(factorFor(503, StepUpCodes.claimStoreUnavailable), isNull);
    });
  });

  group('StepUpCredential — secrecy invariants', () {
    test('toString is redacted', () {
      final c = StepUpCredential(StepUpFactor.totp, '123456');
      expect(c.toString(), isNot(contains('123456')));
      expect(c.toString(), contains('redacted'));
    });

    test('toJson refuses to serialise the secret', () {
      final c = StepUpCredential(StepUpFactor.password, 'hunter2');
      expect(c.toJson, throwsUnsupportedError);
    });

    test('the value is reachable only through the getter', () {
      final c = StepUpCredential(StepUpFactor.password, 'hunter2');
      expect(c.value, 'hunter2');
      expect(c.factor, StepUpFactor.password);
    });
  });

  group('FinancialStepUp — prompt installation', () {
    tearDown(FinancialStepUp.uninstall);

    test('no prompt installed yields null (caller must rethrow)', () async {
      expect(FinancialStepUp.isInstalled, isFalse);
      final got = await FinancialStepUp.request(
        const StepUpChallenge(factor: StepUpFactor.totp, message: 'x'),
      );
      expect(got, isNull);
    });

    test('installed prompt is asked exactly once per request', () async {
      var asks = 0;
      FinancialStepUp.install((challenge) async {
        asks++;
        return StepUpCredential(challenge.factor, '654321');
      });
      final got = await FinancialStepUp.request(
        const StepUpChallenge(factor: StepUpFactor.totp, message: 'x'),
      );
      expect(asks, 1);
      expect(got?.value, '654321');
    });

    test('a dismissed prompt resolves to null without inventing a value', () async {
      FinancialStepUp.install((_) async => null);
      expect(
        await FinancialStepUp.request(
          const StepUpChallenge(factor: StepUpFactor.password, message: 'x'),
        ),
        isNull,
      );
    });

    test('attemptsLeft survives onto the challenge', () {
      const c = StepUpChallenge(
        factor: StepUpFactor.totp,
        message: 'Invalid code',
        attemptsLeft: 2,
      );
      expect(c.attemptsLeft, 2);
    });
  });
}
