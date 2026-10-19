// =============================================================================
// MARKETPLACE MIX — provider tests (canonical discovery endpoint paging).
//
// The gateway is faked — these tests pin the STATE contract:
//   • one bounded request per page; the selected category AND filters are
//     preserved while paging; cursor passed verbatim
//   • changing category or toggling a filter RESETS pagination and stale
//     results; a same-selection no-op does not re-request
//   • stale-response protection: a response for a superseded request never
//     overwrites the newer selection's feed
//   • typed failures render distinct states: 404 → disabled, 422 →
//     invalidRequest, network → failed (retryable), 200-empty → ready
//   • loadMore appends (never reshuffles) and is a no-op without a cursor
//   • offer taps record against the REAL identity fields
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway({this.behavior});

  /// Function receiving the full request; returns a page or throws.
  Future<MixDiscoveryPage> Function(_Request req)? behavior;
  final requests = <_Request>[];

  @override
  Set<MixCapability> get supportedCapabilities => const {
    MixCapability.itemStoreInteractions,
  };

  @override
  Future<MixDiscoveryPage> fetchItems({
    String? category,
    String? q,
    List<String> taxonomies = const [],
    String? city,
    String? region,
    int? limit,
    String? cursor,
  }) async {
    final req = _Request(
      category: category,
      q: q,
      taxonomies: List.of(taxonomies),
      city: city,
      region: region,
      limit: limit,
      cursor: cursor,
    );
    requests.add(req);
    await Future<void>.delayed(Duration.zero);
    if (behavior == null) {
      return (offers: <MixOffer>[], nextCursor: null);
    }
    return await behavior!(req);
  }
}

class _Request {
  final String? category;
  final String? q;
  final List<String> taxonomies;
  final String? city;
  final String? region;
  final int? limit;
  final String? cursor;

  _Request({
    this.category,
    this.q,
    this.taxonomies = const [],
    this.city,
    this.region,
    this.limit,
    this.cursor,
  });

  @override
  String toString() =>
      'category=$category taxonomies=$taxonomies limit=$limit cursor=$cursor';
}

MixDiscoveryPage _page(List<String> ids, String? next) => (
  offers: ids
      .map(
        (id) => MixOffer(
          productId: id,
          businessId: 'bp-$id',
          bizId: 'BIZ-$id',
          businessName: 'Store $id',
          businessCategory: 'FOOD_BEVERAGE',
          name: 'Item $id',
          price: const MixOfferPrice.fixedGhs('10.00'),
        ),
      )
      .toList(),
  nextCursor: next,
);

class _RecordingTapRecorder implements MixTapRecorder {
  final taps = <(String, String, String?)>[];

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    String? mixCategory,
  }) {
    taps.add((businessProfileId, productId, mixCategory));
  }
}

