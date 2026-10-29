// =============================================================================
// AZAMAN — SSO GATEWAY  (the native provider boundary)
//
// WHY THIS FILE EXISTS
//
// `SsoService` owns the backend contract (POST /api/auth/sso) and the session
// hydration. Everything that touches a NATIVE sign-in SDK lives here, behind
// one small interface, so that:
//
//   • the real providers can be wired without the service knowing about
//     GoogleSignIn / SignInWithApple / FirebaseAuth,
//   • tests can drive every outcome (success, cancel, misconfiguration,
//     provider rejection) without native plugins or a device,
//   • a platform that cannot do a given provider fails with a typed,
//     user-explainable error instead of an opaque crash.
//
// THE CONTRACT. Both providers end at the SAME place: a FIREBASE ID TOKEN.
// The backend verifies exactly that (`admin.auth().verifyIdToken`), so the
// gateway always exchanges the provider credential through FirebaseAuth and
// returns `getIdToken()`. A raw Google or Apple token is never posted.
//
//   Google : GoogleSignIn.authenticate() → google idToken
//            → GoogleAuthProvider.credential → signInWithCredential
//            → getIdToken()
//
//   Apple  : SignInWithApple.getAppleIDCredential(nonce: sha256(rawNonce))
//            → identityToken + authorizationCode
//            → OAuthProvider('apple.com').credential(rawNonce: rawNonce)
//            → signInWithCredential → getIdToken()
//
// The Apple nonce is generated per attempt, hashed for the request and sent
// raw to Firebase, which is what makes the exchange replay-proof: the backend
// then verifies the Firebase token, not our nonce.
//
// OWNER-ONLY CONFIGURATION (cannot be done from code):
//   • Android: an OAuth client for this app's package + signing SHA-1 in the
//     Google Cloud project behind google-services.json, and for idToken
//     issuance the WEB client id passed as --dart-define=GOOGLE_SERVER_CLIENT_ID.
//   • iOS: the reversed client id URL scheme in Info.plist, and the
//     "Sign in with Apple" capability on the App ID + provisioning profile.
//   • Firebase: Google and Apple sign-in providers enabled in the console.
// Missing pieces surface as SsoNotConfiguredException with a specific reason,
// never as a silent failure or a fake success.
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:azaman/services/sso_service.dart'
    show
        SsoCancelledException,
        SsoException,
        SsoNotConfiguredException,
        SsoProvider;

/// Builds the Firebase credential for an Apple sign-in.
///
/// APPLE TOKEN BUG (fixed 2026-10-28). This used to pass
/// `credential.authorizationCode` as `accessToken`. That code is a one-time
/// authorization code for Apple's own token endpoint, NOT an access token:
/// handing it to Firebase made the exchange marginally valid at best and
/// usually a confusing rejection. Firebase verifies Apple sign-ins from the
/// identity token plus the raw nonce alone, so the access token is omitted
/// entirely rather than filled with the wrong thing.
///
/// Kept as a named function so the contract can be asserted directly:
/// the credential must carry the id token and raw nonce, and no access token.
OAuthCredential buildAppleCredential({
  required String idToken,
  required String rawNonce,
}) {
  return OAuthProvider(
    'apple.com',
  ).credential(idToken: idToken, rawNonce: rawNonce);
}

/// The native provider boundary.
abstract class SsoGateway {
  /// Returns a FIREBASE id token for a completed Google sign-in.
  Future<String> acquireGoogleIdToken();

  /// Returns a FIREBASE id token for a completed Apple sign-in.
  Future<String> acquireAppleIdToken();
}

