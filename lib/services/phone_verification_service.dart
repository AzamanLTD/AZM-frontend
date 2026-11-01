import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'contact_service.dart' show kDefaultDialCode, normalizeToE164;

// =============================================================================
// AZAMAN — PHONE VERIFICATION (P8)
//
// Wires the EXISTING backend contract; no new endpoints are invented:
//
//   POST /api/security/phone/send-otp    { phoneNumber: '+233244123456' }
//   POST /api/security/phone/verify-otp  { phoneNumber, code }
//
// On verify the server re-hashes the number (HMAC + pepper), sets
// phoneVerified, and links any pre-registration vouches. That is the only
// moment the app may say a number is verified: this service never marks
// anything locally, and a UI state of "verified" is derived from the server's
// answer, not from having shown the code screen.
//
// ── THE HONESTY PROBLEM IN THE CURRENT BACKEND ───────────────────────────
//
// `SMSService.sendOTP` returns the generated code as `otp` when `isTestMode`
// is true, and the controller forwards it as `testOtp`. `isTestMode` is
// `NODE_ENV !== 'production'`. So in a NON-production build the response tells
// us plainly that no SMS was sent — and the app must say that too, not
// "check your phone". When `testOtp` is present we show the code and label the
// screen as test delivery.
//
// The reverse case is NOT detectable from here: with `SMS_PROVIDER=mock` in a
// production build, `isTestMode` is false, `sendSMS` only logs, and the
// response still claims "OTP sent successfully". The app cannot tell that
// apart from a real send, so it is recorded as a BACKEND defect for its own
// PR (refuse mock delivery in production; stop logging the code) rather than
// papered over with hedged copy here.
// =============================================================================

/// What actually happened when we asked for a code.
enum OtpSendStatus {
  /// The backend reported a send with no test code — it went to a provider.
  sent,

  /// The backend returned the code itself (`testOtp`): nothing was delivered
  /// over SMS. The UI must show this as test mode, with the code visible.
  testMode,

  /// The number is not a plausible E.164 number; never sent.
  invalidNumber,

  /// Rate limited or the code store is unavailable.
  throttled,

  /// Network/server failure. Not a delivery claim either way.
  failed,
}

@immutable
class OtpSendResult {
  const OtpSendResult({
    required this.status,
    this.message,
    this.expiresAt,
    this.testCode,
  });

  final OtpSendStatus status;
  final String? message;
  final DateTime? expiresAt;

  /// Present ONLY when the backend admitted it did not send an SMS.
  final String? testCode;

  bool get isDeliverable =>
      status == OtpSendStatus.sent || status == OtpSendStatus.testMode;
}

enum OtpVerifyStatus {
  /// The server accepted the code and marked the number verified.
  verified,

  /// The code was rejected. [OtpVerifyResult.attemptsLeft] may be known.
  rejected,

  /// The number was in a form the server refuses.
  invalidNumber,

  /// Network/server failure — the code may still be good, so do not burn it.
  failed,
}

@immutable
class OtpVerifyResult {
  const OtpVerifyResult({
    required this.status,
    this.message,
    this.attemptsLeft,
    this.phoneNumber,
  });

  final OtpVerifyStatus status;
  final String? message;
  final int? attemptsLeft;

  /// The number the SERVER confirmed, echoed from its own response.
  final String? phoneNumber;
}

class PhoneVerificationService {
  PhoneVerificationService._({ApiClient? api}) : _api = api ?? apiClient;

  static final PhoneVerificationService instance = PhoneVerificationService._();

  @visibleForTesting
  factory PhoneVerificationService.withClient(ApiClient api) =>
      PhoneVerificationService._(api: api);

  final ApiClient _api;

  /// Ask for a code. [rawPhone] may be a local number ("0244123456"); it is
  /// normalized to E.164 before it leaves the device, because the backend
  /// rejects anything else and a user should not have to know that.
  Future<OtpSendResult> sendOtp(
    String rawPhone, {
    String defaultDialCode = kDefaultDialCode,
  }) async {
    final e164 = normalizeToE164(rawPhone, defaultDialCode: defaultDialCode);
    if (e164 == null) {
      return const OtpSendResult(
        status: OtpSendStatus.invalidNumber,
        message: 'That does not look like a phone number.',
      );
    }

    http.Response res;
    try {
      res = await _api.post('/security/phone/send-otp', {'phoneNumber': e164});
    } on ApiException catch (e) {
      // ApiClient throws for every non-2xx, so the status lives on the
      // exception. 429 and 400 are different facts and must not be reported
      // as 'could not reach Azaman'.
      if (e.statusCode == 429) {
        return OtpSendResult(
          status: OtpSendStatus.throttled,
          message: e.message.isEmpty
              ? 'Too many attempts. Wait a minute.'
              : e.message,
        );
      }
      if (e.statusCode == 400 || e.statusCode == 422) {
        return OtpSendResult(
          status: OtpSendStatus.invalidNumber,
          message: e.message.isEmpty ? 'That number was refused.' : e.message,
        );
      }
      return OtpSendResult(
        status: OtpSendStatus.failed,
        message: e.message.isEmpty
            ? 'Could not send a code right now.'
            : e.message,
      );
    } catch (_) {
      return const OtpSendResult(
        status: OtpSendStatus.failed,
        message: 'Could not reach Azaman. Check your connection.',
      );
    }

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      /* non-JSON error page: handled by status below */
    }

