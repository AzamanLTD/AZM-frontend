// =============================================================================
// AZAMAN — SSO SERVICE  (Phase F)
//
// Backend contract (verified against azaman-backend-main):
//
//   POST /api/auth/sso
//   body: { idToken: string, provider: 'google' | 'apple', referredByCode? }
//
//   The backend verifies the idToken via firebase-admin
//   (`admin.auth().verifyIdToken`) and either auto-creates the user or
//   links the provider to an existing email-matched account, returning
//   the standard `{ token, user }` payload.
//
// WHAT IS LIVE NOW
//
//   Real provider sign-in. `FirebaseSsoGateway` (lib/services/sso_gateway.dart)
//   runs the native Google / Apple flows and exchanges the provider credential
//   through FirebaseAuth into a FIREBASE id token, which is the exact thing
//   this service posts. There is no longer a "not configured" stub on the
//   happy path: the only ways to reach SsoNotConfiguredException are a genuine
//   missing native client (owner-only config, reported with a specific reason)
//   or a platform that cannot do the provider at all.
//
// WHAT THIS SERVICE OWNS
//
//   1. Token acquisition through the injected [SsoGateway].
//   2. The backend contract: POST /api/auth/sso { idToken, provider,
//      referredByCode? } — verified against azaman-backend.
//   3. Credential persistence (auth_token / refresh_token / user_id /
//      user_role) and AuthProvider hydration, identical to email login.
//
// OUTCOMES ARE TYPED, NEVER SILENT
//
//   SsoCancelledException   the user dismissed the provider sheet — the login
//                           screen just resets, no error banner.
//   SsoNotConfiguredException  this build/platform cannot do the provider;
//                           carries a human reason for the dialog.
//   SsoException            anything else (network, backend rejection,
//                           unverifiable token) with a user-facing message.
//
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/sso_gateway.dart';

/// Identifies the SSO provider the user picked.
enum SsoProvider {
  google,
  apple;

  /// Backend wire format. The /api/auth/sso endpoint expects exactly
  /// the lowercase strings 'google' or 'apple'.
  String get wire => name;
}

/// The result of a successful SSO round-trip.
class SsoResult {
  final User user;
  final bool isNewUser;
  final String message;

  const SsoResult({
    required this.user,
    required this.isNewUser,
    required this.message,
  });
}

/// Thrown when this BUILD (or platform) genuinely cannot complete the
/// provider flow: no OAuth client for the app's signing key, provider disabled
/// in the Firebase project, Apple not enabled for the App ID, or a platform
/// that has no Apple flow. Carries a specific, user-explainable [reason] —
/// never a generic "something went wrong" and never a fake success.
class SsoNotConfiguredException implements Exception {
  final SsoProvider provider;

  /// One plain sentence a user can act on (or hand to support verbatim).
  final String reason;

  const SsoNotConfiguredException(
    this.provider, {
    this.reason = 'Sign-in with this provider is not available in this build.',
  });

  @override
  String toString() => 'SSO unavailable for ${provider.name}: $reason';
}

/// Thrown when the user dismisses the provider sheet. NOT an error: the login
/// screen resets its loading state and shows nothing.
class SsoCancelledException implements Exception {
  final SsoProvider provider;
  const SsoCancelledException(this.provider);

  @override
  String toString() => 'SSO cancelled for ${provider.name}.';
}

/// Generic failure during the SSO exchange (network, server rejection,
/// invalid token, etc.). Carries a user-facing message.
class SsoException implements Exception {
  final String message;
  final int? statusCode;