/// The real gateway: Google + Apple through their native SDKs, exchanged
/// through FirebaseAuth into a Firebase id token.
class FirebaseSsoGateway implements SsoGateway {
  FirebaseSsoGateway({
    /// The web OAuth client id used for Google idToken issuance on Android.
    /// Supplied at build time: --dart-define=GOOGLE_SERVER_CLIENT_ID=...
    /// Empty is legal (iOS and web read it from the native config file);
    /// Android then reports a specific not-configured reason instead of
    /// returning a token-less success.
    this.serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '',
    ),
    Future<void> Function()? initializeFirebase,
    bool Function()? firebaseAppsPresent,
  }) : _initializeFirebase =
           initializeFirebase ??
           (() async {
             await Firebase.initializeApp();
           }),
       _firebaseAppsPresent =
           firebaseAppsPresent ?? (() => Firebase.apps.isNotEmpty);

  final String serverClientId;

  /// Seams for the Firebase pre-flight, so its retry contract can be tested
  /// without a real native Firebase plugin. Production uses the defaults.
  final Future<void> Function() _initializeFirebase;
  final bool Function() _firebaseAppsPresent;

  bool _googleInitialized = false;
  bool _firebaseReady = false;

  /// Firebase must exist before any credential exchange. The app initialises
  /// it during startup; this is the defensive path for the login screen being
  /// the first thing that runs (deep link straight to /login).
  ///
  /// RETRY-AFTER-FAILURE (fixed 2026-10-28). This used to set its "checked"
  /// flag BEFORE attempting initialisation, so a single transient failure
  /// (plugin not attached yet, cold start, flaky network) permanently
  /// poisoned the gateway: every later attempt returned early, Firebase was
  /// never initialised, and the user kept seeing the same "try again" error
  /// that could never succeed. The flag is now set only AFTER Firebase is
  /// actually available, so a retry genuinely retries.
  Future<void> ensureFirebase() async {
    if (_firebaseReady) return;
    if (_firebaseAppsPresent()) {
      _firebaseReady = true;
      return;
    }
    try {
      await _initializeFirebase();
      _firebaseReady = true;
    } catch (_) {
      // Stay un-ready: the next attempt retries instead of failing forever.
      _firebaseReady = false;
      throw const SsoException(
        'Could not reach the sign-in service on this build. '
        'Please try again in a moment.',
      );
    }
  }

  /// Google's plugin initialisation, with the same retry rule: a transient
  /// failure is NOT "this build has no Google client", so it must not be
  /// reported as one, and it must not latch a permanent failure.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final hasClientId = serverClientId.trim().isNotEmpty;
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: hasClientId ? serverClientId.trim() : null,
      );
      _googleInitialized = true;
    } catch (e) {
      // A genuine configuration failure is only provable when no client id
      // was supplied at all; anything else is retryable.
      if (!hasClientId) {
        throw const SsoNotConfiguredException(
          SsoProvider.google,
          reason: 'This build has no Google sign-in client configured.',
        );
      }
      throw const SsoException(
        'Google sign-in could not start. Please try again in a moment.',
      );
    }
  }

  @override
  Future<String> acquireGoogleIdToken() async {
    await ensureFirebase();
    await _ensureGoogleInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SsoCancelledException(SsoProvider.google);
      }
      throw const SsoException(
        'Google sign-in did not complete. Please try again.',
      );
    } catch (e) {
      // PlatformException surfaces here when the OAuth client for this
      // package + signing key is missing. That is configuration, not user
      // error — say so plainly.
      throw const SsoNotConfiguredException(
        SsoProvider.google,
        reason: 'Google sign-in is not configured for this build.',
      );
    }

    final String? googleIdToken = account.authentication.idToken;
    if (googleIdToken == null || googleIdToken.isEmpty) {
      // Authentication succeeded but no id_token was issued: the project has
      // no web/server client id for this app. Firebase needs it.
      throw const SsoNotConfiguredException(
        SsoProvider.google,
        reason: 'Google sign-in needs a server client id in this build.',
      );
    }

    return _exchangeWithFirebase(
      () => FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: googleIdToken),
      ),
      SsoProvider.google,
    );
  }

  @override
  Future<String> acquireAppleIdToken() async {
    await ensureFirebase();

    if (kIsWeb) {
      throw const SsoNotConfiguredException(
        SsoProvider.apple,
        reason: 'Apple sign-in is not available on the web build.',
      );
    }

    // Per-attempt nonce: hashed for Apple, raw for Firebase. This is what
    // stops a captured Apple token from being replayed against our backend.
    final rawNonce = _randomNonce();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SsoCancelledException(SsoProvider.apple);
      }
      if (e.code == AuthorizationErrorCode.notHandled ||
          e.code == AuthorizationErrorCode.notInteractive) {
        throw const SsoNotConfiguredException(
          SsoProvider.apple,
          reason: 'Apple sign-in is not enabled for this build.',
        );
      }
      throw const SsoException(
        'Apple sign-in did not complete. Please try again.',
      );
    } catch (e) {
      throw const SsoNotConfiguredException(
        SsoProvider.apple,
        reason: 'Apple sign-in is not enabled for this build.',
      );
    }

    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw const SsoNotConfiguredException(
        SsoProvider.apple,
        reason: 'Apple did not return an identity token for this build.',
      );
    }

    return _exchangeWithFirebase(
      () => FirebaseAuth.instance.signInWithCredential(
        buildAppleCredential(idToken: identityToken, rawNonce: rawNonce),
      ),
      SsoProvider.apple,
    );
  }

  /// Exchanges a provider credential for a Firebase id token, mapping the
  /// auth-side rejections that actually mean "this build is misconfigured"
  /// apart from the ones that mean "the server said no".
  Future<String> _exchangeWithFirebase(
    Future<UserCredential> Function() exchange,
    SsoProvider provider,
  ) async {
    final UserCredential result;
    try {
      result = await exchange();
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('operation-not-allowed') ||
          code.contains('invalid-credential') ||
          code.contains('invalid-api-key') ||
          code.contains('app-not-authorized')) {
        throw SsoNotConfiguredException(
          provider,
          reason: '${_label(provider)} sign-in is not enabled for this build.',
        );
      }
      if (code.contains('network')) {
        throw const SsoException(
          'No connection to the sign-in service. Check your network.',
        );
      }
      throw SsoException(
        '${_label(provider)} sign-in was rejected. Please try another way.',
      );
    } catch (e) {
      throw SsoException(
        '${_label(provider)} sign-in could not be completed. Please try again.',
      );
    }

    final user = result.user;
    if (user == null) {
      throw SsoException(
        '${_label(provider)} sign-in returned no account. Please try again.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw SsoException(
        'Could not confirm your ${_label(provider)} session. Please try again.',
      );
    }
    return token;
  }

  static String _label(SsoProvider p) =>
      p == SsoProvider.google ? 'Google' : 'Apple';

  static String _randomNonce([int bytes = 32]) {
    final rnd = Random.secure();
    final values = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
