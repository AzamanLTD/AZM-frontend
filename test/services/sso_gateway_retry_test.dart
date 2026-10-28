// =============================================================================
// SSO GATEWAY — THE TWO DEFECTS THAT BROKE REAL SIGN-IN (2026-10-28)
//
// Both bugs below made a REAL provider sign-in fail in ways the old suite
// could not see, because they live inside the native gateway rather than in
// the wire contract:
//
//   1. FIREBASE PRE-FLIGHT LATCHED ITS OWN FAILURE. The "already checked"
//      flag was set BEFORE initialisation was attempted, so one transient
//      failure (plugin not attached on a cold start, flaky network) left the
//      gateway permanently convinced it was ready. Every retry returned
//      early with Firebase never initialised, so the user saw the same
//      "try again" error forever.
//      PINNED HERE: a failed pre-flight leaves the gateway retryable; the
//      retry actually re-runs initialisation; success is stable afterwards.
//
//   2. APPLE'S authorizationCode WAS SENT AS AN ACCESS TOKEN. That code is a
//      one-time authorization code for Apple's own token endpoint, not an
//      access token, so the Firebase exchange was at best meaningless and at
//      worst a rejection. Firebase verifies Apple sign-ins from the identity
//      token plus the raw nonce, so the access token must be ABSENT.
//      PINNED HERE: the credential carries the id token and raw nonce and
//      no access token at all.
// =============================================================================
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/services/sso_gateway.dart';
import 'package:azaman/services/sso_service.dart';

void main() {
  group('Firebase pre-flight is RETRYABLE, not latching', () {
    test('1. a transient failure surfaces a retryable error, and the next '
        'call genuinely retries initialisation', () async {
      var calls = 0;
      var present = false;
      final gateway = FirebaseSsoGateway(
        initializeFirebase: () async {
          calls++;
          if (calls == 1) {
            throw Exception('plugin not attached yet');
          }
          present = true;
        },
        firebaseAppsPresent: () => present,
      );

      // First attempt fails, and fails as RETRYABLE — never as
      // "this build is not configured".
      await expectLater(
        gateway.ensureFirebase(),
        throwsA(
          isA<SsoException>().having(
            (e) => e is SsoNotConfiguredException,
            'is a misconfiguration claim',
            isFalse,
          ),
        ),
      );
      expect(calls, 1);

      // The retry must actually attempt initialisation again — this is the
      // exact behaviour the latched flag destroyed.
      await gateway.ensureFirebase();
      expect(calls, 2);
      expect(present, isTrue);

      // And success is stable: no further initialisation attempts.
      await gateway.ensureFirebase();
      expect(calls, 2);
    });

    test('2. a pre-flight that keeps failing stays retryable every time', () async {
      var calls = 0;
      final gateway = FirebaseSsoGateway(
        initializeFirebase: () async {
          calls++;
          throw Exception('still down');
        },
        firebaseAppsPresent: () => false,
      );

      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(
          gateway.ensureFirebase(),
          throwsA(isA<SsoException>()),
        );
      }
      expect(
        calls,
        3,
        reason: 'every attempt must reach initialisation, not be skipped',
      );
    });

    test('3. an already-initialised Firebase is never re-initialised', () async {
      var calls = 0;
      final gateway = FirebaseSsoGateway(
        initializeFirebase: () async => calls++,
        firebaseAppsPresent: () => true,
      );

      await gateway.ensureFirebase();
      await gateway.ensureFirebase();
      expect(calls, 0);
    });
  });

  group('the Apple credential', () {
    test('4. carries the identity token and raw nonce, and NO access token', () {
      final credential = buildAppleCredential(
        idToken: 'apple.identity.token',
        rawNonce: 'raw-nonce-value',
      );

      expect(credential.providerId, 'apple.com');
      expect(credential.idToken, 'apple.identity.token');
      expect(credential.rawNonce, 'raw-nonce-value');
      expect(
        credential.accessToken,
        isNull,
        reason: 'Apple authorizationCode is NOT an access token',
      );
    });

    test('5. two calls do not share state (a fresh credential each time)', () {
      final a = buildAppleCredential(idToken: 'one', rawNonce: 'n1');
      final b = buildAppleCredential(idToken: 'two', rawNonce: 'n2');
      expect(identical(a, b), isFalse);
      expect(a.idToken, 'one');
      expect(b.idToken, 'two');
      expect(b.accessToken, isNull);
    });
  });
}
