// =============================================================================
// AZAMAN — FINANCIAL STEP-UP (WP-J)
//
// The backend's `require2FA` middleware reads `totpToken` (when 2FA is
// enabled) or `password` (when it is not) from the REQUEST BODY and strips
// both before the controller runs. A protected operation that arrives
// without either field is refused with 401 + code `2FA_REQUIRED` or
// `PASSWORD_REQUIRED`.
//
// This file is the single client-side authority for satisfying that
// contract. Screens never collect OTPs themselves: one prompt is installed
// at the app root, and [ApiClient] asks it exactly once per request when the
// backend demands a factor.
//
// SECURITY INVARIANTS (do not weaken):
//   • [StepUpCredential] holds its value in memory only. It is never added to
//     a durable-operation snapshot, never queued offline, never logged, and
//     its `toString` is redacted so an accidental interpolation cannot leak.
//   • A credential is used for exactly ONE transmit attempt.
//   • `TOTP_REPLAYED` and `TOTP_CLAIM_STORE_UNAVAILABLE` are NEVER retried
//     automatically: the first means the code was already spent, the second
//     means the verifier could not decide — both need the user, not a loop.
// =============================================================================

import 'package:flutter/foundation.dart';

/// Which factor the backend is asking for on this request.
enum StepUpFactor {
  /// `totpToken` — the account has 2FA enabled.
  totp,

  /// `password` — the account does not have 2FA enabled.
  password;

  /// The exact JSON body field the backend reads.
  String get bodyField => switch (this) {
        StepUpFactor.totp => 'totpToken',
        StepUpFactor.password => 'password',
      };

  String get promptTitle => switch (this) {
        StepUpFactor.totp => 'Authenticator code',
        StepUpFactor.password => 'Confirm your password',
      };
}

/// Backend refusal codes that mean "a step-up factor is missing", as opposed
/// to "the factor you sent was wrong".
abstract final class StepUpCodes {
  static const twoFactorRequired = '2FA_REQUIRED';
  static const passwordRequired = 'PASSWORD_REQUIRED';

  /// A spent TOTP step. Never auto-retried.
  static const totpReplayed = 'TOTP_REPLAYED';

  /// The verifier's claim store could not be consulted. Never auto-retried;
  /// the operation outcome is UNKNOWN, not failed.
  static const claimStoreUnavailable = 'TOTP_CLAIM_STORE_UNAVAILABLE';

  static const _challenge = {twoFactorRequired, passwordRequired};
  static const _ambiguous = {totpReplayed, claimStoreUnavailable};

  static bool isChallenge(String? code) => code != null && _challenge.contains(code);
  static bool isAmbiguous(String? code) => code != null && _ambiguous.contains(code);
}

/// One user-supplied factor, alive for the duration of a single attempt.
class StepUpCredential {
  StepUpCredential(this.factor, String value) : _value = value;

  final StepUpFactor factor;
  final String _value;

  /// The raw value. Deliberately a getter rather than a public field so it is
  /// never serialised accidentally by `jsonEncode(credential)`.
  String get value => _value;

  /// Explicit JSON refusal: a credential must never be serialised into a
  /// journal, analytics payload or durable snapshot.
  Object toJson() => throw UnsupportedError(
        'StepUpCredential must never be serialised. Add only the single '
        'body field for the immediate request.',
      );

  /// Redacted on purpose.
  @override
  String toString() => 'StepUpCredential(${factor.name}, <redacted>)';
}

/// What the UI is being asked for.
@immutable
class StepUpChallenge {
  const StepUpChallenge({
    required this.factor,
    required this.message,
    this.attemptsLeft,
  });

  final StepUpFactor factor;
  final String message;

  /// Present on app-unlock style refusals; null on `require2FA` challenges.
  final int? attemptsLeft;

  StepUpChallenge copyWith({String? message, int? attemptsLeft}) => StepUpChallenge(
        factor: factor,
        message: message ?? this.message,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
      );
}

/// The user dismissed the prompt. Distinct from "wrong credential": nothing
/// was sent, so a caller can offer the action again without side effects.
class StepUpCancelled implements Exception {
  const StepUpCancelled();
  @override
  String toString() => 'StepUpCancelled';
}

/// Resolves the factor to ask for, or null when the response is not a
/// step-up challenge. Pure and unit-testable — no Flutter dependency.
StepUpFactor? factorFor(int statusCode, String? code) {
  if (statusCode != 401) return null;
  return switch (code) {
    StepUpCodes.twoFactorRequired => StepUpFactor.totp,
    StepUpCodes.passwordRequired => StepUpFactor.password,
    _ => null,
  };
}

/// The single installed prompt.
abstract final class FinancialStepUp {
  static Future<StepUpCredential?> Function(StepUpChallenge)? _prompt;

  static void install(Future<StepUpCredential?> Function(StepUpChallenge) prompt) {
    _prompt = prompt;
  }

  static void uninstall() => _prompt = null;

  static bool get isInstalled => _prompt != null;

  /// Ask the user for [challenge]. Returns null when no prompt is installed
  /// (headless tests, background work) — the caller must then rethrow the
  /// original refusal rather than invent a credential.
  static Future<StepUpCredential?> request(StepUpChallenge challenge) async {
    final prompt = _prompt;
    if (prompt == null) return null;
    return prompt(challenge);
  }
}