    if (res.statusCode == 429) {
      return OtpSendResult(
        status: OtpSendStatus.throttled,
        message:
            body['message']?.toString() ?? 'Too many attempts. Wait a minute.',
      );
    }
    if (res.statusCode == 400) {
      return OtpSendResult(
        status: OtpSendStatus.invalidNumber,
        message: body['message']?.toString() ?? 'That number was refused.',
      );
    }
    if (res.statusCode != 200 || body['success'] != true) {
      return OtpSendResult(
        status: OtpSendStatus.failed,
        message:
            body['message']?.toString() ?? 'Could not send a code right now.',
      );
    }

    final expires = DateTime.tryParse(body['expiresAt']?.toString() ?? '');
    final testOtp = body['testOtp']?.toString();

    // The backend handing us the code means NO SMS left the building. Say so.
    if (testOtp != null && testOtp.isNotEmpty) {
      return OtpSendResult(
        status: OtpSendStatus.testMode,
        message: 'Test delivery: no SMS was sent.',
        expiresAt: expires,
        testCode: testOtp,
      );
    }

    return OtpSendResult(
      status: OtpSendStatus.sent,
      message: body['message']?.toString(),
      expiresAt: expires,
    );
  }

  /// Submit the code. Verification only counts when the SERVER says so.
  Future<OtpVerifyResult> verifyOtp(
    String rawPhone,
    String code, {
    String defaultDialCode = kDefaultDialCode,
  }) async {
    final e164 = normalizeToE164(rawPhone, defaultDialCode: defaultDialCode);
    if (e164 == null) {
      return const OtpVerifyResult(
        status: OtpVerifyStatus.invalidNumber,
        message: 'That does not look like a phone number.',
      );
    }
    final trimmed = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (trimmed.length < 4) {
      return const OtpVerifyResult(
        status: OtpVerifyStatus.rejected,
        message: 'Enter the code from the SMS.',
      );
    }

    http.Response res;
    try {
      res = await _api.post('/security/phone/verify-otp', {
        'phoneNumber': e164,
        'code': trimmed,
      });
    } on ApiException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 422) {
        // NOTE: the backend also returns `attemptsLeft`, but ApiClient's
        // ApiException carries only message/code/errors, so the count is
        // dropped in transit. The UI therefore shows the server's message and
        // does not invent an attempt counter. (Surfacing it needs a client or
        // backend change, tracked with the SMS-delivery defect.)
        return OtpVerifyResult(
          status: OtpVerifyStatus.rejected,
          message: e.message.isEmpty ? 'That code did not work.' : e.message,
        );
      }
      // 401/403/5xx/429: the code itself was not judged, so do not tell the
      // user it was wrong.
      return OtpVerifyResult(
        status: OtpVerifyStatus.failed,
        message: e.message.isEmpty
            ? 'Could not reach Azaman. Your code is still valid.'
            : e.message,
      );
    } catch (_) {
      return const OtpVerifyResult(
        status: OtpVerifyStatus.failed,
        message: 'Could not reach Azaman. Your code is still valid.',
      );
    }

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      /* ignored */
    }

    if (res.statusCode == 200 && body['success'] == true) {
      return OtpVerifyResult(
        status: OtpVerifyStatus.verified,
        // Echo the SERVER's number, not the one we typed.
        phoneNumber: body['phoneNumber']?.toString() ?? e164,
        message: body['message']?.toString(),
      );
    }

    if (res.statusCode == 400) {
      return OtpVerifyResult(
        status: OtpVerifyStatus.rejected,
        message: body['message']?.toString() ?? 'That code did not work.',
        attemptsLeft: body['attemptsLeft'] is int
            ? body['attemptsLeft'] as int
            : null,
      );
    }

    return OtpVerifyResult(
      status: OtpVerifyStatus.failed,
      message: body['message']?.toString() ?? 'Verification failed. Try again.',
    );
  }
}
