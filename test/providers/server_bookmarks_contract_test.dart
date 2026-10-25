// =============================================================================
// Durable server bookmarks — contract guards for AZM-backend PR #370
// ("Backend A", BusinessBookmark).
//
// Wire contract (docs/marketplace-personalisation-contracts.md):
//   POST   /api/bookmarks → 201 new / 200 idempotent repeat,
//          { success, state: "BOOKMARKED", alreadyBookmarked,
//            bookmark: { businessProfileId, savedAt } }
//   DELETE /api/bookmarks/:id → 200 { state: "NOT_BOOKMARKED", removed }
//   GET    /api/bookmarks → { success, total, bookmarks: [...] } (savedAt DESC)
//
// Honesty rules pinned here:
//  * optimistic toggle with EXACT rollback on any rejection — including
//    the contract 404 "wrong business id" which must NEVER be retried
//    and NEVER simulated as a local save;
//  * idempotency both directions: repeat saves converge to BOOKMARKED,
//    repeat removals (removed:false) to NOT_BOOKMARKED;
//  * hydrate failure keeps the last known list — a failed load never
//    silently clears the user's bookmarks;
//  * the derived id set always agrees with the full state;
//  * demo mode routes to the device-local wishlist and makes NO HTTP
//    call (the demo interceptor must never answer for this contract).
// =============================================================================

import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/config.dart';
import 'package:azaman/providers/server_bookmarks_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/server_bookmark_service.dart';

// ── Fake HTTP edge ──────────────────────────────────────────────────────────

class _FakeApiClient extends ApiClient {
  final List<String> calls = <String>[];

  /// Canned handlers, installable per test.
  Future<http.Response> Function(String endpoint) onGet =
      (_) async => http.Response('{"success": true, "total": 0, "bookmarks": []}', 200);
  Future<http.Response> Function(String endpoint, Map<String, dynamic> body) onPost =
      (_, __) async => http.Response(
          '{"success": true, "state": "BOOKMARKED", "alreadyBookmarked": false,'
          ' "bookmark": {"businessProfileId": "u1", "savedAt": "2026-10-25T10:00:00Z"}}',
          201);
  Future<http.Response> Function(String endpoint) onDelete =
      (_) async => http.Response(
          '{"success": true, "state": "NOT_BOOKMARKED", "removed": true}', 200);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) {
    calls.add('GET $endpoint');
    return onGet(endpoint);
  }

  @override
  Future<http.Response> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers,
      bool requireAuth = true,
      String? idempotencyKey}) {
    calls.add('POST $endpoint');
    return onPost(endpoint, body);
  }

  @override
  Future<http.Response> delete(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) {
    calls.add('DELETE $endpoint');
    return onDelete(endpoint);
  }
}

String _pageJson(List<Map<String, dynamic>> items, {int? total}) =>
    jsonEncode(<String, dynamic>{
      'success': true,
      'total': total ?? items.length,
      'bookmarks': items,
    });

Map<String, dynamic> _dto(String id, {String? name}) => {
      'businessProfileId': id,
      'businessName': name ?? 'Business $id',
      'logoUrl': null,
      'category': 'RESTAURANT',
      'isVerified': true,
      'averageRating': 4.5,
      'savedAt': '2026-10-2${id.length}T10:00:00Z',
    };

// ── Harness ─────────────────────────────────────────────────────────────────

class _Harness {
  final _FakeApiClient api = _FakeApiClient();
  late final ProviderContainer container;
  late final ServerBookmarksNotifier notifier;

  _Harness() {
    // A notifier seeded via a canned GET — autoHydrate rides the fake.
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    notifier = container.read(serverBookmarksProvider.notifier);
  }

  Set<String> get ids =>
      container.read(serverBookmarkIdsProvider);

