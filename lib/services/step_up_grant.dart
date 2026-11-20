// =============================================================================
// AZAMAN — ACTION-BOUND STEP-UP GRANT (WP-H client protocol)
//
// The legacy `require2FA` contract (see financial_step_up.dart) puts the factor
// in the request BODY and is understood by `factorFor()`. The newer WP-H
// contract is different and stricter: the backend refuses with
// `STEP_UP_REQUIRED` and describes the EXACT action it will accept a grant for.
//
//   1. POST the financial action            -> 409/401 STEP_UP_REQUIRED
//      { actionType, actionDigest, action: {...material descriptor...} }
//   2. POST { action } to /api/step-up/grant (no credential)
//                                            -> 2FA_REQUIRED | PASSWORD_REQUIRED
//   3. POST { action, totpToken|password } to /api/step-up/grant
//                                            -> { stepUpGrant, actionDigest, ... }
//   4. Retry the ORIGINAL request, same body, same Idempotency-Key, plus
//      `x-step-up-grant`.
//
// INVARIANTS (each has a test):
//   • The server's `action` descriptor is carried VERBATIM. This client never
//     rebuilds or normalises it from screen state — a descriptor the user
//     cannot see must never be re-derived from a screen they can.
//   • The grant's digest must equal the challenge's digest. A mismatch refuses
//     BEFORE the economic action is transmitted.
//   • The grant token and the proof are credentials: memory-only, redacted in
//     toString, refused by toJson, never written to a durable operation.
//   • A cancelled prompt sends nothing and keeps the operation identity.
// =============================================================================

import 'package:flutter/foundation.dart';

import 'financial_step_up.dart';

abstract final class StepUpGrantCodes {
  /// The backend wants an action-bound grant.
  static const stepUpRequired = 'STEP_UP_REQUIRED';

  /// Returned by the grant endpoint when the account needs TOTP.
  static const twoFactorRequired = '2FA_REQUIRED';

  /// Returned by the grant endpoint when the account needs its password.
  static const passwordRequired = 'PASSWORD_REQUIRED';

  /// The grant endpoint's route.
  static const grantPath = '/api/step-up/grant';

  /// The header the granted token travels in.
  static const grantHeader = 'x-step-up-grant';
}

/// The server's description of the action a grant will be bound to.
///
/// [action] is opaque to this client on purpose: it is forwarded to the grant
/// endpoint exactly as received. [actionDigest] is what the issued grant must
/// match before the economic retry is allowed.
@immutable
class StepUpGrantChallenge {
  const StepUpGrantChallenge({
    required this.actionType,
    required this.actionDigest,
    required this.action,
    this.message,
  });

  final String? actionType;
  final String actionDigest;
  final Map<String, dynamic> action;
  final String? message;

  /// Parse the backend's STEP_UP_REQUIRED body. Returns null when the body is
  /// not a usable challenge — the caller must then rethrow the original
  /// refusal rather than invent one.
  static StepUpGrantChallenge? fromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    final digest = body['actionDigest'];
    final action = body['action'];
    if (digest is! String || digest.isEmpty) return null;
    if (action is! Map) return null;
    return StepUpGrantChallenge(
      actionType: body['actionType'] is String ? body['actionType'] as String : null,
      actionDigest: digest,
      action: Map<String, dynamic>.from(action),
      message: body['message'] is String ? body['message'] as String : null,
    );
  }

  /// The grant request body: the server's descriptor, plus a proof only when
  /// one has been supplied. Step 2 of the protocol sends no credential at all.
  Map<String, dynamic> grantBody({StepUpCredential? credential}) => <String, dynamic>{
        'action': action,
        if (credential != null) credential.factor.bodyField: credential.value,
      };

  @override
  String toString() =>
      'StepUpGrantChallenge(${actionType ?? 'unknown'}, digest=$actionDigest)';
}

/// A granted, single-use token bound to [actionDigest].
@immutable
class StepUpGrant {
  const StepUpGrant({
    required this.token,
    required this.actionDigest,
    this.expiresAt,
    this.ttlSeconds,
  });

  final String token;
  final String actionDigest;
  final String? expiresAt;
  final int? ttlSeconds;

