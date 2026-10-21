// IDENTITY BOUNDARIES — review follow-up pins.
//
// The review item: balanceDataProvider / userUsdcBalanceProvider /
// balanceReadinessProvider must reset on logout and identity change in
// AuthProvider (setSessionFromLogin, fetchUserDetails invalid-profile
// paths, logout); the last confirmed balance is preserved ONLY for the
// same identity on refresh failure; a stale async response for an old
// identity must not overwrite the new identity's state; the delta
// baseline re-anchors at the hydration boundary (readiness gating in the
// card already handles that once readiness returns to `unresolved`).
//
// Pins below assert the provider state directly after each boundary.

import 'dart:convert';

import 'dart:async';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:azaman/services/api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// A provider whose value is its own Ref — lets tests hand a live
// container Ref to a directly-constructed AuthProvider / refresh call.
final _refProbe = Provider<Ref>((r) => r);

Map<String, dynamic> _profileJson(String id, double available) => {
      'user': {
        'id': id,
        'username': 'user-$id',
        'email': '$id@example.com',
        'role': 'USER',
        'availableBalance': available,
      }
    };

User _loginUser(String id) => User.fromJson({
      'id': id,
      'username': 'user-$id',
      'email': '$id@example.com',
      'token': 'tok-$id',
      'role': 'USER',
    });

