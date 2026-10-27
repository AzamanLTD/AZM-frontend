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
void _mockSecureStorage({String? token, String? userId}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    switch (call.method) {
      case 'read':
        final key = call.arguments['key'];
        if (key == 'auth_token') return token;
        if (key == 'user_id') return userId;
        return null;
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

  // LEAD REVIEW FOLLOW-UP 1 — checkAuthStatus() must end the balance
  // identity too: ApiClient.isAuthenticated() also returns false when
  // the check request itself fails, and setSessionFromLogin sees
  // `_user == null` afterwards so its different-user guard cannot reset.
  test('checkAuthStatus()=false resets the balance surface; a new user '
      'whose hydration fails never sees the old figure, and a late old '
      'refresh is discarded', () async {
    _mockSecureStorage(token: 'mock', userId: 'u1');

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
    expect(container.read(balanceDataProvider).availableBalance, 120.5);
    final epochBefore = container.read(balanceEpochProvider);

    // The old user's refresh is still in flight when the session dies.
    final gate = Completer<http.Response>();
    balanceRefreshClientOverride = MockClient((request) => gate.future);
    final staleRefresh = refreshCanonicalBalance(ref);
    await _pump();

    // checkAuthStatus() -> isAuthenticated() false (storage intact but
    // /auth/me fails here). This is a session end: the surface resets.
    meStatus = 500;
    final ok = await auth.checkAuthStatus();
    expect(ok, false, reason: 'the mock must drive the unauthenticated path');
    expect(container.read(balanceEpochProvider), epochBefore + 1,
        reason: 'checkAuthStatus()=false is an identity boundary — the '
            'epoch must bump');
    expect(container.read(balanceReadinessProvider),
        BalanceReadiness.unresolved);
    expect(container.read(balanceDataProvider).availableBalance, 0.0);
    expect(container.read(userUsdcBalanceProvider), 0.0);

    // New user logs in on the now-null session and hydration FAILS
    // transiently: the card must stay unresolved, never u1's 120.5.
    await auth.setSessionFromLogin(_loginUser('u2'));
    await _pump();
    expect(auth.status, AuthStatus.authenticated,
        reason: 'transient hydration failure keeps the session');
    expect(container.read(balanceReadinessProvider),
        BalanceReadiness.unresolved,
        reason: 'u2 has no confirmed balance — u1\'s figure must not '
            'survive the checkAuthStatus() boundary');
    expect(container.read(balanceDataProvider).availableBalance, 0.0);

    // The old identity's refresh resolves last and must be discarded.
    gate.complete(http.Response(
        jsonEncode({
          'data': {'availableBalance': 777.0}
        }),
        200));
    await staleRefresh;
    expect(container.read(balanceDataProvider).availableBalance, 0.0);
    expect(container.read(balanceReadinessProvider),
        BalanceReadiness.unresolved);
  });

  // LEAD REVIEW FOLLOW-UP 1 (race) — the checkAuthStatus() boundary
  // must also invalidate an in-flight profile hydration: a late
  // /auth/me success for the cleared identity must not restore the
  // user, the authenticated status, or the old balance.
  test('checkAuthStatus()=false invalidates a pending fetchUserDetails — '
      'a late old-user profile response is discarded completely', () async {
    // Storage carries NO credentials: isAuthenticated() returns false
    // without issuing a request, so the only /auth/me traffic is the
    // hydration itself.
    _mockSecureStorage(token: null, userId: null);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ref = container.read(_refProbe);

    var meCalls = 0;
    final gate = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.contains('/auth/me/')) {
        meCalls++;
        return meCalls == 1
            ? http.Response(jsonEncode(_profileJson('u1', 120.5)), 200)
            : gate.future;
      }
      return http.Response(jsonEncode({'message': 'boom'}), 500);
    });

    final auth = AuthProvider(ref: ref, client: ApiClient(client: client));
    await auth.setSessionFromLogin(_loginUser('u1'));
    await _pump();
    expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded);
    expect(container.read(balanceDataProvider).availableBalance, 120.5);
    final epochBefore = container.read(balanceEpochProvider);

    // A profile re-hydration for u1 is in flight when the session dies.
    final lateHydration = auth.fetchUserDetails();
    await _pump();
    expect(meCalls, 2, reason: 'the stale hydration must be in flight');

    // The session ends: checkAuthStatus() reports unauthenticated.
    final ok = await auth.checkAuthStatus();
    expect(ok, false);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(container.read(balanceEpochProvider), epochBefore + 1,
        reason: 'the boundary must still bump the epoch');
    expect(container.read(balanceReadinessProvider),
        BalanceReadiness.unresolved);
    expect(container.read(balanceDataProvider).availableBalance, 0.0);

    // The stale u1 profile response lands with a SUCCESS body. It must
    // be discarded wholesale: no restored user, no authenticated
    // status, no balance or readiness write.
    gate.complete(http.Response(jsonEncode(_profileJson('u1', 999.0)), 200));
    await lateHydration;
    await _pump();

    expect(auth.user, isNull,
        reason: 'a late hydration must not restore the cleared user');
    expect(auth.status, AuthStatus.unauthenticated,
        reason: 'a late hydration must not flip the session back to '
            'authenticated');
    expect(AuthGuard.isAuthenticated, false);
    expect(container.read(balanceReadinessProvider),
        BalanceReadiness.unresolved,
        reason: 'a late hydration must not mark readiness loaded');
    expect(container.read(balanceDataProvider).availableBalance, 0.0,
        reason: 'a late hydration must not write the old user\'s '
            'balance');
    expect(container.read(userUsdcBalanceProvider), 0.0);
    expect(container.read(balanceEpochProvider), epochBefore + 1);
  });

  // LEAD REVIEW FOLLOW-UP 2 — single-flight coalescing is identity
  // (epoch) scoped: a new identity may start its own refresh while the
  // previous identity's request is still pending.
  group('refreshCanonicalBalance identity-scoped single-flight', () {
    test('an OLD refresh pending at an epoch bump does not swallow the '
        'new identity\'s refresh — both resolve independently', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.unresolved;

      // Identity A's refresh hangs on a gate.
      final gate = Completer<http.Response>();
      balanceRefreshClientOverride = MockClient((request) => gate.future);
      final oldRefresh = refreshCanonicalBalance(ref);
      await _pump();

      // Identity boundary: epoch bumps mid-flight.
      container.read(balanceEpochProvider.notifier).state++;
      await _pump();

      // The new identity asks for a refresh: it must START its own
      // request (the pending old future belongs to the previous epoch).
      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(
              jsonEncode({
                'data': {
                  'availableBalance': 55.0,
                  'vendorUnallocatedBalance': '0',
                  'escrowLockedBalance': '0',
                  'disputeEscrowBalance': '0',
                  'azmBalance': '0',
                }
              }),
              200));
      final newRefresh = refreshCanonicalBalance(ref);
      await newRefresh; // would never settle on the old (still-gated) future

      expect(container.read(balanceDataProvider).availableBalance, 55.0,
          reason: 'the new identity\'s refresh must actually run');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.loaded);

      // A's stale response lands last and is discarded.
      gate.complete(http.Response(
          jsonEncode({
            'data': {
              'availableBalance': 999.0,
              'vendorUnallocatedBalance': '0',
              'escrowLockedBalance': '0',
              'disputeEscrowBalance': '0',
              'azmBalance': '0',
            }
          }),
          200));
      await oldRefresh;
      expect(container.read(balanceDataProvider).availableBalance, 55.0,
          reason: 'the old identity\'s response must not overwrite the '
              'new identity\'s figure');
    });

    test('SAME epoch still coalesces — concurrent refreshes issue ONE '
        'request', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.unresolved;

      var requests = 0;
      final gate = Completer<http.Response>();
      balanceRefreshClientOverride =
          MockClient((request) => requests++ == 0 ? gate.future : gate.future);

      final a = refreshCanonicalBalance(ref);
      final b = refreshCanonicalBalance(ref);
      await _pump();

      expect(requests, 1,
          reason: 'same identity: the second caller must join the '
              'in-flight request instead of issuing a new one');

      gate.complete(http.Response(
          jsonEncode({
            'data': {
              'availableBalance': 42.0,
              'vendorUnallocatedBalance': '0',
              'escrowLockedBalance': '0',
              'disputeEscrowBalance': '0',
              'azmBalance': '0',
            }
          }),
          200));
      await a;
      await b;
      expect(container.read(balanceDataProvider).availableBalance, 42.0);
      expect(container.read(balanceReadinessProvider), BalanceReadiness.loaded);
    });
  });

  // LEAD REVIEW FOLLOW-UP 3 — resource lifecycle: the refresh must never
  // create (or need to close) an owned client; the injected test client
  // stays under test ownership and is not closed by production code.
  group('refreshCanonicalBalance resource lifecycle', () {
    test('the injected test client is never closed by the refresh', () async {
      _mockSecureStorage(token: 'mock');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      var closeCalls = 0;
      balanceRefreshClientOverride = _CloseCountingClient(
        (request) async => http.Response(
            jsonEncode({
              'data': {
                'availableBalance': 10.0,
                'vendorUnallocatedBalance': '0',
                'escrowLockedBalance': '0',
                'disputeEscrowBalance': '0',
                'azmBalance': '0',
              }
            }),
            200),
        () => closeCalls++,
      );

      await refreshCanonicalBalance(ref);

      expect(closeCalls, 0,
          reason: 'the injected client belongs to the test; the refresh '
              'must not close it');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.loaded);
      expect(container.read(balanceDataProvider).availableBalance, 10.0);
    });
  });
  group('refreshCanonicalBalance payload validation (the strict parse)', () {
    test('a valid full payload writes the data and marks loaded', () async {
      _mockSecureStorage(token: 'mock');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(jsonEncode({
            'data': {
              'availableBalance': 777.0,
              'vendorUnallocatedBalance': '1',
              'escrowLockedBalance': '2',
              'disputeEscrowBalance': 3,
              'azmBalance': '4',
            },
          }), 200));

      await refreshCanonicalBalance(ref);
      await _pump();

      expect(container.read(balanceDataProvider).availableBalance, 777.0);
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.loaded);
    });

    test('a missing legacy field marks the attempt FAILED, writes nothing', () async {
      _mockSecureStorage(token: 'mock');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(jsonEncode({
            'data': {
              // azmBalance missing — the lenient fromJson would have
              // read it as a confirmed 0.
              'availableBalance': 777.0,
              'vendorUnallocatedBalance': '1',
              'escrowLockedBalance': '2',
              'disputeEscrowBalance': 3,
            },
          }), 200));

      await refreshCanonicalBalance(ref);
      await _pump();

      expect(container.read(balanceDataProvider).availableBalance, 0.0,
          reason: 'an invalid payload must not write data');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.failed,
          reason: 'missing fields are a validation failure, not a '
              'confirmed balance');
    });

    test('a malformed payload after a CONFIRMED balance keeps the last '
        'confirmed figure (stays loaded)', () async {
      _mockSecureStorage(token: 'mock');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      container.read(balanceDataProvider.notifier).state =
          const BalanceData(availableBalance: 500.0);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.loaded;

      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(jsonEncode({
            'data': {
              'availableBalance': 'not-a-number',
              'vendorUnallocatedBalance': '1',
              'escrowLockedBalance': '2',
              'disputeEscrowBalance': 3,
              'azmBalance': '4',
            },
          }), 200));

      await refreshCanonicalBalance(ref);
      await _pump();

      expect(container.read(balanceDataProvider).availableBalance, 500.0,
          reason: 'the last server-confirmed figure stays authoritative');
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.loaded,
          reason: 'the failed attempt does not discard the confirmed '
              'state (the hologram ledger\'s own law)');
    });

    test('a payload carrying data.valuation plumbs it through to the '
        'BalanceData', () async {
      _mockSecureStorage(token: 'mock');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(jsonEncode({
            'data': {
              'availableBalance': 1,
              'vendorUnallocatedBalance': '2',
              'escrowLockedBalance': '3',
              'disputeEscrowBalance': 4,
              'azmBalance': '5',
              'valuation': {'pair': 'USDC/GHS'},
            },
          }), 200));

      await refreshCanonicalBalance(ref);
      await _pump();

      final b = container.read(balanceDataProvider);
      expect(b.valuationFieldPresent, isTrue);
      expect(b.valuationRaw, isA<Map<String, dynamic>>());
      expect(b.valuationRaw!['pair'], 'USDC/GHS');
    });

    test('an EXPLICIT null valuation is plumbed as present-but-null', () async {
      _mockSecureStorage(token: 'mock');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProbe);

      balanceRefreshClientOverride = MockClient((request) async =>
          http.Response(jsonEncode({
            'data': {
              'availableBalance': 1,
              'vendorUnallocatedBalance': '2',
              'escrowLockedBalance': '3',
              'disputeEscrowBalance': 4,
              'azmBalance': '5',
              'valuation': null,
            },
          }), 200));

      await refreshCanonicalBalance(ref);
      await _pump();

      final b = container.read(balanceDataProvider);
      expect(b.valuationFieldPresent, isTrue);
      expect(b.valuationRaw, isNull);
      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.loaded,
          reason: 'explicit valuation unavailability is NOT a ledger '
              'failure — the balance itself was confirmed');
    });
  });
}

/// A [MockClient] that records calls to [close] so tests can prove that
/// production code never closes a client it does not own.
class _CloseCountingClient extends MockClient {
  _CloseCountingClient(super.fn, this.onClose);

  final void Function() onClose;

  @override
  void close() {
    onClose();
    super.close();
  }


}
