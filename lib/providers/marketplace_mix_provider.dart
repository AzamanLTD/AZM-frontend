// =============================================================================
// AZAMAN — MARKETPLACE MIX STATE (category-first, cross-store)
//
// Drives the Mix browse surface: category selection, per-category fan-out
// (stores via /business/search, then each store's listings via
// /business/:bizId/products), and the composed cross-store offer feed.
//
// ORDERING HONESTY: offers render in SERVER order. The fan-out only
// interleaves stores round-robin so one store's long catalogue does not bury
// every other store — a presentation choice, NOT a ranking claim. No scoring,
// popularity or price sort is applied client-side; server-backed ranking waits
// for the backend discovery-event contract (see the PR description).
//
// FAILURE MODEL: a store-page failure is fatal (phase: failed, retryable);
// individual store listing failures are partial (that store is skipped,
// [failedStores] counts it) so one broken catalogue never empties the feed.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/storefront/services/storefront_tracking_service.dart';

/// Injectable seam over the REAL backend interaction contract:
/// `POST /api/storefront/:businessProfileId/events` with the allow-listed
/// `product_tap` event type. The default implementation sends through the
/// existing [StorefrontTrackingService], exactly as the storefront product
/// grid already does — same identity (businessProfileId), same metadata
/// conventions, fire-and-forget. Tests inject a recorder instead of HTTP.
abstract interface class MixTapRecorder {
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    required String mixCategory,
  });
}

class StorefrontMixTapRecorder implements MixTapRecorder {
  const StorefrontMixTapRecorder();

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    required String mixCategory,
  }) {
    StorefrontTrackingService.instance.trackEvent(
      businessProfileId,
      'product_tap',
      {
        'productId': productId,
        'widgetType': 'mix_offer_card',
        'mixCategory': mixCategory,
        'source': 'marketplace_mix',
      },
    );
  }
}

enum MixPhase { idle, loading, ready, failed }

class MarketplaceMixState {
  /// Selected category wire (FOOD_BEVERAGE / RETAIL / LOGISTICS / HOSPITALITY).
  final String categoryWire;

  final MixPhase phase;

  /// Loading the NEXT store page (feed stays interactive).
  final bool loadingMore;

  /// Offers in display order — server order within each store, stores
  /// interleaved round-robin.
  final List<MixOffer> offers;

  /// Stores whose offers are in the feed (in server order).
  final List<MixStore> stores;

  /// Stores in the last page whose listing fetch failed (partial failures).
  final int failedStores;

  final bool hasMoreStores;
  final String? nextStoreCursor;

  /// One-sentence user-facing failure message; never a raw exception string.
  final String? error;

  const MarketplaceMixState({
    this.categoryWire = 'FOOD_BEVERAGE',
    this.phase = MixPhase.idle,
    this.loadingMore = false,
    this.offers = const [],
    this.stores = const [],
    this.failedStores = 0,
    this.hasMoreStores = false,
    this.nextStoreCursor,
    this.error,
  });

  bool get isLoading => phase == MixPhase.loading;

  MarketplaceMixState copyWith({
    String? categoryWire,
    MixPhase? phase,
    bool? loadingMore,
    List<MixOffer>? offers,
    List<MixStore>? stores,
    int? failedStores,
    bool? hasMoreStores,
    Object? nextStoreCursor = _unset,
    Object? error = _unset,
  }) =>
      MarketplaceMixState(
        categoryWire: categoryWire ?? this.categoryWire,
        phase: phase ?? this.phase,
        loadingMore: loadingMore ?? this.loadingMore,
        offers: offers ?? this.offers,
        stores: stores ?? this.stores,
        failedStores: failedStores ?? this.failedStores,
        hasMoreStores: hasMoreStores ?? this.hasMoreStores,
        nextStoreCursor: nextStoreCursor == _unset
            ? this.nextStoreCursor
            : nextStoreCursor as String?,
        error: error == _unset ? this.error : error as String?,
      );

  static const _unset = Object();
}

class MarketplaceMixNotifier extends StateNotifier<MarketplaceMixState> {
  MarketplaceMixNotifier({
    required MarketplaceMixGateway gateway,
    MixTapRecorder? recorder,
  })  : _gateway = gateway,
        _recorder = recorder ?? const StorefrontMixTapRecorder(),
        super(const MarketplaceMixState());

  /// Fan-out bound per store page — keeps request volume predictable.
  static const int kStoresPerPage = 10;
  static const int kProductsPerStore = 50;

  final MarketplaceMixGateway _gateway;
  final MixTapRecorder _recorder;

