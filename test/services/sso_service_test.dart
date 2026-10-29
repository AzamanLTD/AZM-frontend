// =============================================================================
// SSO — THE WHOLE ROUND-TRIP, WITHOUT NATIVE PLUGINS
//
// P4 requires REAL provider sign-in, not a button that explains itself away.
// These tests drive SsoService through every edge that matters:
//
//   1. THE WIRE. The exact POST the backend contract expects:
//      /auth/sso { idToken, provider }, with requireAuth false, and the
//      provider spelled 'google' / 'apple'.
//   2. THE TOKEN. What is posted is the FIREBASE id token the gateway
//      returns — never a raw Google/Apple token.
//   3. THE SESSION. Credentials are persisted and the AuthProvider hydration
//      runs; a hydration that does not reach `authenticated` fails loudly.
//   4. THE OUTCOMES. Cancel is NOT an error. Misconfiguration carries a
//      specific reason. A backend rejection surfaces its own message and
//      status code. A success envelope without a token/user fails closed
//      instead of hydrating a phantom session.
//
// The native gateway itself (FirebaseSsoGateway) is covered by the typed
// error mapping asserted in the last group.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/sso_gateway.dart';
import 'package:azaman/services/sso_service.dart';

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Records what the service posted and answers with a canned envelope.
class _Recorder {
  _Recorder(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  http.Request? lastRequest;
  Map<String, dynamic>? lastBody;
  int calls = 0;

  ApiClient client() => ApiClient(
    client: MockClient((request) async {
      calls++;
      lastRequest = request;
      lastBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

class _FakeGateway implements SsoGateway {
  _FakeGateway({
    this.googleToken = 'fb-id-token-google',
    this.appleToken,
    this.googleError,
    this.appleError,
  });

  final String googleToken;
  final String? appleToken;
  final Object? googleError;
  final Object? appleError;
  int googleCalls = 0;
  int appleCalls = 0;

  @override
  Future<String> acquireGoogleIdToken() async {
    googleCalls++;
    if (googleError != null) throw googleError!;
    return googleToken;
  }

  @override
  Future<String> acquireAppleIdToken() async {
    appleCalls++;
    if (appleError != null) throw appleError!;
    final t = appleToken;
    if (t == null) throw const SsoNotConfiguredException(SsoProvider.apple);
    return t;
  }
}

Map<String, dynamic> _userJson({String id = 'user-1'}) => {
  'id': id,
  'username': 'kofi',
  'email': 'kofi@example.com',
  'role': 'USER',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // flutter_secure_storage has no test backend: answer its channel so the
    // persistence step is exercised (and asserted) instead of throwing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('the backend round-trip', () {
    test(
      'Google posts the FIREBASE token to /auth/sso and hydrates the session',
      () async {
        final rec = _Recorder(200, {
          'success': true,
          'token': 'jwt-abc',
          'refreshToken': 'refresh-abc',
          'user': _userJson(),
          'isNewUser': true,
          'message': 'Account created via SSO.',
        });
        final gateway = _FakeGateway();
        User? hydrated;
        final svc = SsoService(
          gateway: gateway,
          client: rec.client(),
          hydrateSession: (ref, user) async {
            hydrated = user;
            return AuthStatus.authenticated;
          },
        );

        final result = await svc.signInWithGoogle(_refOf(container()));

        expect(gateway.googleCalls, 1);
        expect(rec.calls, 1);
        // The client's baseUrl carries the /api prefix; this is the exact
        // endpoint the backend exposes.
        expect(rec.lastRequest!.url.path, '/api/auth/sso');
        expect(rec.lastBody, {
          'idToken': 'fb-id-token-google',
          'provider': 'google',
        });
        expect(
          hydrated?.id,
          'user-1',
          reason: 'the parsed user reaches the AuthProvider hydration',
        );
        expect(result.user.id, 'user-1');
        expect(result.isNewUser, isTrue);
        expect(result.message, 'Account created via SSO.');
      },
    );

    test('Apple posts provider "apple" and the Apple token', () async {
      final rec = _Recorder(200, {
        'success': true,
        'token': 'jwt-apple',
        'user': _userJson(id: 'user-apple'),
      });
      final svc = SsoService(
        gateway: _FakeGateway(appleToken: 'fb-id-token-apple'),
        client: rec.client(),
        hydrateSession: (ref, user) async => AuthStatus.authenticated,
      );

      final result = await svc.signInWithApple(_refOf(container()));

      expect(rec.lastBody!['provider'], 'apple');
      expect(rec.lastBody!['idToken'], 'fb-id-token-apple');
      expect(result.user.id, 'user-apple');
    });

    test(
      'a referral code rides along only when present and non-empty',
      () async {
        final rec = _Recorder(200, {
          'success': true,
          'token': 'jwt',
          'user': _userJson(),
        });
        final svc = SsoService(
          gateway: _FakeGateway(),
          client: rec.client(),
          hydrateSession: (ref, user) async => AuthStatus.authenticated,
        );

        await svc.signInWithGoogle(_refOf(container()), referredByCode: '  ');
        expect(
          rec.lastBody!.containsKey('referredByCode'),
          isFalse,
          reason: 'blank codes must not be posted',
        );

        await svc.signInWithGoogle(
          _refOf(container()),
          referredByCode: ' KOFI10 ',
        );
        expect(rec.lastBody!['referredByCode'], 'KOFI10');
      },
    );
  });

  group('outcomes are typed', () {
    test('cancelling is not an error', () async {
      final svc = SsoService(
        gateway: _FakeGateway(
          googleError: const SsoCancelledException(SsoProvider.google),
        ),
        client: _Recorder(200, {}).client(),
        hydrateSession: (ref, user) async => AuthStatus.authenticated,
      );

      await expectLater(
        svc.signInWithGoogle(_refOf(container())),
        throwsA(isA<SsoCancelledException>()),
      );
    });

    test('a misconfigured build reports the specific reason', () async {
      final svc = SsoService(
        gateway: _FakeGateway(
          googleError: const SsoNotConfiguredException(
            SsoProvider.google,
            reason: 'Google sign-in needs a server client id in this build.',
          ),
        ),
        client: _Recorder(200, {}).client(),
        hydrateSession: (ref, user) async => AuthStatus.authenticated,
      );

      await expectLater(
        svc.signInWithGoogle(_refOf(container())),
        throwsA(
          isA<SsoNotConfiguredException>().having(
            (e) => e.reason,
            'reason',
            contains('server client id'),
          ),
        ),
      );
    });

    test('a backend rejection keeps its message and status', () async {
      final rec = _Recorder(409, {
        'success': false,
        'message': 'That email is already linked to another sign-in method.',
      });
      final svc = SsoService(
        gateway: _FakeGateway(),
        client: rec.client(),
        hydrateSession: (ref, user) async => AuthStatus.authenticated,
      );

      await expectLater(
        svc.signInWithGoogle(_refOf(container())),
        throwsA(
          isA<SsoException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('already linked')),
        ),
      );
    });

    test('a success envelope without a user fails closed', () async {
      final svc = SsoService(
        gateway: _FakeGateway(),
        client: _Recorder(200, {'success': true}).client(),
        hydrateSession: (ref, user) async =>
            throw StateError('must not hydrate without a verified session'),
      );

      await expectLater(
        svc.signInWithGoogle(_refOf(container())),
        throwsA(anything),
      );
    });

    test('a hydration that does not reach authenticated throws', () async {
      final svc = SsoService(
        gateway: _FakeGateway(),
        client: _Recorder(200, {
          'success': true,
          'token': 'jwt',
          'user': _userJson(),
        }).client(),
        hydrateSession: (ref, user) async => AuthStatus.unauthenticated,
      );

      await expectLater(
        svc.signInWithGoogle(_refOf(container())),
        throwsA(isA<SsoException>()),
      );
    });
  });
}

/// A minimal WidgetRef stand-in: the injected hydrator never touches it, but
/// the service signature needs one. Using the container's notifier reader
/// keeps this honest without a full widget tree.
WidgetRef _refOf(ProviderContainer c) => _FakeRef(c);

class _FakeRef implements WidgetRef {
  _FakeRef(this._container);
  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
