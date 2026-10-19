// =============================================================================
// AZAMAN — MARKETPLACE MIX STATE (category-first, cross-store)
//
// Drives the Mix browse surface against the canonical discovery endpoint
// (`GET /api/discovery/items`, backend PR #349): one bounded request per
// feed page, cursor-paginated by the server.
//
// ALL MODE (in-place Mix): `categoryWire == null` means ALL — the
// UNFILTERED discovery feed. The gateway OMITS the `category` query
// parameter entirely (the server's own default page); no invented `ALL`
// server value exists. Entering Mix starts at All; category selections
// narrow the feed.
//
// PAGING & RESET HONESTY:
//   • Changing the category or any filter RESETS the feed — stale
//     cross-selection content is never shown.
//   • Stale-response protection: every load carries a monotonic request id;
//     a response for an older request (the user switched category while the
//     request was in flight) is DISCARDED — an out-of-order response can
//     never overwrite a newer selection's feed.
//
// ORDERING HONESTY: offers render in SERVER order (totalOrders desc /
// createdAt desc). No client-side scoring, popularity or price sort exists;
// `rank.score` passes through untouched.
//
// FAILURE MODEL (typed from the gateway):
//   • 404  → [MixPhase.disabled] — the discovery surface is off/unavailable.
//     Distinct from an empty feed; never misreported as "no items".
//   • 422  → [MixPhase.invalidRequest] — surfaced, never retried in a loop.
//   • network/server → [MixPhase.failed] — the retryable experience.
//   • 200 with zero items → [MixPhase.ready] + empty feed — a LEGITIMATE
//     empty result, never rendered as an error.
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
    String? mixCategory,
  });
}

class StorefrontMixTapRecorder implements MixTapRecorder {
  const StorefrontMixTapRecorder();

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    String? mixCategory,
  }) {
    StorefrontTrackingService.instance.trackEvent(
      businessProfileId,
      'product_tap',
      {
        'productId': productId,
        'widgetType': 'mix_offer_card',
        // null (All mode) is omitted — an honest event, never a fabricated
        // category wire the server vocabulary does not own.
        if (mixCategory != null) 'mixCategory': mixCategory,
        'source': 'marketplace_mix',
      },
    );
  }
}

enum MixPhase {
  idle,
  loading,

  /// 200 success — feed (possibly legitimately empty) is rendered.
  ready,

  /// Retryable failure (network/5xx/malformed body). Existing retry UX.
  failed,

  /// 404 — the discovery surface is not enabled/available. NOT an empty
  /// feed and NOT retryable-as-if-transient.
  disabled,

  /// 422 — the server rejected a request parameter. Surfaced honestly;
  /// never auto-retried.
  invalidRequest,
}

class MarketplaceMixState {
  /// Selected discovery category wire
  /// (FOOD_BEVERAGE / RETAIL / LOGISTICS / HOSPITALITY). NULL means ALL —
  /// the unfiltered discovery feed (the gateway omits the `category`
  /// parameter entirely; no invented `ALL` server value exists).
  final String? categoryWire;

  /// Selected canonical taxonomy chip ids (repeatable `taxonomy` filter).
  /// Changing this list resets the feed.
  final List<String> taxonomies;

  final MixPhase phase;

  /// Loading the NEXT page (feed stays interactive).
  final bool loadingMore;

  /// Offers in display order — the SERVER's order, untouched.
  final List<MixOffer> offers;

  /// Opaque server cursor for the next page; null = end of feed.
  final String? nextCursor;

  /// One-sentence user-facing failure message; never a raw exception string.
  final String? error;

  const MarketplaceMixState({
    this.categoryWire,
    this.taxonomies = const [],
    this.phase = MixPhase.idle,
    this.loadingMore = false,
    this.offers = const [],
    this.nextCursor,
    this.error,
  });

  bool get isLoading => phase == MixPhase.loading;

  bool get hasMore => nextCursor != null;

  MarketplaceMixState copyWith({
    String? categoryWire,
    List<String>? taxonomies,
    MixPhase? phase,
    bool? loadingMore,
    List<MixOffer>? offers,
    Object? nextCursor = _unset,
    Object? error = _unset,
  }) => MarketplaceMixState(
    categoryWire: categoryWire ?? this.categoryWire,
    taxonomies: taxonomies ?? this.taxonomies,
    phase: phase ?? this.phase,
    loadingMore: loadingMore ?? this.loadingMore,
    offers: offers ?? this.offers,
    nextCursor: nextCursor == _unset ? this.nextCursor : nextCursor as String?,
    error: error == _unset ? this.error : error as String?,
  );

