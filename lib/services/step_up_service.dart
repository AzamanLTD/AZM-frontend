import 'dart:convert';

/// §WP-H G — the client half of action-bound step-up verification.
///
/// The backend gate answers `401 STEP_UP_REQUIRED` with `actionType`,
/// `actionDigest` and `action`: the server's OWN canonical descriptor for the
/// exact request it refused. The client never reconstructs that descriptor (a
/// guess would hash differently and the capability would authorise nothing).
/// It echoes `action` back to `/api/step-up/grant` together with a proof, gets a
/// single-use grant, and replays the original request once with that grant.
class StepUpChallenge {
  const StepUpChallenge({
    required this.actionType,
    required this.actionDigest,
    required this.action,
  });

  final String actionType;
  final String actionDigest;
  final Map<String, dynamic> action;

  /// Parses a 401 body. Returns null for anything that is not a step-up
  /// challenge, so ordinary auth failures keep their existing handling.
  static StepUpChallenge? fromBody(Map<String, dynamic> body) {
    if (body['code']?.toString() != 'STEP_UP_REQUIRED') return null;
    final rawAction = body['action'];
    if (rawAction is! Map) return null;
    final action = <String, dynamic>{};
    rawAction.forEach((key, value) => action[key.toString()] = value);
    // Without the descriptor there is nothing to echo, and an unbound challenge
    // must not be turned into a prompt the user cannot satisfy.
    if (action.isEmpty) return null;
    return StepUpChallenge(
      actionType: body['actionType']?.toString() ?? '',
      actionDigest: body['actionDigest']?.toString() ?? '',
      action: action,
    );
  }

  /// What the sheet shows the user, derived from the canonical descriptor.
  String get summary {
    final amount = action['amount']?.toString();
    final currency = action['currency']?.toString();
    final destination = action['destination']?.toString();
    final parts = <String>[];
    if (amount != null && amount.isNotEmpty) {
      parts.add(currency == null || currency.isEmpty
          ? amount
          : '$currency $amount');
    }
    if (destination != null && destination.isNotEmpty) {
      parts.add('to $destination');
    }
    return parts.isEmpty ? actionType : parts.join(' ');
  }

  @override
  String toString() =>
      'StepUpChallenge($actionType, $actionDigest)';
}

/// A proof of possession. Exactly one of the two is ever sent: a TOTP code for
/// accounts with 2FA enabled, a password otherwise. The backend decides which it
/// will accept and refuses anything unverifiable.
class StepUpProof {
  const StepUpProof.totp(String code)
      : totpToken = code,
        password = null;

  const StepUpProof.password(String value)
      : totpToken = null,
        password = value;

  final String? totpToken;
  final String? password;

  bool get isEmpty =>
      (totpToken == null || totpToken!.isEmpty) &&
      (password == null || password!.isEmpty);

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (totpToken != null) 'totpToken': totpToken,
        if (password != null) 'password': password,
      };
}

/// Asked to obtain a proof for [challenge]. Returning null means the user
/// cancelled: the original failure is surfaced unchanged and nothing is retried.
typedef StepUpProofProvider = Future<StepUpProof?> Function(
    StepUpChallenge challenge);

/// Raised when the grant endpoint refuses the proof. Carries the backend's own
/// code so callers can distinguish a wrong code from an unavailable claim store.
class StepUpGrantException implements Exception {
  const StepUpGrantException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  bool get isUnavailable => statusCode == 503;

  @override
  String toString() => message;
}

/// Parses a grant response body.
///
/// Kept here (not in ApiClient) so the wire contract has exactly one definition:
/// `/api/step-up/grant` answers 201 with `stepUpGrant`, `actionDigest`,
/// `expiresAt` and `ttlSeconds`, and the token is valid exactly once.
class StepUpGrant {
  const StepUpGrant({
    required this.token,
    required this.actionDigest,
    this.expiresAt,
  });

  final String token;
  final String actionDigest;
  final String? expiresAt;

  static StepUpGrant? fromBody(Map<String, dynamic> body) {
    final token = body['stepUpGrant']?.toString();
    if (token == null || token.isEmpty) return null;
    return StepUpGrant(
      token: token,
      actionDigest: body['actionDigest']?.toString() ?? '',
      expiresAt: body['expiresAt']?.toString(),
    );
  }
}

/// Best-effort decode of a response body that may not be JSON at all.
Map<String, dynamic>? decodeJsonObject(String body) {
  if (body.isEmpty) return null;
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map) {
      final out = <String, dynamic>{};
      parsed.forEach((key, value) => out[key.toString()] = value);
      return out;
    }
  } on FormatException {
    return null;
  }
  return null;
}
