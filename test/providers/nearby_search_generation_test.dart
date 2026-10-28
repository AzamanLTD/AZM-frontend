import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';

/// G3 — stale-response guard for the Near You feed. The user can change
/// position/category/query (or leave the surface) while a slow nearby
/// request is in flight; the LAST-ARRIVING response must never overwrite
/// the newer authoritative one, and a cleared feed can never be
/// resurrected by a late response.

/// Controllable service: each pending searchNearby returns a completer the
/// test completes in a chosen order, proving which response survives.
class _ScriptedService extends BusinessService {
  final List<Completer<NearbyPage>> _pending = [];

  @override
  Future<NearbyPage> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    String? q,
    bool? verified,
    int limit = 20,
    int page = 0,
  }) async {
    final c = Completer<NearbyPage>();
    _pending.add(c);
    return c.future;
  }
}

BusinessLocation _loc(String id, String name) => BusinessLocation.fromJson({
  'id': id,
  'businessProfileId': 'bp-$id',
  'label': name,
  'address': 'Accra',
  'latitude': 5.56,
  'longitude': -0.19,
  'galleryUrls': <String>[],
  'isPrimary': true,
  'isActive': true,
});

void main() {
  test(
    'a STALE searchNearby response can never overwrite the newer one',
    () async {
      final service = _ScriptedService();
      final notifier = NearbySearchNotifier(service);

      // First search (position A) — in flight.
      final f1 = notifier.searchNearby(lat: 5.60, lng: -0.20);
      // Second search (position B) supersedes it before either lands.
      final f2 = notifier.searchNearby(lat: 5.61, lng: -0.19);

      expect(service._pending.length, 2);

      // The STALE (A) response completes LAST — the classic
      // slow-network reorder. It must be discarded whole.
      service._pending[1].complete((
        locations: [_loc('b1', 'Newest result')],
        hasMore: false,
        nextPage: null,
      ));
      await Future<void>.delayed(Duration.zero);
      // A lands after B's state was applied — must NOT touch the state.
      service._pending[0].complete((
        locations: [_loc('a1', 'Stale result'), _loc('a2', 'Stale 2')],
        hasMore: false,
        nextPage: null,
      ));
      await f1;
      await f2;

      final state = notifier.state;
      expect(
        state.locations.length,
        1,
        reason: 'stale page must be discarded, not spliced',
      );
      expect(state.locations.single.id, 'b1');
      expect(state.lat, 5.61, reason: 'the NEW origin must survive');
      expect(state.isLoading, isFalse);
    },
  );

  test(
    'clear() kills in-flight responses — the feed cannot be resurrected',
    () async {
      final service = _ScriptedService();
      final notifier = NearbySearchNotifier(service);

      final f = notifier.searchNearby(lat: 5.60, lng: -0.20);
      expect(notifier.state.isLoading, isTrue);

      notifier.clear();
      expect(notifier.state.locations, isEmpty);
      expect(notifier.state.isLoading, isFalse);

      // The late response arrives after the user left the surface.
      service._pending.single.complete((
        locations: [_loc('ghost', 'Should not resurrect')],
        hasMore: true,
        nextPage: 2,
      ));
      await f;
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.state.locations,
        isEmpty,
        reason: 'a cleared feed must never be resurrected by a late page',
      );
      expect(notifier.state.hasMore, isFalse);
    },
  );

  test('a stale loadMore tail cannot splice into a superseded feed', () async {
    final service = _ScriptedService();
    final notifier = NearbySearchNotifier(service);

    // Prime a loaded page 0 (category filter active).
    final f0 = notifier.searchNearby(lat: 5.60, lng: -0.20, category: 'RETAIL');
    service._pending[0].complete((
      locations: [_loc('r1', 'Retail 1')],
      hasMore: true,
      nextPage: 1,
    ));
    await f0;
    expect(notifier.state.locations.single.id, 'r1');

    // Page 1 tail in flight…
    final fTail = notifier.loadMore();
    expect(service._pending.length, 2);

    // …but the user switches category — a NEW search supersedes the feed.
    final fNew = notifier.searchNearby(lat: 5.60, lng: -0.20, category: 'FOOD');
    service._pending[1].complete((
      locations: [_loc('tail-of-retail', 'Stale tail')],
      hasMore: false,
      nextPage: null,
    ));
    await fTail;
    await Future<void>.delayed(Duration.zero);

    // The new search's page lands.
    service._pending[2].complete((
      locations: [_loc('f1', 'Food 1')],
      hasMore: false,
      nextPage: null,
    ));
    await fNew;

    final state = notifier.state;
    expect(state.category, 'FOOD');
    expect(state.locations.map((l) => l.id), [
      'f1',
    ], reason: 'the stale retail tail must never splice into the food feed');
    expect(state.isLoadingMore, isFalse);
  });

  test('a genuine loadMore still appends when nothing supersedes it', () async {
    final service = _ScriptedService();
    final notifier = NearbySearchNotifier(service);

    final f0 = notifier.searchNearby(lat: 5.60, lng: -0.20);
    service._pending[0].complete((
      locations: [_loc('a', 'A')],
      hasMore: true,
      nextPage: 1,
    ));
    await f0;

    final f1 = notifier.loadMore();
    service._pending[1].complete((
      locations: [_loc('b', 'B')],
      hasMore: false,
      nextPage: null,
    ));
    await f1;

    expect(notifier.state.locations.map((l) => l.id), ['a', 'b']);
    expect(notifier.state.hasMore, isFalse);
  });

  test('a stale ERROR can also not overwrite newer success', () async {
    final service = _ScriptedService();
    final notifier = NearbySearchNotifier(service);

    final f1 = notifier.searchNearby(lat: 5.60, lng: -0.20);
    final f2 = notifier.searchNearby(lat: 5.61, lng: -0.19);

    // The newer request succeeds.
    service._pending[1].complete((
      locations: [_loc('ok', 'Fresh')],
      hasMore: false,
      nextPage: null,
    ));
    // The STALE request fails LAST — its error must be dropped, or the
    // feed would flip to a failure state with good data on screen.
    service._pending[0].completeError(Exception('stale network failure'));
    await f1.catchError((_) {});
    await f2;

    final state = notifier.state;
    expect(
      state.error,
      isNull,
      reason: 'a stale failure must not poison fresh data',
    );
    expect(state.locations.single.id, 'ok');
    expect(state.isLoading, isFalse);
  });
}