  static const _unset = Object();
}

class MarketplaceMixNotifier extends StateNotifier<MarketplaceMixState> {
  MarketplaceMixNotifier({
    required MarketplaceMixGateway gateway,
    MixTapRecorder? recorder,
  }) : _gateway = gateway,
       _recorder = recorder ?? const StorefrontMixTapRecorder(),
       super(const MarketplaceMixState());

  /// Backend default page size (discoveryService DEFAULT_LIMIT = 24). One
  /// bounded request per feed page — the whole point of the canonical
  /// endpoint.
  static const int kPageSize = 24;

  /// Explicit, safe continuation limit for the first-page walk (final
  /// acceptance pass, 2026-10-19). The server's window-filter scan is
  /// bounded per request (backend runQuery walks at most MAX_ROUNDS
  /// batches of where-eligible rows past the section-window post-filter),
  /// so a page can legitimately return `items: []` with a NON-NULL
  /// nextCursor — the scan budget ended before any eligible item. The
  /// first page AUTO-FOLLOWS such cursors, at most this many follow-ups
  /// (each one bounded server round trip), until offers appear or the
  /// source is exhausted. Hard limit — no unbounded retry loop exists —
  /// and the stale-response guard discards any page a newer selection
  /// superseded mid-walk.
  static const int kMaxFirstPageContinuations = 8;

  final MarketplaceMixGateway _gateway;
  final MixTapRecorder _recorder;

  /// Monotonic request id for stale-response protection. Every accepted
  /// result must carry the id it was issued; a response for a superseded
  /// request is discarded.
  int _requestSeq = 0;

  /// Switches category. `null` selects ALL — the unfiltered discovery feed.
  /// Resets any taxonomy filters (chips are category-scoped) and reloads
  /// the first page — stale cross-category content never survives the
  /// switch.
  Future<void> selectCategory(String? wire) async {
    if (state.categoryWire == wire &&
        state.taxonomies.isEmpty &&
        state.phase != MixPhase.idle &&
        state.phase != MixPhase.failed &&
        state.phase != MixPhase.disabled) {
      return;
    }
    state = MarketplaceMixState(categoryWire: wire, phase: MixPhase.loading);
    await _loadFirstPage();
  }

  /// Toggles one canonical taxonomy chip. Changing the filter RESETS
  /// pagination and removes stale results, then reloads page one.
  Future<void> toggleTaxonomy(String chipId) async {
    final next = List<String>.of(state.taxonomies);
    next.contains(chipId) ? next.remove(chipId) : next.add(chipId);
    state = MarketplaceMixState(
      categoryWire: state.categoryWire,
      taxonomies: next,
      phase: MixPhase.loading,
    );
    await _loadFirstPage();
  }

  /// Clears every taxonomy filter (the 422 recovery affordance): resets to
  /// the selected category, unfiltered, page one. Deliberately NOT guarded
  /// by an empty-taxononomies short-circuit — an invalid request may have
  /// come from the unfiltered default load itself, and "Clear filters" is
  /// the explicit, non-looping recovery action for exactly that state.
  Future<void> clearTaxonomies() async {
    state = MarketplaceMixState(
      categoryWire: state.categoryWire,
      phase: MixPhase.loading,
    );
    await _loadFirstPage();
  }

  /// Initial load of the default category (screen entry).
  Future<void> load() async {
    if (state.phase == MixPhase.idle) {
      state = state.copyWith(phase: MixPhase.loading);
    }
    await _loadFirstPage();
  }

  Future<void> retry() async {
    // Not selectCategory(): a failed load of the SAME selection must not be
    // short-circuited by the same-category no-op guard.
    state = state.copyWith(
      phase: MixPhase.loading,
      loadingMore: false,
      error: null,
    );
    await _loadFirstPage();
  }

