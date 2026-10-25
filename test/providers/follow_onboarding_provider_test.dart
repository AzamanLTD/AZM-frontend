// =============================================================================
// I1 — Marketplace Follow Onboarding: eligibility + dismissal tests.
//
// Pins the required state machine against REAL fake-HTTP edges:
//   • empty vs non-empty authoritative follow list
//   • loading / unauthenticated / failed request / malformed body —
//     none of which is ever an "eligible" state
//   • "Maybe later" persists user-scoped and never repeats
//   • account switching is isolated by construction (family key)
// =============================================================================
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/follow_onboarding_dismissal_store.dart';
import 'package:azaman/providers/follow_onboarding_provider.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// In-memory FlutterSecureStorage: implements the platform interface so
/// the REAL store code (read/write/delete) runs — no storage mock at
/// the logic level.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.containsKey(key);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFollowClient extends ApiClient {
  final int status;
  final dynamic following; // List, or a non-List for malformed cases
  _FakeFollowClient({this.status = 200, this.following = const []});

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    if (endpoint.startsWith('/follows/following')) {
      return _json(status, {'success': true, 'following': following});
    }
    return _json(404, {'success': false});
  }
}

class _ThrowingClient extends ApiClient {
  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    throw Exception('network unreachable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('eligibility state machine', () {
    test('empty follow list -> eligible; non-empty -> notEligible', () async {
      final empty = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(following: []),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(empty.state, FollowOnboardingEligibility.eligible);

      final one = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(
          following: [
            {'businessProfileId': 'bp-9'},
          ],
        ),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(one.state, FollowOnboardingEligibility.notEligible);
    });

    test('loading precedes the verdict; failure is error, never '
        'eligible', () async {
      // Failure: transport error.
      final failing = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _ThrowingClient(),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      expect(failing.state, FollowOnboardingEligibility.loading);
      await Future<void>.delayed(Duration.zero);
      expect(
        failing.state,
        FollowOnboardingEligibility.error,
        reason: 'a failed request is NEVER an empty follow list',
      );

      // Failure: non-2xx.
      final rejected = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(status: 401),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rejected.state, FollowOnboardingEligibility.error);

      // Failure: malformed body (following is not a List).
      final malformed = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(following: {'oops': true}),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        malformed.state,
        FollowOnboardingEligibility.error,
        reason: 'missing/malformed data is NEVER an empty list',
      );
    });

    test('no authenticated user -> notAuthenticated (no requests '
        'fired)', () async {
      var requests = 0;
      final client = _FakeFollowClient();
      final c = FollowOnboardingEligibilityController(
        userId: null,
        api: _RecordingClient(() => requests++),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
      );
      expect(c.state, FollowOnboardingEligibility.notAuthenticated);
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);
    });

    test('demo mode: eligibility is honestly unestablished — the '
        'card can never render', () async {
      var requests = 0;
      final c = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _RecordingClient(() => requests++),
        store: FollowOnboardingDismissalStore(storage: _FakeSecureStorage()),
        demoMode: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.state, FollowOnboardingEligibility.error);
      expect(
        requests,
        0,
        reason:
            'the demo interceptor must never answer for the '
            'follow contract',
      );
    });
  });

  group('maybe-later dismissal', () {
    test('dismissal persists user-scoped and never repeats', () async {
      final storage = _FakeSecureStorage();
      final store = FollowOnboardingDismissalStore(storage: storage);

      // Before: eligible.
      final c = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(following: []),
        store: store,
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.state, FollowOnboardingEligibility.eligible);

      await c.maybeLater();
      expect(c.state, FollowOnboardingEligibility.dismissed);

      // A FRESH controller (next app launch) reads the same store:
      // no second prompt for this account.
      final relaunch = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _ThrowingClient(), // store verdict wins pre-network
        store: store,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        relaunch.state,
        FollowOnboardingEligibility.dismissed,
        reason:
            'the persisted dismissal wins without any network '
            'call — throwing client proves none was needed',
      );
    });

    test('account switching is isolated: another user starts clean', () async {
      final storage = _FakeSecureStorage();
      final store = FollowOnboardingDismissalStore(storage: storage);

      final a = FollowOnboardingEligibilityController(
        userId: 'user-a',
        api: _FakeFollowClient(following: []),
        store: store,
      );
      await Future<void>.delayed(Duration.zero);
      await a.maybeLater();
      expect(a.state, FollowOnboardingEligibility.dismissed);

      // user-b on the SAME device: no inherited dismissal.
      final b = FollowOnboardingEligibilityController(
        userId: 'user-b',
        api: _FakeFollowClient(following: []),
        store: store,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        b.state,
        FollowOnboardingEligibility.eligible,
        reason: 'dismissals are scoped per user id by construction',
      );

      // And user-a's dismissal still stands after user-b's session.
      final a2 = FollowOnboardingEligibilityController(
        userId: 'user-a',
        api: _FakeFollowClient(following: []),
        store: store,
      );
      await Future<void>.delayed(Duration.zero);
      expect(a2.state, FollowOnboardingEligibility.dismissed);
    });

    test('a corrupt dismissal record reads as NOT dismissed (honest '
        'absence)', () async {
      final storage = _FakeSecureStorage();
      await storage.write(
        key: 'azm.marketplace.followOnboarding.user-1',
        value: 'not json at all',
      );
      final c = FollowOnboardingEligibilityController(
        userId: 'user-1',
        api: _FakeFollowClient(following: []),
        store: FollowOnboardingDismissalStore(storage: storage),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        c.state,
        FollowOnboardingEligibility.eligible,
        reason: 'corrupt storage never fabricates a dismissal',
      );
    });
  });
}

/// Counts requests; used where no body matters.
class _RecordingClient extends ApiClient {
  final void Function() onGet;
  _RecordingClient(this.onGet);

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    onGet();
    return _json(200, {'success': true, 'following': const []});
  }
}