  const SsoException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class SsoService {
  /// [gateway] is the native provider boundary — the real one by default, a
  /// fake in tests. [client] and [hydrateSession] exist for the same reason:
  /// every external edge of this service is injectable, so the whole
  /// round-trip can be exercised without native plugins or a live backend.
  SsoService({
    SsoGateway? gateway,
    ApiClient? client,
    SessionHydrator? hydrateSession,
  }) : _gateway = gateway ?? FirebaseSsoGateway(),
       _client = client,
       _hydrateSession = hydrateSession;

  final SsoGateway _gateway;
  final ApiClient? _client;
  final SessionHydrator? _hydrateSession;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient get _api => _client ?? apiClient;

  /// Sign in via Google. See file header for the wiring contract and
  /// the future-replacement instructions for the idToken acquisition.
  Future<SsoResult> signInWithGoogle(WidgetRef ref, {String? referredByCode}) {
    return _signIn(ref, SsoProvider.google, referredByCode: referredByCode);
  }

  /// Sign in via Apple. See file header for the wiring contract and
  /// the future-replacement instructions for the idToken acquisition.
  Future<SsoResult> signInWithApple(WidgetRef ref, {String? referredByCode}) {
    return _signIn(ref, SsoProvider.apple, referredByCode: referredByCode);
  }

  // ── Internal flow ─────────────────────────────────────────────────────────

  Future<SsoResult> _signIn(
    WidgetRef ref,
    SsoProvider provider, {
    String? referredByCode,
  }) async {
    // Step 1 — acquire a FIREBASE id token from the chosen provider. The
    // gateway owns the native flow; this service never talks to Google or
    // Apple directly.
    final idToken = provider == SsoProvider.google
        ? await _gateway.acquireGoogleIdToken()
        : await _gateway.acquireAppleIdToken();

    // Step 2 — POST to the backend's single SSO endpoint. The backend
    // verifies the token and returns the standard auth payload.
    final body = <String, dynamic>{
      'idToken': idToken,
      'provider': provider.wire,
    };
    if (referredByCode != null && referredByCode.trim().isNotEmpty) {
      body['referredByCode'] = referredByCode.trim();
    }

    late final dynamic data;
    try {
      final response = await _api.post('/auth/sso', body, requireAuth: false);
      data = jsonDecode(response.body);
    } on ApiException catch (e) {
      throw SsoException(e.message, statusCode: e.statusCode);
    } catch (e) {
      throw SsoException('Network error during SSO: $e');
    }

    if (data is! Map<String, dynamic> || data['success'] != true) {
      final message = (data is Map<String, dynamic>)
          ? (data['message']?.toString() ?? 'SSO failed.')
          : 'SSO failed.';
      throw SsoException(message);
    }

    // Step 3 — parse + persist credentials, mirror what login_screen does
    // for email/password so the rest of the app behaves identically.
    final String token =
        (data['token'] ??
                data['data']?['token'] ??
                data['user']?['token'] ??
                '')
            .toString();

    final Map<String, dynamic> u = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : (data['data']?['user'] is Map<String, dynamic>
              ? data['data']!['user'] as Map<String, dynamic>
              : <String, dynamic>{});

    final user = User.fromJson({...u, 'token': token});

    final ssoRefreshToken =
        (data['refreshToken'] ?? data['data']?['refreshToken'])?.toString();
    await _storage.write(key: 'auth_token', value: user.token);
    if (ssoRefreshToken != null && ssoRefreshToken.isNotEmpty) {
      await _storage.write(key: 'refresh_token', value: ssoRefreshToken);
    }
    await _storage.write(key: 'user_id', value: user.id);
    await _storage.write(key: 'user_role', value: user.role.toLowerCase());

    // Step 4 — hydrate the auth provider (this calls /auth/me/:id internally
    // and flips status to authenticated). We don't strictly need to await
    // the resulting AuthStatus here because the login screen rebuilds on
    // its own once the provider notifies, but we await so callers can
    // distinguish a successful login from a phantom-user case.
    final authStatus =
        await (_hydrateSession ??
            (WidgetRef r, User u) =>
                r.read(authProvider).setSessionFromLogin(u))(ref, user);

    if (authStatus != AuthStatus.authenticated) {
      throw SsoException(
        ref.read(authProvider).error ??
            'Could not load your profile after SSO. Please try again.',
      );
    }

    return SsoResult(
      user: user,
      isNewUser: data['isNewUser'] == true,
      message:
          data['message']?.toString() ??
          (data['isNewUser'] == true
              ? 'Account created via SSO.'
              : 'Login successful.'),
    );
  }
}

/// Turns a parsed [User] into an authenticated session. Defaults to the real
/// AuthProvider hydration; tests supply a deterministic stand-in so the
/// backend exchange and the session step can be asserted independently.
typedef SessionHydrator = Future<AuthStatus> Function(WidgetRef ref, User user);

/// Riverpod handle. Use `ref.read(ssoServiceProvider).signInWithGoogle(ref)`
/// from any ConsumerWidget / ConsumerStatefulWidget.
final ssoServiceProvider = Provider<SsoService>((ref) => SsoService());
