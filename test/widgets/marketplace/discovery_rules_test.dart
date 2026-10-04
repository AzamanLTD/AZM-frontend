// Pure rules behind the portal (Overhaul 02): which chips show, what a
// world card says, what the local pulse counts, which placeholders apply.

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/widgets/marketplace/discovery/intent_rail.dart';
import 'package:azaman/widgets/marketplace/discovery/local_pulse.dart';
import 'package:azaman/widgets/marketplace/discovery/marketplace_placeholders.dart';
import 'package:azaman/widgets/marketplace/discovery/trust_mark.dart';
import 'package:azaman/widgets/marketplace/discovery/utility_rail.dart';
import 'package:azaman/widgets/marketplace/discovery/world_deck.dart';

BusinessLocation _loc(String bizProfileId, Map<String, dynamic>? hours) =>
    BusinessLocation(
      id: 'l-$bizProfileId',
      businessProfileId: bizProfileId,
      label: 'Main',
      address: 'x',
      latitude: 0,
      longitude: 0,
      galleryUrls: const [],
      isPrimary: true,
      isActive: true,
      operatingHours: hours,
    );

BusinessProfile _biz(
  String id, {
  String category = 'FOOD_BEVERAGE',
  bool verified = false,
  String kyb = 'UNVERIFIED',
  double rating = 0,
  Map<String, dynamic>? hours,
  String? cover,
}) =>
    BusinessProfile(
      id: id,
      bizId: 'BIZ-$id',
      businessName: id,
      category: category,
      isVerified: verified,
      isSuspended: false,
      kybStatus: kyb,
      totalEscrows: 0,
      completedEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: rating,
      username: id,
      coverImageUrl: cover,
      locations: [_loc(id, hours)],
    );