  void dispose() => container.dispose();
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hydrate — GET /api/bookmarks', () {
    test('parses the BookmarkPage shape; newest first is the server order',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onGet = (_) async =>
          http.Response(_pageJson([_dto('u1'), _dto('u2', name: 'Second')], total: 2), 200);

      await h.notifier.hydrate();

      final state = h.container.read(serverBookmarksProvider);
      expect(state.loaded, isTrue);
      expect(state.error, isNull);
      expect(
          state.bookmarks.map((b) => b.businessProfileId), ['u1', 'u2']);
      expect(state.bookmarks.first.businessName, 'Business u1');
      expect(h.ids, {'u1', 'u2'});
    });

    test('hydrate failure KEEPS the last known list and records an honest error',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onGet = (_) async => http.Response(_pageJson([_dto('u1')]), 200);
      await h.notifier.hydrate();
      expect(h.ids, {'u1'});

      // Now the network dies mid-refresh.
      h.api.onGet = (_) async => throw const SocketException('offline');
      await h.notifier.hydrate();

      final state = h.container.read(serverBookmarksProvider);
      expect(state.error, isNotNull,
          reason: 'the failure must be surfaced, never swallowed');
      expect(state.loaded, isTrue,
          reason: 'a failed refresh does not un-load the screen');
      expect(h.ids, {'u1'},
          reason: 'a failed load NEVER silently clears the bookmark list');
    });

    test('a successful hydrate replaces optimistic placeholders with server truth',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      // Save lands with a placeholder row...
      await h.notifier.save('u1');
      expect(h.container.read(serverBookmarksProvider).bookmarks.single.businessName, '');

      // ...then hydrate replaces it with the durable row.
      h.api.onGet = (_) async => http.Response(_pageJson([_dto('u1')]), 200);
      await h.notifier.hydrate();
      expect(h.container.read(serverBookmarksProvider).bookmarks.single.businessName,
          'Business u1');
    });
  });

  group('save — POST /api/bookmarks', () {
    test('201 — optimistic placeholder confirmed durable, returns true',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);

      final pending = h.notifier.save('u1');
      await _drain();
      // Optimistic membership is visible BEFORE the response resolves.
      expect(h.ids, contains('u1'));

      expect(await pending, isTrue);
      expect(h.api.calls, contains('POST /bookmarks'));
      expect(h.container.read(serverBookmarksProvider).error, isNull);
    });

    test('200 alreadyBookmarked (idempotent repeat) converges to BOOKMARKED',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onPost = (endpoint, body) async => http.Response(
          '{"success": true, "state": "BOOKMARKED", "alreadyBookmarked": true,'
          ' "bookmark": {"businessProfileId": "u1", "savedAt": "2026-10-25T10:00:00Z"}}',
          200);

      final ok = await h.notifier.save('u1');

      expect(ok, isTrue,
          reason: 'alreadyBookmarked is a durable end state, not an error');
    });

    test('404 — wrong business id: EXACT rollback, never simulated, never retried',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onGet = (_) async =>
          http.Response(_pageJson([_dto('u1'), _dto('u2')]), 200);
      await h.notifier.hydrate();
      final before = h.container.read(serverBookmarksProvider).bookmarks;

      h.api.onPost = (endpoint, body) async =>
          http.Response('{"success": false, "message": "Business not found."}', 404);
      final ok = await h.notifier.save('u9');

      expect(ok, isFalse, reason: 'the contract forbids simulating a 404 save');
      expect(
          h.container.read(serverBookmarksProvider).bookmarks, before,
          reason: 'rollback restores the exact snapshot');
      expect(h.api.calls.where((c) => c == 'POST /bookmarks').length, 1,
          reason: 'a 404 must NOT be retried');
    });

    test('network failure — EXACT rollback, returns false', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onPost = (endpoint, body) async => throw const SocketException('offline');

      final ok = await h.notifier.save('u1');

      expect(ok, isFalse);
      expect(h.ids, isEmpty, reason: 'offline must not leave a phantom save');
    });

    test('a 2xx WITHOUT state BOOKMARKED is a contract violation → rollback',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onPost = (endpoint, body) async =>
          http.Response('{"success": true, "unexpected": true}', 200);

      final ok = await h.notifier.save('u1');

      expect(ok, isFalse,
          reason: 'the client trusts `state`, never the status code alone');
      expect(h.ids, isEmpty);
    });
  });

  group('remove — DELETE /api/bookmarks/:id', () {
    test('200 removed:true — durable NOT_BOOKMARKED', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.notifier.save('u1');

      final ok = await h.notifier.remove('u1');

      expect(ok, isTrue);
      expect(h.ids, isEmpty);
      expect(h.api.calls, contains('DELETE /bookmarks/u1'));
    });

    test('200 removed:false (was not bookmarked) is STILL the durable end state',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.notifier.save('u1');
      h.api.onDelete = (_) async => http.Response(
          '{"success": true, "state": "NOT_BOOKMARKED", "removed": false}', 200);

      final ok = await h.notifier.remove('u1');

      expect(ok, isTrue,
          reason: 'idempotent removal: the user wanted it gone; it is gone');
      expect(h.ids, isEmpty);
    });

    test('500 — EXACT rollback, returns false', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onGet = (_) async =>
          http.Response(_pageJson([_dto('u1'), _dto('u2')]), 200);
      await h.notifier.hydrate();
      final before = h.container.read(serverBookmarksProvider).bookmarks;

      h.api.onDelete = (_) async => http.Response('boom', 500);
      final ok = await h.notifier.remove('u2');

      expect(ok, isFalse);
      expect(h.container.read(serverBookmarksProvider).bookmarks, before);
    });

    test('repeat removal with no local row makes no HTTP call', () async {
      final h = _Harness();
      addTearDown(h.dispose);

      final ok = await h.notifier.remove('never-saved');

      expect(ok, isTrue);
      expect(h.api.calls.where((c) => c.startsWith('DELETE')), isEmpty);
    });
  });

  group('derived id set consistency', () {
    test('the id set always agrees with the full state', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onGet = (_) async =>
          http.Response(_pageJson([_dto('u1'), _dto('u2')]), 200);
      await h.notifier.hydrate();

      expect(h.ids, {'u1', 'u2'});

      await h.notifier.remove('u1');
      expect(h.ids, {'u2'},
          reason: 'badge/toggle state and the list can never disagree');
    });
  });

  group('demo mode keeps the device-local wishlist', () {
    test('the notifier fires NO bookmark HTTP in demo mode', () async {
      // Demo mode has no backend, and the demo interceptor must never
      // answer for the bookmark contract. The notifier-level gate is
      // defense in depth beneath the UI seam.
      AppConfig.enableDemoMode();
      addTearDown(() {
        // AppConfig has no public disable — the process is per-test
        // isolated; nothing to restore inside one VM.
      });

      final api = _FakeApiClient();
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      final notifier = ServerBookmarksNotifier(
          service: ServerBookmarkService(client: api), autoHydrate: true);
      await _drain();
      await notifier.save('u1');
      await notifier.remove('u1');
      await notifier.hydrate();

      expect(api.calls, isEmpty,
          reason: 'no bookmark HTTP may ever fire in demo mode');
      expect(container.read(serverBookmarkIdsProvider), isEmpty);
    });
  });
}