  /// A category switch resets the feed (no stale cross-category content).
  Future<void> selectCategory(String wire) async {
    if (state.categoryWire == wire && state.phase != MixPhase.idle) return;
    state = MarketplaceMixState(categoryWire: wire, phase: MixPhase.loading);
    await _load(reset: true);
  }

  /// Initial load of the default category (screen entry).
  Future<void> load() async {
    if (state.phase == MixPhase.idle) {
      state = state.copyWith(phase: MixPhase.loading);
    }
    await _load(reset: true);
  }

  Future<void> retry() async {
    // Not selectCategory(): a failed load of the SAME wire must not be
    // short-circuited by the same-category no-op guard.
    state = state.copyWith(
      phase: MixPhase.loading,
      loadingMore: false,
      offers: const [],
      stores: const [],
      failedStores: 0,
      error: null,
    );
    await _load(reset: true);
  }

  /// Loads the next page of stores (and their listings), APPENDING to the
  /// existing feed so nothing the user is looking at reshuffles mid-scroll.
  Future<void> loadMoreStores() async {
    if (state.loadingMore ||
        !state.hasMoreStores ||
        state.nextStoreCursor == null) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _gateway.searchStores(
        category: state.categoryWire,
        limit: kStoresPerPage,
        cursor: state.nextStoreCursor,
      );
      final fetched = await _fetchOffersFor(page.stores);
      state = state.copyWith(
        loadingMore: false,
        offers: [...state.offers, ..._interleave(fetched.pages)],
        stores: [...state.stores, ...page.stores],
        failedStores: state.failedStores + fetched.failed,
        hasMoreStores: page.hasMore,
        nextStoreCursor: page.nextCursor,
      );
    } catch (_) {
      // Partial page failure keeps the current feed; the retry affordance is
      // the pull-to-refresh / reselect path.
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Records a tap on one item+store offer pair through the real backend
  /// events contract (`product_tap` with the offer identity `productId` plus
  /// the mix surface in metadata), so server-side ranking can later
  /// distinguish the same item in different stores. Only sent while the
  /// real interaction contract is a supported capability.
  void trackOfferTap(MixOffer offer) {
    if (!_gateway.supportedCapabilities
        .contains(MixCapability.itemStoreInteractions)) {
      return;
    }
    _recorder.recordProductTap(
      businessProfileId: offer.businessProfileId,
      productId: offer.productId,
      mixCategory: state.categoryWire,
    );
  }

  Future<void> _load({required bool reset}) async {
    try {
      final page = await _gateway.searchStores(
        category: state.categoryWire,
        limit: kStoresPerPage,
      );
      final fetched = await _fetchOffersFor(page.stores);
      state = MarketplaceMixState(
        categoryWire: state.categoryWire,
        phase: MixPhase.ready,
        offers: _interleave(fetched.pages),
        stores: page.stores,
        failedStores: fetched.failed,
        hasMoreStores: page.hasMore,
        nextStoreCursor: page.nextCursor,
      );
    } catch (_) {
      state = state.copyWith(
        phase: MixPhase.failed,
        error: 'We couldn\'t load this category right now.',
      );
    }
  }

  Future<({List<MixStoreOffers> pages, int failed})> _fetchOffersFor(
      List<MixStore> stores) async {
    final pages = <MixStoreOffers>[];
    var failed = 0;
    // Parallel fan-out; per-store failures never fail the whole feed.
    final results = await Future.wait(stores.map((s) async {
      try {
        return await _gateway.productsFor(s, limit: kProductsPerStore);
      } catch (_) {
        return null;
      }
    }));
    for (final r in results) {
      if (r == null) {
        failed++;
      } else {
        pages.add(r);
      }
    }
    return (pages: pages, failed: failed);
  }

  /// Round-robin interleave across stores, preserving server order inside
  /// each store. Presentation only — no ranking signal.
  static List<MixOffer> _interleave(List<MixStoreOffers> pages) {
    final out = <MixOffer>[];
    var index = 0;
    var anyAdvanced = true;
    while (anyAdvanced) {
      anyAdvanced = false;
      for (final p in pages) {
        if (index < p.offers.length) {
          out.add(p.offers[index]);
          anyAdvanced = true;
        }
      }
      index++;
    }
    return out;
  }
}

final marketplaceMixProvider =
    StateNotifierProvider<MarketplaceMixNotifier, MarketplaceMixState>((ref) {
  return MarketplaceMixNotifier(
    gateway: ref.watch(marketplaceMixGatewayProvider),
  );
});