  /// Parse the grant endpoint's success body, or null when it is not a grant.
  static StepUpGrant? fromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    final token = body['stepUpGrant'];
    final digest = body['actionDigest'];
    if (token is! String || token.isEmpty) return null;
    if (digest is! String || digest.isEmpty) return null;
    return StepUpGrant(
      token: token,
      actionDigest: digest,
      expiresAt: body['expiresAt'] is String ? body['expiresAt'] as String : null,
      ttlSeconds: body['ttlSeconds'] is int ? body['ttlSeconds'] as int : null,
    );
  }

  /// The grant is only usable for the action it was issued for.
  bool matches(StepUpGrantChallenge challenge) => actionDigest == challenge.actionDigest;

  /// A token is a credential.
  Object toJson() => throw UnsupportedError(
        'StepUpGrant must never be serialised. Send it in the retry header only.',
      );

  @override
  String toString() => 'StepUpGrant(digest=$actionDigest, token=<redacted>)';
}

/// A grant could not be obtained for a reason the user must resolve.
class StepUpGrantRefused implements Exception {
  const StepUpGrantRefused(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'StepUpGrantRefused(${code ?? 'no-code'}: $message)';
}

/// The digest the server issued does not match the one it challenged with.
/// The economic action is NEVER transmitted in this state.
class StepUpGrantDigestMismatch implements Exception {
  const StepUpGrantDigestMismatch(this.expected, this.received);
  final String expected;
  final String received;
  @override
  String toString() => 'StepUpGrantDigestMismatch(expected=$expected, received=$received)';
}

/// One HTTP result, shaped so the protocol is testable without a live server.
@immutable
class StepUpHttpResult {
  const StepUpHttpResult({required this.statusCode, this.body, this.code});
  final int statusCode;
  final Map<String, dynamic>? body;
  final String? code;
  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// The action-bound grant protocol, transport-injected.
///
/// [send] performs one unauthenticated-or-authenticated POST to the grant
/// endpoint. Production passes the app's ApiClient; tests pass a fake, so the
/// full four-step exchange is exercised at the API level.
class StepUpGrantProtocol {
  StepUpGrantProtocol({required this.send});

  final Future<StepUpHttpResult> Function(String path, Map<String, dynamic> body) send;

  /// Steps 2–3: discover the factor, then obtain the grant.
  ///
  /// Returns the granted token, or throws:
  ///   • [StepUpCancelled]      — the user dismissed the prompt (nothing sent);
  ///   • [StepUpGrantRefused]   — the backend refused the proof;
  ///   • [StepUpGrantDigestMismatch] — the grant is not for this action.
  Future<StepUpGrant> obtain(StepUpGrantChallenge challenge) async {
    // Step 2 — no credential: the backend tells us which factor it wants.
    final probe = await send(
      StepUpGrantCodes.grantPath,
      challenge.grantBody(),
    );

    StepUpFactor? factor;
    if (probe.ok) {
      // Some backends grant immediately when the action needs no proof.
      final granted = StepUpGrant.fromBody(probe.body);
      if (granted != null) return _verified(granted, challenge);
      throw const StepUpGrantRefused('The step-up service returned no grant.');
    }
    switch (probe.code) {
      case StepUpGrantCodes.twoFactorRequired:
        factor = StepUpFactor.totp;
      case StepUpGrantCodes.passwordRequired:
        factor = StepUpFactor.password;
      default:
        throw StepUpGrantRefused(
          probe.body?['message'] as String? ?? 'This action could not be verified.',
          code: probe.code,
        );
    }

    // Step 3 — the same action plus the proof the backend actually asked for.
    final credential = await FinancialStepUp.request(
      StepUpChallenge(
        factor: factor,
        message: challenge.message ?? 'Confirm this action to continue.',
      ),
    );
    if (credential == null) throw const StepUpCancelled();

    final granted = await send(
      StepUpGrantCodes.grantPath,
      challenge.grantBody(credential: credential),
    );
    if (!granted.ok) {
      throw StepUpGrantRefused(
        granted.body?['message'] as String? ?? 'That confirmation was not accepted.',
        code: granted.code,
      );
    }
    final grant = StepUpGrant.fromBody(granted.body);
    if (grant == null) {
      throw const StepUpGrantRefused('The step-up service returned no grant.');
    }
    return _verified(grant, challenge);
  }

  StepUpGrant _verified(StepUpGrant grant, StepUpGrantChallenge challenge) {
    if (!grant.matches(challenge)) {
      throw StepUpGrantDigestMismatch(challenge.actionDigest, grant.actionDigest);
    }
    return grant;
  }
}
