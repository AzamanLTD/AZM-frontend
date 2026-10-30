// AZAMAN — MEMBER APP UNLOCK, CLIENT CONTRACT
//
// The HTTP half of the app-wide money lock. Every route below exists in the
// backend's app-unlock surface (routes/securityRoutes.js on
// feat/member-app-unlock-security); nothing here is invented, and nothing here
// grants a session — the server returns a VERDICT, never a token.
//
//   GET    /security/app-unlock/capabilities   → what THIS account can use
//   POST   /security/app-unlock/pin/verify     → { pin }
//   POST   /security/app-unlock/totp/verify    → { token }
//   POST   /security/app-unlock/sms/send       → challengeId + maskedPhone
//   POST   /security/app-unlock/sms/verify     → { challengeId, code }
//
// Available is a server fact, never a client assumption: a method is offered
// only when the capabilities call says the account is configured for it, and
// SMS is offered only when the server says the SMS facility can actually
// deliver (an OTP store with no provider is not an unlock method).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';

/// The unlock challenges the member may be asked for.
enum AppUnlockMethod { deviceAuth, pin, totp, sms }

/// What this account can actually do, as reported by the backend.
@immutable
class AppUnlockCapabilities {
  const AppUnlockCapabilities({
    required this.pinConfigured,
    required this.authenticatorConfigured,
    required this.phoneVerified,
    required this.smsUnlockAvailable,
    this.smsUnavailableReason,
  });

  /// Everything unavailable: the honest default while the call is in flight or
  /// when it failed. Never claims a method exists.
  static const AppUnlockCapabilities none = AppUnlockCapabilities(
    pinConfigured: false,
    authenticatorConfigured: false,
    phoneVerified: false,
    smsUnlockAvailable: false,
  );

  final bool pinConfigured;
  final bool authenticatorConfigured;
  final bool phoneVerified;
  final bool smsUnlockAvailable;

  /// Why SMS cannot be used (PHONE_UNVERIFIED, SMS_SERVICE_UNAVAILABLE, …).
  final String? smsUnavailableReason;

  factory AppUnlockCapabilities.fromJson(Map<String, dynamic> json) =>
      AppUnlockCapabilities(
        pinConfigured: json['pinConfigured'] == true,
        authenticatorConfigured: json['authenticatorConfigured'] == true,
        phoneVerified: json['phoneVerified'] == true,
        smsUnlockAvailable: json['smsUnlockAvailable'] == true,
        smsUnavailableReason: json['smsUnavailableReason']?.toString(),
      );

  /// The backend-configured methods, in the order the sheet offers them.
  List<AppUnlockMethod> get configured => [
    if (pinConfigured) AppUnlockMethod.pin,
    if (authenticatorConfigured) AppUnlockMethod.totp,
    if (smsUnlockAvailable) AppUnlockMethod.sms,
  ];

  bool canUse(AppUnlockMethod method) => switch (method) {
    AppUnlockMethod.deviceAuth => true,
    AppUnlockMethod.pin => pinConfigured,
    AppUnlockMethod.totp => authenticatorConfigured,
    AppUnlockMethod.sms => smsUnlockAvailable,
  };
}

/// A refused challenge. [code] is the server's own code and [attemptsLeft] is
/// present exactly when the server reported one — the UI never estimates.
@immutable
class AppUnlockRefusal implements Exception {
  const AppUnlockRefusal(this.code, {this.attemptsLeft, this.retryAfterMs});

  final String code;
  final int? attemptsLeft;
  final int? retryAfterMs;

  @override
  String toString() => 'AppUnlockRefusal($code)';
}

/// An issued SMS challenge. [maskedPhone] is the server's own mask; the client
/// never receives (and cannot reconstruct) the full number.
@immutable
class AppUnlockSmsChallenge {
  const AppUnlockSmsChallenge({
    required this.challengeId,
    required this.maskedPhone,
    this.expiresAt,
  });

  final String challengeId;
  final String maskedPhone;
  final String? expiresAt;
}

/// The gateway the app talks to. [ApiClient] is injected so tests can drive a
/// MockClient — and so demo mode keeps working through the same seam.
abstract class AppUnlockGateway {
  Future<AppUnlockCapabilities> capabilities();

  /// Returns normally only on an accepted PIN.
  Future<void> verifyPin(String pin);

  Future<void> verifyTotp(String token);

  Future<AppUnlockSmsChallenge> sendSmsChallenge();

  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  });
}

class HttpAppUnlockGateway implements AppUnlockGateway {
  HttpAppUnlockGateway(this._api);

  final ApiClient _api;

  static const String _base = '/security/app-unlock';

  /// JSON is UTF-8 whatever a proxy claims. The masked phone the server sends
  /// contains bullets, so decoding with the response's default latin1 would
  /// corrupt exactly the string we show the member.
  static Object? _decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    try {
      final response = await _api.get('$_base/capabilities');
      final decoded = _decode(response);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! Map<String, dynamic>) {
        throw const AppUnlockRefusal('CAPABILITIES_UNAVAILABLE');
      }
      return AppUnlockCapabilities.fromJson(data);
    } on ApiException catch (e) {
      throw _refusal(e, fallback: 'CAPABILITIES_UNAVAILABLE');
    }
  }

  @override
  Future<void> verifyPin(String pin) async {
    await _post('$_base/pin/verify', {'pin': pin}, fallback: 'PIN_REJECTED');
  }

  @override
  Future<void> verifyTotp(String token) async {
    await _post('$_base/totp/verify', {
      'token': token,
    }, fallback: 'TOTP_REJECTED');
  }

  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async {
    try {
      final response = await _api.post('$_base/sms/send', const {});
      final decoded = _decode(response);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      final id = data is Map<String, dynamic>
          ? data['challengeId']?.toString()
          : null;
      if (id == null || id.isEmpty) {
        throw const AppUnlockRefusal('UNLOCK_CHALLENGE_FAILED');
      }
      final map = data as Map<String, dynamic>;
      return AppUnlockSmsChallenge(
        challengeId: id,
        maskedPhone: map['maskedPhone']?.toString() ?? 'your phone',
        expiresAt: map['expiresAt']?.toString(),
      );
    } on ApiException catch (e) {
      throw _refusal(e, fallback: 'UNLOCK_CHALLENGE_FAILED');
    }
  }

  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {
    await _post('$_base/sms/verify', {
      'challengeId': challengeId,
      'code': code,
    }, fallback: 'CODE_INVALID');
  }

  Future<void> _post(
    String endpoint,
    Map<String, dynamic> body, {
    required String fallback,
  }) async {
    try {
      // The server answers 200 + { unlocked: true } or a refusal; a 2xx is the
      // only thing that counts, and there is no client-side "probably fine".
      await _api.post(endpoint, body);
    } on ApiException catch (e) {
      throw _refusal(e, fallback: fallback);
    }
  }

  AppUnlockRefusal _refusal(ApiException e, {required String fallback}) {
    final body = e.body;
    final code = e.code ?? body?['code']?.toString() ?? fallback;
    final attempts = body?['attemptsLeft'];
    final retry = body?['retryAfterMs'];
    return AppUnlockRefusal(
      code,
      attemptsLeft: attempts is int ? attempts : null,
      retryAfterMs: retry is int ? retry : null,
    );
  }
}
