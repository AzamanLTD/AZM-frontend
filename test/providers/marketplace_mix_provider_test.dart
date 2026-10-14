// =============================================================================
// MARKETPLACE MIX — provider tests (category select, cross-store fan-out,
// ordering honesty, failure model, interaction recording).
//
// The gateway is faked — these tests pin the COMPOSITION contract:
//   • selecting a category resets and reloads only that category's stores
//   • offers interleave round-robin across stores, in server order per store
//   • a store-page failure is fatal+retryable; per-store listing failures are
//     partial and never empty the feed
//   • offer taps record against the REAL identity fields
//   • no client-side ranking: server order is preserved end-to-end
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway({this.pages = const {}});

  /// category wire → (store pages, keyed by cursor)
  final Map<String, List<MixStorePage>> pages;
  final List<(String category, String? cursor)> searchCalls = [];
  final List<String> productCalls = [];

  /// bizIds whose listing fetch should fail.
  final Set<String> failingBizIds = {};
  var failSearch = false;

  @override
  Set<MixCapability> get supportedCapabilities =>
      const {MixCapability.itemStoreInteractions};

  @override
  Future<MixStorePage> searchStores({
    required String category,
    int limit = 10,
    String? cursor,
  }) async {
    searchCalls.add((category, cursor));
    if (failSearch) throw Exception('network down');
    final pageList = pages[category] ?? const <MixStorePage>[];
    final index = cursor == null ? 0 : int.parse(cursor);
    if (index >= pageList.length) {
      return (stores: <MixStore>[], hasMore: false, nextCursor: null);
    }
    return pageList[index];
  }

  @override
  Future<MixStoreOffers> productsFor(MixStore store, {int limit = 50}) async {
    productCalls.add(store.bizId);
    await Future<void>.delayed(Duration.zero);
    if (failingBizIds.contains(store.bizId)) throw Exception('store down');
    final offers = _catalogues[store.bizId]!
        .map((Map<String, dynamic> row) => MixOffer.fromJson(
              row,
              businessProfileId: store.id,
              bizId: store.bizId,
              businessName: store.businessName,
              businessCategory: store.category,
            ))
        .toList();
    return (store: store, offers: offers);
  }
}

class _RecordingTapRecorder implements MixTapRecorder {
  final List<({String businessProfileId, String productId, String mixCategory})>
      taps = [];

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    required String mixCategory,
  }) {
    taps.add((
      businessProfileId: businessProfileId,
      productId: productId,
      mixCategory: mixCategory,
    ));
  }
}

Map<String, dynamic> _item(String id, String name, [double price = 10]) =>
    {'id': id, 'name': name, 'priceUsdc': price};

final Map<String, List<Map<String, dynamic>>> _catalogues = {
  'BIZ-R': [_item('r1', 'Bolgatti Basket', 22.0)],
  'BIZ-X': [_item('x1', 'Jollof Plate')],
  'BIZ-Y': [_item('y1', 'Jollof Plate')],
  'BIZ-A': [_item('a1', 'Jollof'), _item('a2', 'Waakye')],
  'BIZ-B': [_item('b1', 'Banku'), _item('b2', 'Fufu'), _item('b3', 'Kenkey')],
  'BIZ-C': [_item('c1', 'Pizza')],
};

MixStore _store(String suffix, String category) => MixStore(
      id: 'bp-$suffix',
      bizId: 'BIZ-$suffix',
      businessName: 'Store $suffix',
      category: category,
    );

/// One page: two stores.
List<MixStorePage> _foodPages({bool more = false}) => [
      (
        stores: [_store('A', 'FOOD_BEVERAGE'), _store('B', 'FOOD_BEVERAGE')],
        hasMore: more,
        nextCursor: more ? '1' : null,
      ),
    ];