  /// Loads the next cursor page, APPENDING to the existing feed so nothing
  /// the user is looking at reshuffles mid-scroll. Preserves the selected
  /// category and filters in the request.
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.phase != MixPhase.ready) {
      return;
    }
    final seq = ++_requestSeq;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _gateway.fetchItems(
        category: state.categoryWire,
        taxonomies: state.taxonomies,
        limit: kPageSize,
        cursor: state.nextCursor,
      );
      // Stale-response guard: the selection may have changed while the page
      // was in flight — a late page never appends to a newer feed.
      if (seq != _requestSeq) return;
      state = state.copyWith(
        loadingMore: false,
        offers: [...state.offers, ...page.offers],
        nextCursor: page.nextCursor,
      );
    } catch (_) {
      if (seq != _requestSeq) return;
      // Page-load failure keeps the current feed; the retry affordance is
      // the pull-to-refresh / reselect path.
      state = state.copyWith(loadingMore: false, nextCursor: state.nextCursor);
    }
  }

  /// Records a tap on one item+store offer pair through the real backend
  /// events contract (`product_tap` with the offer identity `productId`
  /// plus the mix surface in metadata). Only sent while the real
  /// interaction contract is a supported capability. The existing
  /// `product_tap` event is an interaction record ONLY — it does NOT drive
  /// any ranking system (the discovery-events/ranking contract is separate
  /// future backend work).
  void trackOfferTap(MixOffer offer) {
    if (!_gateway.supportedCapabilities.contains(
      MixCapability.itemStoreInteractions,
    )) {
      return;
    }
    _recorder.recordProductTap(
      businessProfileId: offer.businessId,
      productId: offer.productId,
      mixCategory: state.categoryWire,
    );
  }

  Future<void> _loadFirstPage() async {
    final seq = ++_requestSeq;
    try {
      var page = await _gateway.fetchItems(
        category: state.categoryWire,
        taxonomies: state.taxonomies,
        limit: kPageSize,
      );
      // Stale-response guard: a newer selection superseded this request —
      // its result is discarded entirely.
      if (seq != _requestSeq) return;
      // Scan-budget continuation (final acceptance pass, 2026-10-19): an
      // empty page WITH a cursor is not a dead end — the server's bounded
      // window-filter scan ended the page before an eligible item. The
      // walk continues from the cursor within the explicit continuation
      // limit until offers appear or the source is exhausted (cursor
      // null). An exhausted budget leaves the remaining cursor in the
      // state so the surface's continuation affordance stays truthful.
      var continuations = 0;
      // Progress guard (final acceptance follow-up 2026-10-19): a cursor
      // the walk has ALREADY consumed and seen again means the source is
      // not advancing — following it would loop without progress. The walk
      // stops instead; the surviving cursor stays in the state so the
      // surface affordance remains truthful.
      final seenCursors = <String?>{};
      while (page.offers.isEmpty &&
          page.nextCursor != null &&
          !seenCursors.contains(page.nextCursor) &&
          continuations < kMaxFirstPageContinuations) {
        seenCursors.add(page.nextCursor);
        page = await _gateway.fetchItems(
          category: state.categoryWire,
          taxonomies: state.taxonomies,
          limit: kPageSize,
          cursor: page.nextCursor,
        );
        continuations += 1;
        if (seq != _requestSeq) return;
      }
      state = MarketplaceMixState(
        categoryWire: state.categoryWire,
        taxonomies: state.taxonomies,
        phase: MixPhase.ready,
        offers: page.offers,
        nextCursor: page.nextCursor,
      );
    } on MixEndpointDisabledException {
      if (seq != _requestSeq) return;
      state = state.copyWith(
        phase: MixPhase.disabled,
        offers: const [],
        nextCursor: null,
        error: null,
      );
    } on MixInvalidFilterException catch (e) {
      if (seq != _requestSeq) return;
      state = state.copyWith(
        phase: MixPhase.invalidRequest,
        offers: const [],
        nextCursor: null,
        error: e.message,
      );
    } catch (_) {
      if (seq != _requestSeq) return;
      state = state.copyWith(
        phase: MixPhase.failed,
        offers: const [],
        nextCursor: null,
        error: 'We couldn\'t load this category right now.',
      );
    }
  }
}

final marketplaceMixProvider =
    StateNotifierProvider<MarketplaceMixNotifier, MarketplaceMixState>((ref) {
      return MarketplaceMixNotifier(
        gateway: ref.watch(marketplaceMixGatewayProvider),
      );
    });
