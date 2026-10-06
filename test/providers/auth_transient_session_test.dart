// FINAL PASS §7 — AUTH/NAVIGATION REGRESSION PINS
//
// The brief: "The current auth.refresh/fetchUserDetails flow flips
// isAuthenticated=false on ANY non-401 exception (network timeout, server
// 500, parsing blip) — then the router redirect bounces a LIVE user back to
// '/' — investigate the intended semantics and fix so transient failures
// never invalidate an otherwise authenticated session. Add regression tests
// covering: authenticated state + transient /auth/me failure does not clear
// authentication and does not cause protected navigation to redirect to /;
// explicit logout still invalidates; a 401 still invalidates."
//
// The GoRouter redirect is a PURE function of the AuthGuard.isAuthenticated
// flag (lib/router/app_router.dart): if the flag survives a transient
// failure, no redirect to '/' can occur. These pins therefore assert the
// flag + provider state directly — the redirect has no other input.
//
// Http is faked with MockClient; the secure-storage method channel is
// mocked (reads return a fixed token, deletes are recorded so the 401 pin
// proves clearAuthData actually ran).

import 'dart:convert';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:azaman/services/api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

User _sessionUser() => User.fromJson({
      'id': 'u1',
      'username': 'u',
      'email': 'u@example.com',
      'token': 'tok',
      'role': 'USER',
    });

ApiClient _apiFor(http.Client client) => ApiClient(client: client);

void _mockSecureStorage(List<String> deletedKeys) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    switch (call.method) {
      case 'read':
        final key = call.arguments['key'];
        return key == 'auth_token' || key == 'user_id' ? 'mock' : null;
      case 'delete':
        deletedKeys.add(call.arguments['key']?.toString() ?? '');
        return null;
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'authenticated state + transient 5xx from /auth/me does NOT clear '
      'authentication (no redirect to / possible)', () async {
    final deletedKeys = <String>[];
    _mockSecureStorage(deletedKeys);

    final api = _apiFor(MockClient((request) async => http.Response(
        jsonEncode({'message': 'boom'}), 500)));

    final auth = AuthProvider(client: api);
    AuthGuard.isAuthenticated = false;
    await auth.setSessionFromLogin(_sessionUser());

    // §7 contract: session survives a transient server error.
    expect(auth.status, AuthStatus.authenticated,
        reason: 'a transient 5xx must not demote an authenticated session');
    expect(AuthGuard.isAuthenticated, isTrue,
        reason: 'the router redirect reads this flag; flipping it on a '
            'transient failure kicked live users back to "/"');
    expect(auth.user?.id, 'u1');
    expect(deletedKeys, isEmpty,
        reason: 'a transient failure must not clear stored credentials');

    AuthGuard.isAuthenticated = false;
  });

  test(
      'authenticated state + network-level failure (ClientException) does '
      'NOT clear authentication', () async {
    final deletedKeys = <String>[];
    _mockSecureStorage(deletedKeys);

    final api = _apiFor(MockClient((request) async =>
        throw http.ClientException('Server unreachable')));

    final auth = AuthProvider(client: api);
    AuthGuard.isAuthenticated = false;
    await auth.setSessionFromLogin(_sessionUser());

    expect(auth.status, AuthStatus.authenticated,
        reason: 'a dropped connection must keep the session intact');
    expect(AuthGuard.isAuthenticated, isTrue);
    expect(auth.user, isNotNull);

    AuthGuard.isAuthenticated = false;
  });

  test('an authoritative 401 from /auth/me STILL invalidates the session',
      () async {
    final deletedKeys = <String>[];
    _mockSecureStorage(deletedKeys);

    final api = _apiFor(MockClient((request) async => http.Response(
        jsonEncode({'message': 'jwt expired'}), 401)));

    final auth = AuthProvider(client: api);
    AuthGuard.isAuthenticated = false;
    await auth.setSessionFromLogin(_sessionUser());

    expect(auth.status, AuthStatus.unauthenticated);
    expect(AuthGuard.isAuthenticated, isFalse,
        reason: 'a rejected JWT must keep invalidating — the fix only '
            'covers TRANSIENT failures');
    expect(auth.user, isNull);
    expect(deletedKeys, containsAll(['auth_token', 'user_id']),
        reason: 'the 401 path must still clear stored credentials');

    AuthGuard.isAuthenticated = false;
  });

  test('a 404 profile miss still routes to the setup flow (profileNotFound)',
      () async {
    final deletedKeys = <String>[];
    _mockSecureStorage(deletedKeys);

    final api = _apiFor(MockClient((request) async =>
        http.Response(jsonEncode({'message': 'not found'}), 404)));

    final auth = AuthProvider(client: api);
    AuthGuard.isAuthenticated = false;
    await auth.setSessionFromLogin(_sessionUser());

    expect(auth.status, AuthStatus.profileNotFound);
    expect(AuthGuard.isAuthenticated, isFalse);
    expect(auth.user, isNull);

    AuthGuard.isAuthenticated = false;
  });

  test('explicit logout still invalidates', () async {
    final deletedKeys = <String>[];
    _mockSecureStorage(deletedKeys);

    final api = _apiFor(MockClient((request) async =>
        throw http.ClientException('offline during logout')));

    final auth = AuthProvider(client: api);
    AuthGuard.isAuthenticated = true;
    await auth.logout();

    expect(auth.status, AuthStatus.unauthenticated);
    expect(AuthGuard.isAuthenticated, isFalse);
    expect(auth.user, isNull);
  });
}
