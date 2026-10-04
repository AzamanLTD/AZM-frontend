// =============================================================================
// PR #142 close-out §2 — the marketplace RELEVANCE reminder signal.
//
// Truthfulness contract under test:
//   * WHERE  → the existing world memory (freshness window, most-recent
//              touched wins; stale memory is not context).
//   * WHAT   → the existing discovery snapshot (real search/featured
//              results only; featured preferred over catalog order).
//   * COPY   → "Relevant in <Category>" — the label comes from the
//              canonical BusinessCategories utility, and the signal never
//              claims "new" (the data model has no trustworthy newness).
//   * EMPTY  → no fresh memory, or no real match, or nothing openable →
//              NO reminder. Nothing is manufactured to fill the deck.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';

BusinessProfile _biz(
  String id,
  String name, {
  String category = 'FOOD_BEVERAGE',
  bool suspended = false,
}) =>
    BusinessProfile(
      id: id,
      bizId: 'BIZ-$id',
      businessName: name,
      category: category,
      isVerified: true,
      isSuspended: suspended,
      kybStatus: 'VERIFIED',
      totalEscrows: 3,
      completedEscrows: 3,
      userId: 1,
      totalVolume: 100,
      averageRating: 4.5,
      username: 'vendor-$id',
    );

void main() {
  final now = DateTime(2026, 10, 4, 12, 0);

  ProviderContainer make({
    List<BusinessProfile> catalog = const [],
    List<BusinessProfile> featured = const [],
    DateTime Function()? clock,
  }) {
    final c = ProviderContainer(overrides: [
      discoveryClockProvider.overrideWithValue(clock ?? () => now),
      worldMemoryProvider.overrideWith(
          (_) => WorldMemoryNotifier(clock: clock ?? () => now)),
      discoverySnapshotProvider.overrideWithValue(DiscoverySnapshot(
        catalog: catalog,
        featured: featured,
        distanceKmByBusinessId: null,
        savedBizIds: const {},
        now: clock?.call() ?? now,
      )),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('no fresh marketplace memory → no reminder', () {
    final c = make(
        catalog: [_biz('b1', 'Auntie Muni')]);
    expect(c.read(marketplaceRelevanceProvider), isNull);
  });

  test('fresh category with no matching business → no reminder', () {
    final c = make(
        // The user browsed RETAIL, but only a restaurant exists in the
        // snapshot — a restaurant is NOT relevant to a retail visit.
        catalog: [_biz('b1', 'Auntie Muni', category: 'FOOD_BEVERAGE')]);
    c.read(worldMemoryProvider.notifier).remember('RETAIL');
    final r = c.read(marketplaceRelevanceProvider);
    expect(r, isNull);
  });

  test('stale memory → ignored', () {
    var t = now;
    final c = make(
        catalog: [_biz('b1', 'Auntie Muni')],
        clock: () => t,
    );
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    t = now.add(const Duration(hours: 1)); // beyond the 30-minute window
    c.invalidate(marketplaceRelevanceProvider);
    expect(c.read(marketplaceRelevanceProvider), isNull);
  });

  test('fresh category with a matching real business → the correct reminder',
      () {
    final c = make(
        catalog: [_biz('b1', 'Auntie Muni', category: 'FOOD_BEVERAGE')]);
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    final r = c.read(marketplaceRelevanceProvider)!;
    expect(r.worldWire, 'FOOD_BEVERAGE');
    expect(r.categoryLabel, 'Restaurants');
    expect(r.business.id, 'b1');
    expect(r.business.businessName, 'Auntie Muni');
  });

  test('most recently touched fresh context wins', () {
    var t = now;
    final c = make(
      clock: () => t,
      catalog: [
        _biz('retail-1', 'Kantamanto Kicks', category: 'RETAIL'),
        _biz('food-1', 'Auntie Muni', category: 'FOOD_BEVERAGE'),
      ],
    );
    final n = c.read(worldMemoryProvider.notifier);
    n.remember('FOOD_BEVERAGE');
    t = now.add(const Duration(minutes: 5));
    n.remember('RETAIL'); // touched after — this is the context that wins
    final r = c.read(marketplaceRelevanceProvider)!;
    expect(r.worldWire, 'RETAIL');
    expect(r.categoryLabel, 'Retail');
    expect(r.business.id, 'retail-1');
  });

  test('category mapping uses the canonical BusinessCategories utility',
      () {
    final c = make(catalog: [_biz('b1', 'Auntie Muni')]);
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    final r = c.read(marketplaceRelevanceProvider)!;
    // The label IS the canonical one — no parallel category map exists.
    expect(r.categoryLabel, BusinessCategories.labelFor('FOOD_BEVERAGE'));
    expect(r.categoryLabel, isNot('New'));
  });

  test('featured real results are preferred over catalog order', () {
    final c = make(
      catalog: [_biz('cat-1', 'Catalog Diner')],
      featured: [_biz('feat-1', 'Featured Chop Bar')],
    );
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    final r = c.read(marketplaceRelevanceProvider)!;
    expect(r.business.id, 'feat-1');
  });

  test('suspended or unopenable businesses do not earn the reminder', () {
    final c = make(catalog: [
      _biz('b1', 'Suspended Spot', suspended: true),
      _biz('b2', 'Open Spot'),
    ]);
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    final r = c.read(marketplaceRelevanceProvider)!;
    expect(r.business.id, 'b2');
  });

  test('no fabricated "new" claim — the signal carries relevance only', () {
    final c = make(catalog: [_biz('b1', 'Auntie Muni')]);
    c.read(worldMemoryProvider.notifier).remember('FOOD_BEVERAGE');
    final r = c.read(marketplaceRelevanceProvider)!;
    // The derived signal names a real business and a real category. It
    // deliberately exposes no recency/newness of its own — the deck's copy
    // ("Relevant in …") is the only wording, and the deck test pins it.
    expect(r.worldWire, 'FOOD_BEVERAGE');
    expect(r.business.businessName, 'Auntie Muni');
  });
}
