// =============================================================================
// Durable notification dismissal — owner-scoped DELETE contract guards
//
// Backend contract (AZM-backend PR #374, "Backend E"):
//   DELETE /api/notifications/:id  soft-dismisses the row. The server
//   NEVER deletes the record; it hides it from the owner's list and
//   unread count in every mode, and broadcasts
//   `notifications_updated { type: DISMISSED, notificationId }` on the
//   owner's socket room so other sessions converge.
//
// Honesty rules pinned by this suite:
//   * optimistic removal, EXACT rollback on rejection — an item is
//     never silently lost locally when the server said no (500, 404,
//     network failure);
//   * dismissal is independent of isRead — no PATCH read is fired by a
//     dismissal, and a rolled-back item returns with its read state
//     untouched;
//   * repeated dismissal is idempotent on both sides;
//   * the socket DISMISSED event converges the same durable state with
//     NO HTTP re-request;
//   * the derived unread count follows the durable list, so the badge
//     and the list can never disagree.
// =============================================================================

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/models/notification_model.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';

// ── Fake HTTP edge ──────────────────────────────────────────────────────────

typedef _DeleteHandler = Future<http.Response> Function(String endpoint);

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  /// Every HTTP call that left the notifier, in order.
  final List<String> calls = <String>[];

  /// Handler for DELETE calls. Tests install canned responses/throws.
  _DeleteHandler onDelete = (_) async => http.Response('{}', 200);

  @override
  Future<http.Response> delete(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) {
    calls.add('DELETE $endpoint');
    return onDelete(endpoint);
  }

  @override
  Future<http.Response> patch(String endpoint,
      {Map<String, dynamic>? body,
      Map<String, String>? headers,
      bool requireAuth = true}) {
    calls.add('PATCH $endpoint');
    throw StateError('no PATCH expected in the dismissal contract tests');
  }

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    calls.add('GET $endpoint');
    // Constructor fetch bails before HTTP when no auth token exists; if
    // it ever reaches here in these tests that's a bug to surface.
    return http.Response('{"notifications": []}', 200);
  }
}

// ── Fake socket edge ───────────────────────────────────────────────────────

class _FakeSocketService implements SocketService {
  final List<void Function(Map<String, dynamic>)> _updated = [];

  @override
  void onNotificationsUpdated(void Function(Map<String, dynamic>) cb) =>
      _updated.add(cb);

  @override
  void removeNotificationsUpdatedListener(
      void Function(Map<String, dynamic>) cb) {
    _updated.remove(cb);
  }

  /// Simulates the server broadcasting `notifications_updated` to the
  /// owner's room (what another session's dismissal triggers).
  void serverBroadcast(Map<String, dynamic> payload) {
    for (final cb in List.of(_updated)) {
      cb(payload);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ── Harness ─────────────────────────────────────────────────────────────────

AppNotification _n(String id,
    {bool isRead = false,
    NotificationCategory category = NotificationCategory.money}) {
  return AppNotification(
    id: id,
    title: 'title-$id',
    body: 'body-$id',
    category: category,
    createdAt: DateTime.parse('2026-10-25T10:00:00Z'),
    isRead: isRead,
  );
}

class _Harness {
  final _FakeApiClient api = _FakeApiClient();
  final _FakeSocketService socket = _FakeSocketService();
  late final ProviderContainer container;
  late final NotificationNotifier notifier;
  late final ProviderSubscription sub;

  _Harness() {
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      socketServiceProvider.overrideWithValue(socket),
    ]);
    notifier = container.read(notificationProvider.notifier);
    sub = container.listen(notificationProvider, (_, __) {});
  }

  List<AppNotification> get state => sub.read();

  void seed(List<AppNotification> items) {
    for (final n in items) {
      notifier.addNotification(n);
    }
  }

  void dispose() {
    sub.close();
    container.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('owner-scoped durable dismissal (DELETE /notifications/:id)', () {
    test('200 — optimistic removal becomes durable; returns true', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a'), _n('b')]);

      final ok = await h.notifier.deleteNotification('a');

      expect(ok, isTrue, reason: 'server 200 → durable dismissal');
      expect(h.state.map((n) => n.id), ['b'],
          reason: 'the dismissed row is gone from the durable list');
      expect(h.api.calls, contains('DELETE /notifications/a'));
    });

    test('optimistic removal is visible BEFORE the response resolves',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a'), _n('b')]);

      final response = Completer<http.Response>();
      h.api.onDelete = (_) => response.future;

      final pending = h.notifier.deleteNotification('a');
      await Future<void>.delayed(Duration.zero);

      expect(h.state.map((n) => n.id), ['b'],
          reason: 'the swipe must feel instant: the row hides at once');

      response.complete(http.Response('{}', 200));
      expect(await pending, isTrue);
    });

    test('500 — exact rollback: same position, same read state, returns false',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a'), _n('unread', isRead: false), _n('c')]);
      final before = h.state.map((n) => n.id).toList();
      expect(before, containsAll(['a', 'unread', 'c']));

      h.api.onDelete = (_) async => http.Response('boom', 500);
      final ok = await h.notifier.deleteNotification('unread');

      expect(ok, isFalse, reason: 'a rejected dismissal must surface failure');
      expect(h.state.map((n) => n.id), before,
          reason: 'rollback restores the ORIGINAL order exactly');
      expect(h.state[1].isRead, isFalse,
          reason: 'the rolled-back row keeps its unread state — a failed '
              'dismissal never marks anything read');
    });

    test('network failure — exact rollback, returns false', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a')]);

      h.api.onDelete = (_) async => throw const SocketException('offline');
      final ok = await h.notifier.deleteNotification('a');

      expect(ok, isFalse);
      expect(h.state.map((n) => n.id), ['a'],
          reason: 'offline must not silently swallow the row');
    });