void main() {
  final wedNoon = DateTime(2026, 10, 7, 12, 0);
  const all = {DiscoverySignal.openNow, DiscoverySignal.nearby, DiscoverySignal.topRated};

  group('visibleIntents', () {
    test('worlds always show; Nearby/Saves/Recent are conditional', () {
      final none = visibleIntents(supported: const {}, hasSaves: false, hasRecent: false)
          .map((i) => i.label)
          .toList();
      expect(none, ['Eat', 'Shop', 'Ride', 'Stay']);
      final everything = visibleIntents(supported: all, hasSaves: true, hasRecent: true)
          .map((i) => i.label)
          .toList();
      expect(everything, ['Eat', 'Shop', 'Ride', 'Stay', 'Nearby', 'My saves', 'Recent']);
    });
  });

  group('visibleUtilityFilters', () {
    test('only supported signals render; Saved needs saves', () {
      expect(visibleUtilityFilters(supported: const {}, hasSaves: false), isEmpty);
      expect(
        visibleUtilityFilters(supported: const {DiscoverySignal.openNow}, hasSaves: true),
        [UtilityFilter.openNow, UtilityFilter.saved],
      );
      expect(
        visibleUtilityFilters(supported: all, hasSaves: false),
        [UtilityFilter.nearMe, UtilityFilter.openNow, UtilityFilter.topRated],
      );
    });
  });

  group('buildWorldCards', () {
    DiscoverySnapshot snap(List<BusinessProfile> catalog, {Map<String, double>? dist}) =>
        DiscoverySnapshot(
          catalog: catalog,
          featured: const [],
          distanceKmByBusinessId: dist,
          savedBizIds: const {},
          now: wedNoon,
        );

    test('one card per primary world, in primary order, with blueprint promise', () {
      final cards = buildWorldCards(snap(const []), all);
      expect(cards.map((c) => c.category.wire),
          BusinessCategories.primary.map((c) => c.wire));
      expect(cards.every((c) => c.promise.isNotEmpty), isTrue);
    });

    test('empty catalog keeps every world enabled (nothing loaded yet)', () {
      final cards = buildWorldCards(snap(const []), all);
      expect(cards.every((c) => c.enabled), isTrue);
      expect(cards.first.signalLine, '0 places');
    });

    test('loaded catalog disables genuinely empty worlds', () {
      final cards = buildWorldCards(snap([_biz('a', category: 'RETAIL')]), all);
      final retail = cards.singleWhere((c) => c.category.wire == 'RETAIL');
      final food = cards.singleWhere((c) => c.category.wire == 'FOOD_BEVERAGE');
      expect(retail.enabled, isTrue);
      expect(retail.signalLine, '1 place');
      expect(food.enabled, isFalse);
    });

    test('signal line: open-now beats distance beats count', () {
      final catalog = [
        _biz('a', hours: {'wed': '8:00-22:00'}),
        _biz('b', hours: {'wed': '8:00-9:00'}),
        _biz('c'),
      ];
      final food = buildWorldCards(snap(catalog, dist: {'a': 0.4, 'b': 0.9, 'c': 5}), all)
          .singleWhere((c) => c.category.wire == 'FOOD_BEVERAGE');
      expect(food.count, 3);
      expect(food.openNow, 1);
      expect(food.withinKm, 2);
      expect(food.signalLine, '1 open now');

      final noOpen = buildWorldCards(
              snap([_biz('b', hours: {'wed': '8:00-9:00'})], dist: {'b': 0.9}), all)
          .singleWhere((c) => c.category.wire == 'FOOD_BEVERAGE');
      expect(noOpen.signalLine, '1 within 1 km');
    });

    test('unsupported signals are null, never zero', () {
      final food = buildWorldCards(snap([_biz('a', hours: {'wed': '8:00-22:00'})]), const {})
          .singleWhere((c) => c.category.wire == 'FOOD_BEVERAGE');
      expect(food.openNow, isNull);
      expect(food.withinKm, isNull);
      expect(food.signalLine, '1 place');
    });

    test('REAL_ESTATE businesses count toward Hotels', () {
      final hotels = buildWorldCards(snap([_biz('h', category: 'REAL_ESTATE')]), all)
          .singleWhere((c) => c.category.wire == 'HOSPITALITY');
      expect(hotels.count, 1);
    });

    test('covers are real urls only, best-rated first, max 3', () {
      final catalog = [
        _biz('a', rating: 3, cover: 'a.jpg'),
        _biz('b', rating: 5, cover: 'b.jpg'),
        _biz('c', rating: 4, cover: ''),
        _biz('d', rating: 4.5, cover: 'd.jpg'),
        _biz('e', rating: 1, cover: 'e.jpg'),
      ];
      final food = buildWorldCards(snap(catalog), all)
          .singleWhere((c) => c.category.wire == 'FOOD_BEVERAGE');
      expect(food.coverUrls, ['b.jpg', 'd.jpg', 'a.jpg']);
    });
  });

  group('buildLocalPulse', () {
    test('counts open and within 2 km; hidden lines are null', () {
      final s = DiscoverySnapshot(
        catalog: [
          _biz('a', hours: {'wed': '8:00-22:00'}),
          _biz('b', hours: {'wed': '8:00-22:00'}),
          _biz('c'),
        ],
        featured: const [],
        distanceKmByBusinessId: const {'a': 1.5, 'b': 2.5, 'c': 1.9},
        savedBizIds: const {},
        now: wedNoon,
      );
      final full = buildLocalPulse(s, all);
      expect(full.openNow, 2);
      expect(full.nearby, 2);
      expect(full.isEmpty, isFalse);

      final none = buildLocalPulse(s, const {});
      expect(none.openNow, isNull);
      expect(none.nearby, isNull);
      expect(none.isEmpty, isTrue);
    });
  });

  group('MarketplacePlaceholders', () {
    test('store scope names the store and its vertical', () {
      expect(
        MarketplacePlaceholders.forScope(MarketplaceSearchScope.store,
            world: 'FOOD_BEVERAGE', storeName: 'Auntie Muni').first,
        'Search for food in "Auntie Muni"',
      );
      expect(
        MarketplacePlaceholders.forScope(MarketplaceSearchScope.store, world: 'OTHER', storeName: 'X'),
        ['Search in "X"'],
      );
    });

    test('REAL_ESTATE is treated as the hotels world', () {
      expect(
        MarketplacePlaceholders.forScope(MarketplaceSearchScope.world, world: 'REAL_ESTATE'),
        ['Search hotels and stays'],
      );
    });

    test('marketplace scope uses the generic rotation', () {
      expect(MarketplacePlaceholders.forScope(MarketplaceSearchScope.marketplace),
          MarketplacePlaceholders.marketplace);
    });
  });

  group('trustLevelOf', () {
    test('verified > pending > none', () {
      expect(trustLevelOf(_biz('a', verified: true, kyb: 'PENDING')), TrustLevel.verified);
      expect(trustLevelOf(_biz('a', kyb: 'PENDING')), TrustLevel.kybPending);
      expect(trustLevelOf(_biz('a', kyb: 'REJECTED')), TrustLevel.none);
    });
  });
}