ProviderContainer _container(_FakeGateway gateway,
    {_RecordingTapRecorder? recorder}) {
  final c = ProviderContainer(overrides: [
    marketplaceMixGatewayProvider.overrideWithValue(gateway),
    if (recorder != null)
      marketplaceMixProvider.overrideWith(
        (ref) => MarketplaceMixNotifier(
          gateway: ref.watch(marketplaceMixGatewayProvider),
          recorder: recorder,
        ),
      ),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('category selection & cross-store composition', () {
    test('selectCategory loads the category\'s stores and their offers',
        () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
      final c = _container(g);
      await c.read(marketplaceMixProvider.notifier).selectCategory('FOOD_BEVERAGE');

      final s = c.read(marketplaceMixProvider);
      expect(s.phase, MixPhase.ready);
      expect(g.searchCalls.first, ('FOOD_BEVERAGE', null));
      expect(s.stores.length, 2);
      expect(s.offers.length, 5); // 2 + 3
      // Every offer carries its OWN store identity.
      expect(
          s.offers.every((o) =>
              o.businessProfileId.isNotEmpty && o.bizId.startsWith('BIZ-')),
          isTrue);
    });

    test('offers interleave round-robin across stores, server order within',
        () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
      final c = _container(g);
      await c.read(marketplaceMixProvider.notifier).selectCategory('FOOD_BEVERAGE');

      final names =
          c.read(marketplaceMixProvider).offers.map((o) => o.name).toList();
      // A(2 items) and B(3 items) interleave: a1,b1,a2,b2,b3 — never all of A
      // then all of B (store-first burying), never any other order.
      expect(names, ['Jollof', 'Banku', 'Waakye', 'Fufu', 'Kenkey']);
    });

    test('switching categories resets the feed to the new category only',
        () async {
      final g = _FakeGateway(pages: {
        'FOOD_BEVERAGE': _foodPages(),
        'RETAIL': [
          (
            stores: [_store('R', 'RETAIL')],
            hasMore: false,
            nextCursor: null,
          ),
        ],
      });
      final c = _container(g);
      final n = c.read(marketplaceMixProvider.notifier);

      await n.selectCategory('FOOD_BEVERAGE');
      await n.selectCategory('RETAIL');

      final s = c.read(marketplaceMixProvider);
      expect(s.categoryWire, 'RETAIL');
      expect(s.stores.map((st) => st.category), everyElement('RETAIL'));
      expect(s.offers.every((o) => o.businessCategory == 'RETAIL'), isTrue);
      // Stale food offers are gone.
      expect(s.offers.any((o) => o.name == 'Jollof'), isFalse);
    });

    test('re-selecting the loaded category is a no-op (no refetch)', () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
      final c = _container(g);
      await c.read(marketplaceMixProvider.notifier).selectCategory('FOOD_BEVERAGE');
      expect(g.searchCalls.length, 1);
      await c.read(marketplaceMixProvider.notifier).selectCategory('FOOD_BEVERAGE');
      expect(g.searchCalls.length, 1);
    });
  });

  group('failure model', () {
    test('a store-page failure is fatal and retryable', () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()})
        ..failSearch = true;
      final c = _container(g);
      final n = c.read(marketplaceMixProvider.notifier);

      await n.selectCategory('FOOD_BEVERAGE');
      expect(c.read(marketplaceMixProvider).phase, MixPhase.failed);
      expect(c.read(marketplaceMixProvider).error, isNotNull);
      expect(c.read(marketplaceMixProvider).offers, isEmpty);

      g.failSearch = false;
      await n.retry();
      final s = c.read(marketplaceMixProvider);
      expect(s.phase, MixPhase.ready);
      expect(s.offers, isNotEmpty);
    });

    test('one store\'s listing failure is partial — the rest still load',
        () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()})
        ..failingBizIds.add('BIZ-A');
      final c = _container(g);
      await c.read(marketplaceMixProvider.notifier).selectCategory('FOOD_BEVERAGE');

      final s = c.read(marketplaceMixProvider);
      expect(s.phase, MixPhase.ready);
      expect(s.failedStores, 1);
      // Store B's three offers survived.
      expect(s.offers.map((o) => o.name), ['Banku', 'Fufu', 'Kenkey']);
      expect(s.offers.every((o) => o.bizId == 'BIZ-B'), isTrue);
    });

    test('empty category (no stores) is ready with no offers', () async {
      final g = _FakeGateway(pages: {'LOGISTICS': []});
      final c = _container(g);
      await c.read(marketplaceMixProvider.notifier).selectCategory('LOGISTICS');
      final s = c.read(marketplaceMixProvider);
      expect(s.phase, MixPhase.ready);
      expect(s.offers, isEmpty);
      expect(s.stores, isEmpty);
    });
  });

  group('pagination', () {
    test('loadMoreStores appends the next page without reshuffling', () async {
      final g = _FakeGateway(pages: {
        'FOOD_BEVERAGE': [
          (
            stores: [_store('A', 'FOOD_BEVERAGE'), _store('B', 'FOOD_BEVERAGE')],
            hasMore: true,
            nextCursor: '1',
          ),
          (
            stores: [_store('C', 'FOOD_BEVERAGE')],
            hasMore: false,
            nextCursor: null,
          ),
        ],
      });
      final c = _container(g);
      final n = c.read(marketplaceMixProvider.notifier);

      await n.selectCategory('FOOD_BEVERAGE');
      final firstNames =
          c.read(marketplaceMixProvider).offers.map((o) => o.name).toList();
      expect(firstNames, ['Jollof', 'Banku', 'Waakye', 'Fufu', 'Kenkey']);

      await n.loadMoreStores();
      final s = c.read(marketplaceMixProvider);
      // Appended after the existing feed — nothing the user saw moved.
      expect(s.offers.map((o) => o.name).take(5), firstNames);
      expect(s.offers.last.name, 'Pizza');
      expect(s.hasMoreStores, isFalse);
      expect(g.searchCalls.last, ('FOOD_BEVERAGE', '1'));
    });

    test('loadMoreStores is a no-op without a cursor', () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
      final c = _container(g);
      final n = c.read(marketplaceMixProvider.notifier);
      await n.selectCategory('FOOD_BEVERAGE');
      await n.loadMoreStores();
      expect(g.searchCalls.length, 1);
    });
  });

  group('interaction recording (real contract, fake transport)', () {
    test('a tap records the item+store pair through the real identity',
        () async {
      final g = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
      final recorder = _RecordingTapRecorder();
      final c = _container(g, recorder: recorder);
      final n = c.read(marketplaceMixProvider.notifier);
      await n.selectCategory('FOOD_BEVERAGE');

      final offer = c.read(marketplaceMixProvider).offers.first;
      n.trackOfferTap(offer);

      expect(recorder.taps.single.businessProfileId, offer.businessProfileId);
      expect(recorder.taps.single.productId, offer.productId);
      expect(recorder.taps.single.mixCategory, 'FOOD_BEVERAGE');
    });

    test('two stores\' same-named items record distinct identities', () async {
      final g = _FakeGateway(pages: {
        'FOOD_BEVERAGE': [
          (
            stores: [
              const MixStore(id: 'bp-1', bizId: 'BIZ-X', businessName: 'A', category: 'FOOD_BEVERAGE'),
              const MixStore(id: 'bp-2', bizId: 'BIZ-Y', businessName: 'B', category: 'FOOD_BEVERAGE'),
            ],
            hasMore: false,
            nextCursor: null,
          ),
        ],
      });
      final recorder = _RecordingTapRecorder();
      final c = _container(g, recorder: recorder);
      final n = c.read(marketplaceMixProvider.notifier);
      await n.selectCategory('FOOD_BEVERAGE');

      final offers = c.read(marketplaceMixProvider).offers;
      expect(offers.length, 2);
      expect(offers.first.name, offers.last.name); // same item name
      n.trackOfferTap(offers.first);
      n.trackOfferTap(offers.last);

      final ids = recorder.taps.map((t) => '${t.businessProfileId}:${t.productId}');
      expect(ids.toSet().length, 2, reason: 'item+store pairs must stay distinct');
    });

    test('taps are NOT recorded when the capability is unsupported', () async {
      final g = _NoInteractionGateway();
      final recorder = _RecordingTapRecorder();
      final c = ProviderContainer(overrides: [
        marketplaceMixGatewayProvider.overrideWithValue(g),
        marketplaceMixProvider.overrideWith(
          (ref) => MarketplaceMixNotifier(
            gateway: ref.watch(marketplaceMixGatewayProvider),
            recorder: recorder,
          ),
        ),
      ]);
      addTearDown(c.dispose);
      final n = c.read(marketplaceMixProvider.notifier);
      await n.selectCategory('FOOD_BEVERAGE');

      n.trackOfferTap(c.read(marketplaceMixProvider).offers.first);
      expect(recorder.taps, isEmpty);
    });
  });
}

class _NoInteractionGateway extends _FakeGateway {
  _NoInteractionGateway()
      : super(pages: {
          'FOOD_BEVERAGE': _foodPages(),
        });

  @override
  Set<MixCapability> get supportedCapabilities => const {};
}