    test('404 unknown id — treated as rejection, not as durable state',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a')]);

      h.api.onDelete = (_) async => http.Response('{"success":false}', 404);
      final ok = await h.notifier.deleteNotification('a');

      expect(ok, isFalse,
          reason: 'the client never invents a dismissal the server did not '
              'confirm (contract: no local save on 404)');
      expect(h.state.map((n) => n.id), ['a']);
    });

    test('repeat dismissal is idempotent on both sides', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a')]);

      expect(await h.notifier.deleteNotification('a'), isTrue);
      // Server 200s an already-dismissed row (contract idempotency).
      final second = await h.notifier.deleteNotification('a');

      expect(second, isTrue);
      expect(h.state, isEmpty,
          reason: 'the repeat must not resurrect the row');
    });

    test('dismissal NEVER marks read — no PATCH fired', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('unread', isRead: false)]);

      await h.notifier.deleteNotification('unread');

      expect(
        h.api.calls.where((c) => c.startsWith('PATCH')).isEmpty,
        isTrue,
        reason: 'isRead and isDismissed are INDEPENDENT states — a '
            'dismissal must not touch the read endpoint',
      );
    });
  });

  group('socket convergence (notifications_updated DISMISSED)', () {
    test('another session dismissal hides the row WITHOUT any HTTP call',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a'), _n('b')]);

      h.socket.serverBroadcast({
        'type': 'DISMISSED',
        'notificationId': 'a',
      });

      expect(h.state.map((n) => n.id), ['b'],
          reason: 'the durable server state is mirrored, not re-requested');
      expect(h.api.calls, isEmpty,
          reason: 'the server already persisted the dismissal; the socket '
              'path makes NO HTTP round-trip');
    });

    test('DISMISSED for an unknown local id is a harmless no-op', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('b')]);

      h.socket.serverBroadcast({
        'type': 'DISMISSED',
        'notificationId': 'never-loaded',
      });

      expect(h.state.map((n) => n.id), ['b']);
    });

    test('MARKED_READ still converges alongside DISMISSED handling', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a', isRead: false)]);

      h.socket.serverBroadcast({
        'type': 'MARKED_READ',
        'notificationId': 'a',
      });

      expect(h.state.single.isRead, isTrue,
          reason: 'existing read-convergence behaviour is unchanged by the '
              'dismissal contract');
    });
  });


  // ==========================================================================
  // REVIEW 4.4 — ROLLBACK ATOMICITY: a failed dismissal must roll back
  // ONLY its own item. The old full-snapshot rollback resurrected items
  // that concurrent operations (a second successful dismissal, or a
  // socket DISMISSED convergence from another session) had legitimately
  // settled while this request was in flight.
  // ==========================================================================
  group('rollback atomicity (review 4.4)', () {
    test('a failed dismissal cannot resurrect a concurrently dismissed item',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onDelete = (endpoint) async =>
          endpoint.contains('/a') ? http.Response('{}', 500) : http.Response('{}', 200);
      h.seed([_n('a'), _n('b'), _n('c')]);

      final first = h.notifier.deleteNotification('a'); // will FAIL (500)
      final second = h.notifier.deleteNotification('b'); // succeeds mid-flight
      await Future.wait([first, second]);

      // 'a' is honestly back (its dismissal failed); 'b' STAYS gone.
      expect(
          h.state.map((n) => n.id), contains('a'),
          reason: 'the failed dismissal rolls its own item back');
      expect(
          h.state.map((n) => n.id), isNot(contains('b')),
          reason: 'the concurrent SUCCESS must not be resurrected');
    });

    test('a failed dismissal cannot resurrect a socket-dismissed item',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onDelete = (endpoint) async =>
          endpoint.contains('/a') ? http.Response('{}', 500) : http.Response('{}', 200);
      h.seed([_n('a'), _n('b')]);

      final pending = h.notifier.deleteNotification('a'); // will FAIL
      // While 'a' is in flight, ANOTHER session dismisses 'b' — the
      // socket convergence removes it durably.
      h.socket.serverBroadcast(
          {'type': 'DISMISSED', 'notificationId': 'b'});
      final failed = await pending;

      expect(failed, isFalse);
      expect(h.state.map((n) => n.id), contains('a'));
      expect(h.state.map((n) => n.id), isNot(contains('b')),
          reason: 'socket convergence must survive the failed rollback');
    });

    test('a failed dismissal keeps concurrent read-state changes intact',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onDelete = (endpoint) async =>
          endpoint.contains('/a') ? http.Response('{}', 500) : http.Response('{}', 200);
      h.seed([_n('a'), _n('b', isRead: false)]);

      final pending = h.notifier.deleteNotification('a'); // will FAIL
      // Another session marks 'b' read while 'a' is in flight.
      h.notifier.markAsRead('b');
      await pending;

      final b = h.state.firstWhere((n) => n.id == 'b');
      expect(b.isRead, isTrue,
          reason: 'the failed dismissal rollback must not undo the '
              'concurrent read flip');
    });

    test('rollback restores the item at its original position and read state',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.api.onDelete = (endpoint) async =>
          endpoint.contains('/b') ? http.Response('{}', 503) : http.Response('{}', 200);
      h.seed([_n('a'), _n('b', isRead: true), _n('c')]);

      final ok = await h.notifier.deleteNotification('b');
      expect(ok, isFalse);
      // addNotification prepends, so the seeded order on the state is
      // [c, b, a]; the rollback must restore exactly THAT order.
      expect(h.state.map((n) => n.id), ['c', 'b', 'a'],
          reason: 'same order as before the optimistic removal');
      expect(h.state.firstWhere((n) => n.id == 'b').isRead, isTrue);
    });

    test('SAME-ID race: a socket dismissal arriving for the EXACT item '
        'whose delete is in flight must survive that delete failing',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a')]);

      // Hold the DELETE open so the socket event lands mid-flight.
      final gate = Completer<http.Response>();
      h.api.onDelete = (_) => gate.future;
      final pending = h.notifier.deleteNotification('a');

      // While 'a' is in flight, ANOTHER session dismisses the SAME
      // item — the server confirms it durably for the whole account.
      h.socket.serverBroadcast(
          {'type': 'DISMISSED', 'notificationId': 'a'});

      // Our own request is then rejected (500). The pre-fix rollback
      // would resurrect 'a' because the list no longer contained it.
      gate.complete(http.Response('{}', 500));
      final ok = await pending;

      expect(ok, isFalse);
      expect(h.state.map((n) => n.id), isNot(contains('a')),
          reason: "the server's confirmed dismissal outranks our "
              'rejected request — the item can never resurrect');
    });

    test('dismissing an item another session already dismissed is idempotent',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('a')]);
      h.socket.serverBroadcast(
          {'type': 'DISMISSED', 'notificationId': 'a'});
      final ok = await h.notifier.deleteNotification('a');
      expect(ok, isTrue, reason: 'already gone locally + server 200 = done');
      expect(h.state, isEmpty);
    });
  });

  group('unread count follows the durable list', () {
    test('dismissing an unread row updates the derived badge consistently',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('keep-unread'), _n('dismiss-me'), _n('read', isRead: true)]);

      expect(h.container.read(unreadCountProvider), 2);

      await h.notifier.deleteNotification('dismiss-me');

      expect(h.container.read(unreadCountProvider), 1,
          reason: 'server counts exclude dismissed rows; the derived client '
              'count must agree, so badge and list can never disagree');
    });

    test('a REJECTED dismissal keeps the unread count stable', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.seed([_n('unread', isRead: false)]);

      h.api.onDelete = (_) async => http.Response('boom', 500);
      await h.notifier.deleteNotification('unread');

      expect(h.container.read(unreadCountProvider), 1,
          reason: 'rollback means the badge never flickers on a failed swipe');
    });
  });
}