ProviderContainer _container(
  _FakeGateway gateway, [
  _RecordingTapRecorder? rec,
]) {
  final c = ProviderContainer(
    overrides: [
      marketplaceMixGatewayProvider.overrideWithValue(gateway),
      if (rec != null)
        marketplaceMixProvider.overrideWith(
          (ref) => MarketplaceMixNotifier(
            gateway: ref.watch(marketplaceMixGatewayProvider),
            recorder: rec,
          ),
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

MarketplaceMixNotifier _notifier(ProviderContainer c) =>
    c.read(marketplaceMixProvider.notifier);

void main() {
  test('initial load: ONE request, NO category (All default — the gateway '
      'omits the param), default page size, no cursor', () async {
    final g = _FakeGateway()
      ..behavior = (req) async => _page(['a', 'b'], 'CUR-1');
    final c = _container(g);
    await _notifier(c).load();

    expect(g.requests, hasLength(1));
    // NULL is the unfiltered All feed — no invented server value, no
    // silent Eat default (the retired contract's bias).
    expect(g.requests.single.category, isNull);
    expect(g.requests.single.taxonomies, isEmpty);
    expect(g.requests.single.limit, MarketplaceMixNotifier.kPageSize);
    expect(g.requests.single.cursor, isNull);

    final state = c.read(marketplaceMixProvider);
    expect(state.phase, MixPhase.ready);
    expect(state.offers.map((o) => o.productId), ['a', 'b']);
    expect(state.nextCursor, 'CUR-1');
  });

  test(
    'loadMore pages with the cursor and PRESERVES category and filters',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async {
          if (req.cursor == null) return _page(['a'], 'CUR-1');
          if (req.cursor == 'CUR-1') return _page(['b'], 'CUR-2');
          return _page(['c'], null);
        };
      final c = _container(g);
      final n = _notifier(c);
      await n.load();
      await n.selectCategory('FOOD_BEVERAGE');

      await n.toggleTaxonomy('MEALS');
      await n.loadMore();

      expect(g.requests, hasLength(4));
      final paged = g.requests.last;
      expect(
        paged.cursor,
        'CUR-1',
        reason: 'the next page request must carry the server cursor verbatim',
      );
      expect(paged.category, 'FOOD_BEVERAGE');
      expect(paged.taxonomies, [
        'MEALS',
      ], reason: 'filters must be preserved while paging');

      final state = c.read(marketplaceMixProvider);
      expect(state.offers.map((o) => o.productId), ['a', 'b']);
      expect(state.nextCursor, 'CUR-2');
      expect(state.hasMore, isTrue);
    },
  );

  test('loadMore without a cursor is a NO-OP (end of feed)', () async {
    final g = _FakeGateway()..behavior = (req) async => _page(['a'], null);
    final c = _container(g);
    final n = _notifier(c);
    await n.load();
    await n.loadMore();

    expect(g.requests, hasLength(1), reason: 'no cursor → no request');
  });

  test(
    'switching category RESETS the feed: no stale cross-category content',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async =>
            _page([req.category == 'RETAIL' ? 'r1' : 'f1'], null);
      final c = _container(g);
      final n = _notifier(c);
      await n.load();
      expect(c.read(marketplaceMixProvider).offers.single.productId, 'f1');

      await n.selectCategory('RETAIL');

      expect(g.requests.last.category, 'RETAIL');
      expect(g.requests.last.cursor, isNull, reason: 'pagination resets');
      final state = c.read(marketplaceMixProvider);
      expect(state.offers.single.productId, 'r1');
      expect(state.taxonomies, isEmpty, reason: 'chips are category-scoped');
    },
  );

  test('switching category DROPS the previous category\'s chips', () async {
    final g = _FakeGateway()..behavior = (req) async => _page(['x'], null);
    final c = _container(g);
    final n = _notifier(c);
    await n.load();
    await n.toggleTaxonomy('MEALS');
    expect(g.requests.last.taxonomies, ['MEALS']);

    await n.selectCategory('RETAIL');

    expect(g.requests.last.taxonomies, isEmpty);
    expect(c.read(marketplaceMixProvider).taxonomies, isEmpty);
  });

  test(
    'toggling a chip RESETS pagination and refetches with the new set',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async =>
            _page(['a'], req.taxonomies.isEmpty ? 'CUR-1' : null);
      final c = _container(g);
      final n = _notifier(c);
      await n.load();
      await n.loadMore();
      expect(g.requests, hasLength(2));

      await n.toggleTaxonomy('DRINKS');
      expect(g.requests, hasLength(3));
      final after = g.requests.last;
      expect(after.cursor, isNull, reason: 'filter change resets pagination');
      expect(after.taxonomies, ['DRINKS']);
      expect(c.read(marketplaceMixProvider).nextCursor, isNull);

      await n.toggleTaxonomy('DRINKS'); // off again
      expect(g.requests.last.taxonomies, isEmpty);
      expect(c.read(marketplaceMixProvider).taxonomies, isEmpty);
    },
  );

  test('clearTaxonomies refetches page one unfiltered', () async {
    final g = _FakeGateway()..behavior = (req) async => _page(['a'], null);
    final c = _container(g);
    final n = _notifier(c);
    await n.load();
    await n.toggleTaxonomy('MEALS');
    await n.clearTaxonomies();

    expect(g.requests.last.taxonomies, isEmpty);
    expect(c.read(marketplaceMixProvider).phase, MixPhase.ready);
  });

  test('STALE RESPONSE PROTECTION: a slow old-category response cannot '
      'overwrite the newer selection', () async {
    // Page 1 for the FIRST category resolves SLOWLY, after the user has
    // already switched categories. The late result must be discarded.
    final slowFirst = Completer<void>();
    final g = _FakeGateway()
      ..behavior = (req) async {
        if (req.category == 'FOOD_BEVERAGE') {
          await slowFirst.future;
          return _page(['stale'], null);
        }
        return _page(['fresh'], null);
      };
    final c = _container(g);
    final n = _notifier(c);

    final firstLoad = n.selectCategory('FOOD_BEVERAGE');
    await Future<void>.delayed(Duration.zero);
    await n.selectCategory('RETAIL');
    final state = c.read(marketplaceMixProvider);
    expect(state.offers.map((o) => o.productId), [
      'fresh',
    ], reason: 'the newer selection must be the one rendered');

    slowFirst.complete();
    await firstLoad;

    final after = c.read(marketplaceMixProvider);
    expect(after.offers.map((o) => o.productId), [
      'fresh',
    ], reason: 'the stale response must NOT overwrite the newer selection');
    expect(after.categoryWire, 'RETAIL');
  });

  test('a stale loadMore page never appends to a newer feed', () async {
    final gate = Completer<void>();
    final g = _FakeGateway()
      ..behavior = (req) async {
        if (req.cursor == 'CUR-1') {
          await gate.future;
          return _page(['late-page'], null);
        }
        return _page(['a'], 'CUR-1');
      };
    final c = _container(g);
    final n = _notifier(c);
    await n.load();

    final more = n.loadMore();
    await Future<void>.delayed(Duration.zero);
    // The user flips a filter while the page request is in flight.
    await n.toggleTaxonomy('MEALS');
    expect(c.read(marketplaceMixProvider).offers.single.productId, 'a');

    gate.complete();
    await more;
    expect(
      c.read(marketplaceMixProvider).offers.single.productId,
      'a',
      reason: 'a superseded cursor page must not append anywhere',
    );
  });

  test(
    '404 renders the DISABLED state — never an empty success, never failed',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async => throw const MixEndpointDisabledException();
      final c = _container(g);
      await _notifier(c).load();

      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.disabled);
      expect(state.offers, isEmpty);
    },
  );

  test(
    '422 renders INVALID-REQUEST with the server message — no retry loop',
    () async {
      var calls = 0;
      final g = _FakeGateway()
        ..behavior = (req) async {
          calls++;
          throw const MixInvalidFilterException('unknown category: FOO');
        };
      final c = _container(g);
      await _notifier(c).load();

      expect(calls, 1, reason: 'an invalid request is never auto-retried');
      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.invalidRequest);
      expect(state.error, 'unknown category: FOO');
    },
  );

  test(
    'a network/server error renders FAILED (retryable), offers cleared',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async => throw const MixRetryableException('down');
      final c = _container(g);
      await _notifier(c).load();

      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.failed);
      expect(state.offers, isEmpty);
      expect(state.error, isNotNull);
    },
  );

  test('retry after failure reloads the same selection', () async {
    var fail = true;
    final g = _FakeGateway()
      ..behavior = (req) async {
        if (fail) throw const MixRetryableException('down');
        return _page(['a'], null);
      };
    final c = _container(g);
    final n = _notifier(c);
    await n.selectCategory('FOOD_BEVERAGE');
    expect(c.read(marketplaceMixProvider).phase, MixPhase.failed);

    fail = false;
    await n.retry();

    expect(g.requests, hasLength(2));
    expect(g.requests.last.category, 'FOOD_BEVERAGE');
    expect(c.read(marketplaceMixProvider).phase, MixPhase.ready);
  });

  test(
    'a 200-empty feed is a LEGITIMATE empty success, not an error',
    () async {
      final g = _FakeGateway()..behavior = (req) async => _page([], null);
      final c = _container(g);
      await _notifier(c).load();

      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers, isEmpty);
      expect(state.error, isNull);
    },
  );

  test('a failed loadMore keeps the current feed (partial failure)', () async {
    final g = _FakeGateway()
      ..behavior = (req) async {
        if (req.cursor == null) return _page(['a'], 'CUR-1');
        throw const MixRetryableException('page down');
      };
    final c = _container(g);
    final n = _notifier(c);
    await n.load();
    await n.loadMore();

    final state = c.read(marketplaceMixProvider);
    expect(state.phase, MixPhase.ready, reason: 'the visible feed survives');
    expect(state.offers.map((o) => o.productId), ['a']);
    expect(state.loadingMore, isFalse);
    expect(
      state.nextCursor,
      'CUR-1',
      reason: 'the cursor survives so the retry affordance works',
    );
  });

  test(
    'offer taps record the item+store pair with REAL identity fields',
    () async {
      final g = _FakeGateway()..behavior = (req) async => _page(['a'], null);
      final rec = _RecordingTapRecorder();
      final c = _container(g, rec);
      final n = _notifier(c);
      await n.selectCategory('FOOD_BEVERAGE');

      n.trackOfferTap(c.read(marketplaceMixProvider).offers.single);

      expect(rec.taps.single, ('bp-a', 'a', 'FOOD_BEVERAGE'));
    },
  );

  test(
    'a tap in ALL mode records an honest null category (omitted key)',
    () async {
      final g = _FakeGateway()..behavior = (req) async => _page(['a'], null);
      final rec = _RecordingTapRecorder();
      final c = _container(g, rec);
      final n = _notifier(c);
      await n.load();

      n.trackOfferTap(c.read(marketplaceMixProvider).offers.single);

      // No fabricated category wire for the unfiltered feed — null travels
      // to the recorder, which omits the metadata key entirely.
      expect(rec.taps.single, ('bp-a', 'a', null));
    },
  );

  test('a disabled-capability gateway records NO tap', () async {
    final g = _FakeGateway()..behavior = (req) async => _page(['a'], null);
    // _FakeGateway reports itemStoreInteractions; strip it via a subclass.
    final stripped = _NoTapGateway(g.behavior);
    final rec = _RecordingTapRecorder();
    final c = ProviderContainer(
      overrides: [marketplaceMixGatewayProvider.overrideWithValue(stripped)],
    );
    addTearDown(c.dispose);
    final n = c.read(marketplaceMixProvider.notifier);
    await n.load();

    n.trackOfferTap(c.read(marketplaceMixProvider).offers.single);
    expect(rec.taps, isEmpty);
  });

  test(
    'first page: an EMPTY page WITH a cursor is auto-followed until offers '
    'appear (server scan-budget boundary, final acceptance pass 2026-10-19)',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async {
          if (req.cursor == null) return _page([], 'CUR-1');
          if (req.cursor == 'CUR-1') return _page(['a'], 'CUR-2');
          return _page(['b'], null);
        };
      final c = _container(g);
      await _notifier(c).load();

      // Exactly two bounded requests: the initial page plus ONE follow-up.
      expect(g.requests, hasLength(2));
      expect(g.requests.first.cursor, isNull);
      expect(g.requests[1].cursor, 'CUR-1');
      // The continuation preserves the selection exactly.
      expect(g.requests[1].category, isNull);
      expect(g.requests[1].taxonomies, isEmpty);
      expect(g.requests[1].limit, MarketplaceMixNotifier.kPageSize);

      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers.map((o) => o.productId), ['a']);
      expect(state.nextCursor, 'CUR-2');
    },
  );

  test(
    'first page: an empty page with a NULL cursor is true exhaustion — NO '
    'continuation request is made',
    () async {
      final g = _FakeGateway()..behavior = (req) async => _page([], null);
      final c = _container(g);
      await _notifier(c).load();

      expect(g.requests, hasLength(1));
      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers, isEmpty);
      expect(state.nextCursor, isNull);
    },
  );

  test(
    'first page: the continuation budget is a HARD limit — at most '
    'kMaxFirstPageContinuations follow-ups, remaining cursor kept truthfully',
    () async {
      final g = _FakeGateway();
      g.behavior = (req) async => _page([], 'CUR-${g.requests.length}');
      final c = _container(g);
      await _notifier(c).load();

      // 1 initial request + the explicit continuation limit.
      expect(
        g.requests,
        hasLength(1 + MarketplaceMixNotifier.kMaxFirstPageContinuations),
      );
      // Every follow-up pages through the previous page's cursor.
      for (var i = 1; i < g.requests.length; i++) {
        expect(g.requests[i].cursor, 'CUR-$i');
      }
      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers, isEmpty);
      // The walk stopped with a source still ahead — the cursor stays so
      // the surface's continuation affordance remains truthful, never a
      // dead end and never a fabricated "no items exist".
      expect(state.nextCursor, isNotNull);
    },
  );

  test(
    'stale-response guard holds MID-WALK: a continuation superseded by a new '
    'category selection never overwrites the newer feed',
    () async {
      final stalePage = Completer<MixDiscoveryPage>();
      final g = _FakeGateway()
        ..behavior = (req) async {
          if (req.cursor == 'CUR-1') return stalePage.future;
          if (req.category == 'FOOD_BEVERAGE') return _page(['fresh'], null);
          return _page([], 'CUR-1');
        };
      final c = _container(g);
      final n = _notifier(c);
      // Initial load: first page is empty with a cursor — the continuation
      // request goes out and awaits the (pending) stale page.
      final initialLoad = n.load();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(g.requests, hasLength(2));
      expect(g.requests[1].cursor, 'CUR-1');

      // The user switches category while the continuation is in flight.
      await n.selectCategory('FOOD_BEVERAGE');
      expect(
        c.read(marketplaceMixProvider).offers.map((o) => o.productId),
        ['fresh'],
      );

      // The superseded continuation page finally arrives — discarded.
      stalePage.complete(_page(['late'], 'CUR-2'));
      await initialLoad;
      final state = c.read(marketplaceMixProvider);
      expect(state.categoryWire, 'FOOD_BEVERAGE');
      expect(state.offers.map((o) => o.productId), ['fresh']);
      expect(state.nextCursor, isNull);
    },
  );

  test(
    'progress guard: a cursor that repeats without progress stops the walk '
    'early — never the full continuation budget',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async => _page([], 'CUR-REPEAT');
      final c = _container(g);
      await _notifier(c).load();

      // Page 1 is empty with CUR-REPEAT; the follow-up (consuming
      // CUR-REPEAT) returns the SAME cursor — no progress. The guard stops
      // the walk after ONE continuation, not the full budget.
      expect(g.requests, hasLength(2));
      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers, isEmpty);
      // The repeated cursor stays truthfully — the surface affordance
      // remains, but the automatic walk cannot spin on it.
      expect(state.nextCursor, 'CUR-REPEAT');
    },
  );

  test(
    'beyond the automatic budget: consecutive empty pages with cursors, then '
    'an eligible item — loadMore walks it, each action bounded',
    () async {
      final g = _FakeGateway();
      g.behavior = (req) async {
        // The automatic first-page walk exhausts its 8-continuation
        // budget on empty pages; two MORE consecutive empty pages follow
        // (the user-driven affordance), and only then the item.
        if (g.requests.length <=
            1 + MarketplaceMixNotifier.kMaxFirstPageContinuations + 2) {
          return _page([], 'CUR-${g.requests.length}');
        }
        return _page(['found'], null);
      };
      final c = _container(g);
      final n = _notifier(c);
      await n.load();
      final budget = 1 + MarketplaceMixNotifier.kMaxFirstPageContinuations;
      expect(g.requests, hasLength(budget));
      expect(c.read(marketplaceMixProvider).offers, isEmpty);

      // First user-driven continuation: STILL an empty page with a cursor.
      await n.loadMore();
      expect(g.requests, hasLength(budget + 1));
      expect(c.read(marketplaceMixProvider).offers, isEmpty);
      expect(c.read(marketplaceMixProvider).nextCursor, isNotNull);

      // Second user-driven continuation: STILL empty with a cursor — the
      // affordance stays truthful, no items invented, no loop in code.
      await n.loadMore();
      expect(g.requests, hasLength(budget + 2));
      expect(c.read(marketplaceMixProvider).offers, isEmpty);

      // Third user-driven continuation: the eligible item finally appears.
      await n.loadMore();
      expect(g.requests, hasLength(budget + 3));
      final state = c.read(marketplaceMixProvider);
      expect(state.offers.map((o) => o.productId), ['found']);
      expect(state.nextCursor, isNull);
    },
  );

  test(
    'true exhaustion via the continuation path: an empty page with a NULL '
    'cursor is the honest terminal state — no further requests possible',
    () async {
      final g = _FakeGateway()
        ..behavior = (req) async {
          if (req.cursor == null) return _page([], 'CUR-1');
          if (req.cursor == 'CUR-1') return _page([], null);
          return _page(['late'], null);
        };
      final c = _container(g);
      final n = _notifier(c);
      await n.load();
      // Page 1 empty+CUR-1, auto-follow to CUR-1's page: empty + NULL
      // cursor — true exhaustion, terminal.
      expect(g.requests, hasLength(2));
      final state = c.read(marketplaceMixProvider);
      expect(state.phase, MixPhase.ready);
      expect(state.offers, isEmpty);
      expect(state.nextCursor, isNull, reason: 'exhausted source has no cursor');
      expect(state.hasMore, isFalse);

      // With no cursor, loadMore is a no-op — the surface renders the
      // honest terminal empty state with no affordance.
      await n.loadMore();
      expect(g.requests, hasLength(2));
    },
  );

  test(
    'the provider watches the real gateway provider (HTTP adapter in prod)',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(marketplaceMixGatewayProvider),
        isA<HttpMarketplaceMixGateway>(),
      );
    },
  );
}

class _NoTapGateway extends _FakeGateway {
  _NoTapGateway(Future<MixDiscoveryPage> Function(_Request req)? b)
    : super(behavior: b);

  @override
  Set<MixCapability> get supportedCapabilities => const {};
}
