import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/data/demo_seed_marketplace.dart';

/// G2/G3 — the demo nearby search must mirror the REAL
/// `/business/search/nearby` contract:
///   • offset pagination (`page`) — the previous cursor demo silently
///     replayed page 1 when the real client asked for page 2;
///   • every row embeds the slim `businessProfile` (id, bizId,
///     businessName, category, logoUrl, isVerified, averageRating,
///     totalEscrows) — the embedded facts power Near You rows and the
///     category-correct map markers without a second fetch;
///   • distanceKm is the real haversine from the request lat/lng and the
///     feed is distance-ordered across page boundaries.
void main() {
  group('DemoMarketplaceSeed.searchNearby — real contract', () {
    test('page 2 returns the SECOND page, not a replay of page 1', () {
      final page1 = DemoMarketplaceSeed.searchNearby(limit: 5, page: 0);
      final page2 = DemoMarketplaceSeed.searchNearby(limit: 5, page: 1);

      final rows1 = (page1['locations'] as List).cast<Map<String, dynamic>>();
      final rows2 = (page2['locations'] as List).cast<Map<String, dynamic>>();

      expect(rows1.length, 5);
      expect(page1['hasMore'], isTrue);
      expect(page1['nextPage'], 1);

      expect(rows2.length, 3, reason: '8 seeded locations, 5 per page');
      expect(page2['hasMore'], isFalse);
      expect(page2['nextPage'], isNull);

      // The regression this guards: identical rows on page 2 (the old
      // cursor drift replayed page 1 because the real client sends
      // `page`, never `cursor`).
      final ids1 = rows1.map((r) => r['id']).toSet();
      final ids2 = rows2.map((r) => r['id']).toSet();
      expect(
        ids2.intersection(ids1),
        isEmpty,
        reason: 'page 2 must contain different rows than page 1',
      );
    });

    test('every row embeds the slim businessProfile with the real fields', () {
      final res = DemoMarketplaceSeed.searchNearby();
      final rows = (res['locations'] as List).cast<Map<String, dynamic>>();
      expect(rows.length, 8);

      for (final row in rows) {
        final profile = row['businessProfile'];
        expect(
          profile,
          isA<Map<String, dynamic>>(),
          reason: 'row ${row['id']} must embed its owning profile',
        );
        // EXACTLY the field set the real backend include ships.
        expect(profile.keys.toSet(), {
          'id',
          'bizId',
          'businessName',
          'category',
          'logoUrl',
          'isVerified',
          'averageRating',
          'totalEscrows',
        }, reason: 'embedded profile field set must match production');
        expect(profile['bizId'], isNotNull);
        expect((profile['businessName'] as String).isNotEmpty, isTrue);
        expect(profile['category'], isNotNull);

        // Coherence: the embedded profile is the OWNER of the row.
        expect(profile['id'], row['businessProfileId']);
      }
    });

    test(
      'distanceKm is the haversine from the request origin, 0.1 km step',
      () {
        // Seeded location: _restaurantLocation (see the seed). Use the
        // seeded coordinates themselves to compute the expected distance.
        final seeded = DemoMarketplaceSeed.allBusinesses().first;
        final loc = (seeded['locations'] as List).first as Map<String, dynamic>;
        final lat = loc['latitude'] as num;
        final lng = loc['longitude'] as num;

        // Exactly on the location → 0.0 km.
        final onIt = DemoMarketplaceSeed.searchNearby(
          lat: lat.toDouble(),
          lng: lng.toDouble(),
        );
        final first = (onIt['locations'] as List).first as Map<String, dynamic>;
        expect(first['businessProfileId'], loc['businessProfileId']);
        expect(first['distanceKm'], 0.0);

        // ~0.111 km north (0.001° lat) → 0.1 after rounding.
        final near = DemoMarketplaceSeed.searchNearby(
          lat: lat.toDouble() - 0.001,
          lng: lng.toDouble(),
        );
        final shifted =
            (near['locations'] as List).first as Map<String, dynamic>;
        expect(shifted['distanceKm'], 0.1);
      },
    );

    test('rows are sorted ascending by distance across pages', () {
      final res = DemoMarketplaceSeed.searchNearby(
        lat: 5.60,
        lng: -0.19,
        limit: 3,
      );
      final rows = (res['locations'] as List).cast<Map<String, dynamic>>();
      expect(rows.length, 3);
      for (var i = 1; i < rows.length; i++) {
        expect(
          (rows[i - 1]['distanceKm'] as num) <= (rows[i]['distanceKm'] as num),
          isTrue,
          reason: 'nearby feed must be distance-ordered (page 1)',
        );
      }

      // Page 2 continues the GLOBAL ordering, not a fresh sort of page 2.
      final res2 = DemoMarketplaceSeed.searchNearby(
        lat: 5.60,
        lng: -0.19,
        limit: 3,
        page: 1,
      );
      final rows2 = (res2['locations'] as List).cast<Map<String, dynamic>>();
      final lastPage1 = rows.last['distanceKm'] as num;
      for (final row in rows2) {
        expect(
          (row['distanceKm'] as num) >= lastPage1,
          isTrue,
          reason: 'page 2 rows must continue the global distance order',
        );
      }
    });

    test('filters still narrow the nearby feed', () {
      final retail = DemoMarketplaceSeed.searchNearby(
        lat: 5.60,
        lng: -0.19,
        category: 'RETAIL',
      );
      final rows = (retail['locations'] as List);
      expect(rows.length, 2);
      for (final row in rows) {
        final profile = row['businessProfile'] as Map<String, dynamic>;
        expect(profile['category'], 'RETAIL');
      }
    });

    test('no origin → no fabricated distances, canonical order preserved', () {
      final res = DemoMarketplaceSeed.searchNearby();
      final rows = (res['locations'] as List).cast<Map<String, dynamic>>();
      for (final row in rows) {
        expect(
          row.containsKey('distanceKm'),
          isFalse,
          reason: 'without request lat/lng no distance may be invented',
        );
      }
    });
  });
}