/// Storage mock for the auth tests: the socket path must stay inert, so
/// auth_token reads return null (SocketService._connect bails without a
/// token). The refresh tests pass [withToken] to arm the refresh path.
void _mockSecureStorage({String? token}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    switch (call.method) {
      case 'read':
        final key = call.arguments['key'];
        return key == 'auth_token' ? token : null;
      case 'delete':
        return null;
      default:
        return null;
    }
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    balanceRefreshClientOverride = null;
  });

  group('AuthProvider identity boundaries', () {
    test('logout resets readiness, balance, USDC projection, and bumps '
        'the epoch', () async {
      _mockSecureStorage(token: null);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      var meStatus = 200;
      late http.Client client;
      client = MockClient((request) async {
        if (request.url.path.contains('/auth/me/')) {
          return meStatus == 200
              ? http.Response(jsonEncode(_profileJson('u1', 120.5)), 200)
              : http.Response(jsonEncode({'message': 'nope'}), meStatus);
        }
        if (request.url.path.contains('/auth/logout')) {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        return http.Response(jsonEncode({'message': 'boom'}), 500);
      });

      final auth = AuthProvider(ref: ref, client: ApiClient(client: client));
      AuthGuard.isAuthenticated = false;
      await auth.setSessionFromLogin(_loginUser('u1'));
      await _pump();

      // Authoritative hydration landed for u1.
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded,
          reason: 'successful /auth/me must mark the balance loaded');
      expect(container.read(balanceDataProvider).availableBalance, 120.5);
      final epochBefore = container.read(balanceEpochProvider);

      await auth.logout();

      expect(auth.status, AuthStatus.unauthenticated);
      expect(container.read(balanceEpochProvider), epochBefore + 1,
          reason: 'logout is an identity boundary — the epoch must bump');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.unresolved,
          reason: 'after logout the card must show the waiting '
              'indicator, never the previous user\'s figure');
      expect(container.read(balanceDataProvider).availableBalance, 0.0);
      expect(container.read(userUsdcBalanceProvider), 0.0);
    });

    test('switching to a DIFFERENT user resets the balance surface; a '
        'transient hydration failure for the new identity must not show '
        'the previous user\'s balance', () async {
      _mockSecureStorage(token: null);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      var meStatus = 200;
      var meId = 'u1';
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/me/')) {
          return meStatus == 200
              ? http.Response(jsonEncode(_profileJson(meId, 120.5)), 200)
              : http.Response(jsonEncode({'message': 'nope'}), meStatus);
        }
        return http.Response(jsonEncode({'message': 'boom'}), 500);
      });

      final auth = AuthProvider(ref: ref, client: ApiClient(client: client));
      await auth.setSessionFromLogin(_loginUser('u1'));
      await _pump();
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded);
      expect(container.read(balanceDataProvider).availableBalance, 120.5);
      final epochBefore = container.read(balanceEpochProvider);

      // Identity switch: u1 -> u2, and the new hydration fails
      // transiently (5xx). The session survives, but the balance surface
      // must be unresolved/empty — never u1's 120.5.
      meStatus = 500;
      meId = 'u2';
      await auth.setSessionFromLogin(_loginUser('u2'));
      await _pump();

      expect(auth.status, AuthStatus.authenticated,
          reason: 'transient failure keeps the session');
      expect(container.read(balanceEpochProvider), epochBefore + 1,
          reason: 'a user switch is an identity boundary');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.unresolved,
          reason: 'the new identity has no confirmed balance yet — the '
              'old figure must not leak through as "loaded"');
      expect(container.read(balanceDataProvider).availableBalance, 0.0);
      expect(container.read(userUsdcBalanceProvider), 0.0);
    });

    test('SAME-identity re-login after a transient failure preserves the '
        'last confirmed balance (no reset, no epoch bump)', () async {
      _mockSecureStorage(token: null);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      var meStatus = 200;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/me/')) {
          return meStatus == 200
              ? http.Response(jsonEncode(_profileJson('u1', 120.5)), 200)
              : http.Response(jsonEncode({'message': 'nope'}), meStatus);
        }
        return http.Response(jsonEncode({'message': 'boom'}), 500);
      });

      final auth = AuthProvider(ref: ref, client: ApiClient(client: client));
      await auth.setSessionFromLogin(_loginUser('u1'));
      await _pump();
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded);
      final epochBefore = container.read(balanceEpochProvider);

      // Same identity, hydration now fails transiently.
      meStatus = 500;
      await auth.setSessionFromLogin(_loginUser('u1'));
      await _pump();

      expect(auth.status, AuthStatus.authenticated);
      expect(container.read(balanceEpochProvider), epochBefore,
          reason: 'same identity — no boundary crossed');
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded,
          reason: '"preserve last confirmed on refresh failure" holds for '
              'the SAME identity');
      expect(container.read(balanceDataProvider).availableBalance, 120.5);
    });

    test('404 profile-not-found tears down the identity and resets the '
        'balance surface', () async {
      _mockSecureStorage(token: null);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      var meStatus = 200;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/me/')) {
          return meStatus == 200
              ? http.Response(jsonEncode(_profileJson('u1', 120.5)), 200)
              : http.Response(jsonEncode({'message': 'nope'}), meStatus);
        }
        return http.Response(jsonEncode({'message': 'boom'}), 500);
      });

      final auth = AuthProvider(ref: ref, client: ApiClient(client: client));
      await auth.setSessionFromLogin(_loginUser('u1'));
      await _pump();
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded);
      final epochBefore = container.read(balanceEpochProvider);

      meStatus = 404;
      await auth.fetchUserDetails();
      await _pump();

      expect(auth.status, AuthStatus.profileNotFound);
      expect(container.read(balanceEpochProvider), epochBefore + 1,
          reason: 'the identity is gone — the epoch must bump');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.unresolved);
      expect(container.read(balanceDataProvider).availableBalance, 0.0);
      expect(container.read(userUsdcBalanceProvider), 0.0);
    });
  });

  group('refreshCanonicalBalance identity guard', () {
    test('a refresh that resolves AFTER an identity boundary is discarded '
        'completely (no data, no loaded, no failed)', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      // Model the post-boundary state: the reset already ran (empty,
      // unresolved), and the new user's hydration is in flight.
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.unresolved;

      final gate = Completer<http.Response>();
      balanceRefreshClientOverride = MockClient((request) => gate.future);

      // Start the refresh under the OLD identity (pre-bump epoch).
      final refresh = refreshCanonicalBalance(ref);
      await _pump();

      // The identity boundary happens mid-flight (e.g. logout / switch).
      container.read(balanceEpochProvider.notifier).state++;
      await _pump();

      // The stale response finally arrives with the OLD user's data.
      gate.complete(http.Response(
          jsonEncode({
            'data': {'availableBalance': 777.0}
          }),
          200));
      await refresh;

      expect(container.read(balanceDataProvider).availableBalance, 0.0,
          reason: 'a stale-identity response must not overwrite the new '
              'identity\'s balance');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.unresolved,
          reason: 'a stale-identity success must not mark the new '
              'identity "loaded"');
    });

    test('a refresh that FAILS after an identity boundary must not mark '
        'the new identity "failed"', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.unresolved;

      final gate = Completer<http.Response>();
      balanceRefreshClientOverride = MockClient((request) => gate.future);

      final refresh = refreshCanonicalBalance(ref);
      await _pump();

      container.read(balanceEpochProvider.notifier).state++;
      await _pump();

      gate.complete(http.Response(jsonEncode({'message': 'down'}), 503));
      await refresh;

      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.unresolved,
          reason: 'the old identity\'s failure must not fail the new '
              'identity\'s hydration');
    });

    test('a SAME-identity refresh failure retains the last confirmed '
        'balance (stays loaded)', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      // A previously confirmed balance for the current identity.
      container.read(balanceDataProvider.notifier).state =
          const BalanceData(availableBalance: 500.0);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.loaded;

      balanceRefreshClientOverride = MockClient(
          (request) async =>
              http.Response(jsonEncode({'message': 'down'}), 503));

      await refreshCanonicalBalance(ref);

      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded,
          reason: 'same identity: a transient refresh failure preserves '
              'the last confirmed figure');
      expect(container.read(balanceDataProvider).availableBalance, 500.0);
    });
  });
}
