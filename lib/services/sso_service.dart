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
// What this service does today:
//
//   1. Exposes `signInWithGoogle()` / `signInWithApple()` entry points.
//   2. Each entry point delegates to `_acquireFirebaseIdToken(provider)`
//      to obtain a Firebase ID token.
//   3. POSTs `{ idToken, provider }` to /api/auth/sso via the central
//      apiClient (so timeouts, ngrok header, error mapping all behave
//      consistently with the rest of the app).
//   4. Hydrates the `AuthProvider` via `setSessionFromLogin` so the
//      whole app picks up the fresh session immediately — same path
//      email/password login uses.
//
// What is intentionally STUBBED — and why:
//
//   The Flutter pubspec currently includes `firebase_core` and
//   `firebase_messaging` but NOT `firebase_auth`, `google_sign_in`, or
//   `sign_in_with_apple`. Adding those packages requires native
//   configuration we don't ship in this PR (Apple Sign-In capability,
//   Google OAuth client IDs, GoogleService-Info.plist scopes). To keep
//   the build healthy and the wiring honest, `_acquireFirebaseIdToken`
//   throws `SsoNotConfiguredException` for now. The login screen
//   catches this and shows a clean, copy-driven dialog explaining what
//   the user can do (use email/password) and what ops needs to do
//   (add the SDKs + native config) for SSO to go live.
//
//   When the SDK + config drop lands, replace the body of
//   `_acquireFirebaseIdToken` with:
//
//     // GOOGLE
//     final account = await GoogleSignIn().signIn();
//     final auth    = await account!.authentication;
//     final cred    = GoogleAuthProvider.credential(
//                       idToken:     auth.idToken,
//                       accessToken: auth.accessToken,
//                     );
//     final user    = await FirebaseAuth.instance.signInWithCredential(cred);
//     return await user.user!.getIdToken();
//
//     // APPLE
//     final cred = await SignInWithApple.getAppleIDCredential(scopes: [
//                    AppleIDAuthorizationScopes.email,
//                    AppleIDAuthorizationScopes.fullName,
//                  ]);
//     final oauth = OAuthProvider('apple.com').credential(
//                     idToken:     cred.identityToken,
//                     accessToken: cred.authorizationCode,
//                   );
//     final user = await FirebaseAuth.instance.signInWithCredential(oauth);
//     return await user.user!.getIdToken();
//
//   No other code in this file changes. The login-screen wiring, the
//   apiClient call, the AuthProvider hydration, the success/error
//   surfaces — all of it is already in place.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';

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

/// Thrown when the native Firebase Auth SDK + provider plugins aren't
/// available in the current build. Caught by the login screen to render
/// a clean explanatory dialog instead of a generic error toast.
class SsoNotConfiguredException implements Exception {
  final SsoProvider provider;
  const SsoNotConfiguredException(this.provider);

  @override
  String toString() =>
      'SSO is not yet configured for ${provider.name}. '
      'Add firebase_auth + the provider SDK and re-run.';
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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Sign in via Google. See file header for the wiring contract and
  /// the future-replacement instructions for the idToken acquisition.
  Future<SsoResult> signInWithGoogle(WidgetRef ref,
      {String? referredByCode}) {
    return _signIn(ref, SsoProvider.google, referredByCode: referredByCode);
  }

  /// Sign in via Apple. See file header for the wiring contract and
  /// the future-replacement instructions for the idToken acquisition.
  Future<SsoResult> signInWithApple(WidgetRef ref,
      {String? referredByCode}) {
    return _signIn(ref, SsoProvider.apple, referredByCode: referredByCode);
  }

  // ── Internal flow ─────────────────────────────────────────────────────────

  Future<SsoResult> _signIn(
    WidgetRef ref,
    SsoProvider provider, {
    String? referredByCode,
  }) async {
    // Step 1 — acquire a Firebase ID token from the chosen provider.
    final idToken = await _acquireFirebaseIdToken(provider);

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
      final response = await apiClient.post(
        '/auth/sso',
        body,
        requireAuth: false,
      );
      data = jsonDecode(response.body);
    } on ApiException catch (e) {
      throw SsoException(
        e.message,
        statusCode: e.statusCode,
      );
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
    final String token = (data['token'] ??
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

    final ssoRefreshToken = (data['refreshToken'] ?? data['data']?['refreshToken'])?.toString();
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
        await ref.read(authProvider).setSessionFromLogin(user);

    if (authStatus != AuthStatus.authenticated) {
      throw SsoException(
        ref.read(authProvider).error ??
            'Could not load your profile after SSO. Please try again.',
      );
    }

    return SsoResult(
      user: user,
      isNewUser: data['isNewUser'] == true,
      message: data['message']?.toString() ??
          (data['isNewUser'] == true
              ? 'Account created via SSO.'
              : 'Login successful.'),
    );
  }

  /// Acquires a Firebase ID token from the chosen provider.
  ///
  /// Today this is intentionally a typed throw — see file header.
  /// When firebase_auth + google_sign_in / sign_in_with_apple ship,
  /// replace this body with the platform-branched flow described above.
  Future<String> _acquireFirebaseIdToken(SsoProvider provider) async {
    if (kDebugMode) {
      debugPrint(
          '[SSO] _acquireFirebaseIdToken(${provider.name}) — native SDK not configured.');
    }
    throw SsoNotConfiguredException(provider);
  }
}

/// Riverpod handle. Use `ref.read(ssoServiceProvider).signInWithGoogle(ref)`
/// from any ConsumerWidget / ConsumerStatefulWidget.
final ssoServiceProvider = Provider<SsoService>((ref) => SsoService());
