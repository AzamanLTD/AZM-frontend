// =============================================================================
// BUSINESS PROVIDER — Flutter V3 Marketplace Sprint (2026-06-21)
//
// All marketplace Riverpod state in one file:
//   • myBusinessProvider        — the signed-in user's own business (or null)
//   • bizUnreadCountProvider     — owner notification badge count
//   • businessSearchProvider     — paginated business search
//   • nearbySearchProvider       — paginated GPS "near you" location search
//   • businessReviewsProvider    — FutureProvider.family(bizId)
//   • businessProductsProvider   — FutureProvider.family(bizId)
//   • myInvoicesProvider         — customer's invoices
//   • myOrdersProvider           — customer's orders
//
// Search / nearby / invoices / orders are StateNotifiers (they paginate +
// hold filter state); reviews + products-by-bizId are one-shot FutureProviders.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/business_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// My Business
// ─────────────────────────────────────────────────────────────────────────────

class MyBusinessState {
  final BusinessProfile? profile;
  final bool isLoading;
  final bool hasLoaded;
  final String? error;

  const MyBusinessState({
    this.profile,
    this.isLoading = false,
    this.hasLoaded = false,
    this.error,
  });

  MyBusinessState copyWith({
    BusinessProfile? profile,
    bool? isLoading,
    bool? hasLoaded,
    String? error,
    bool clearProfile = false,
    bool clearError = false,
  }) {
    return MyBusinessState(
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MyBusinessNotifier extends StateNotifier<MyBusinessState> {
  final BusinessService _service;
  MyBusinessNotifier(this._service) : super(const MyBusinessState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _service.getMyBusiness();
      state = MyBusinessState(
        profile: profile,
        isLoading: false,
        hasLoaded: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: e.toString(),
      );
    }
  }

  /// Replace the cached profile after a register / profile-update mutation.
  void setProfile(BusinessProfile profile) {
    state = state.copyWith(profile: profile, hasLoaded: true);
  }
}

final myBusinessProvider =
    StateNotifierProvider<MyBusinessNotifier, MyBusinessState>(
      (ref) => MyBusinessNotifier(BusinessService()),
    );

/// Owner notification badge count (driven by socket + initial fetch).
final bizUnreadCountProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────────────────────────────────────────────────────────
// Business Search
// ─────────────────────────────────────────────────────────────────────────────

class BusinessSearchState {
  final List<BusinessProfile> results;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextCursor;
  final String? error;
  // REVIEW §5 — a failed LATER-PAGE fetch keeps the loaded results visible;
  // this field drives the inline "couldn't load more" retry affordance at
  // the list tail (distinct from `error`, which is the INITIAL-search
  // failure shown by the honest full-screen failure state).
  final String? loadMoreError;
  // Active query parameters (so loadMore replays the same filters).
  final String query;
  final String? category;
  final bool? verified;
  final String? subcategory;

  const BusinessSearchState({
    this.results = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
    this.loadMoreError,
    this.query = '',
    this.category,
    this.verified,
    this.subcategory,
  });

  BusinessSearchState copyWith({
    List<BusinessProfile>? results,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    String? error,
    String? loadMoreError,
    String? query,
    String? category,
    bool? verified,
    String? subcategory,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearCategory = false,
    bool clearVerified = false,
    bool clearSubcategory = false,
    bool clearCursor = false,
  }) {
    return BusinessSearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      error: clearError ? null : (error ?? this.error),
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      verified: clearVerified ? null : (verified ?? this.verified),
      subcategory: clearSubcategory ? null : (subcategory ?? this.subcategory),
    );
  }
}

class BusinessSearchNotifier extends StateNotifier<BusinessSearchState> {
  final BusinessService _service;
  BusinessSearchNotifier(this._service) : super(const BusinessSearchState());

  // REVIEW §5 — request identity: every search() bumps the generation, so
  // a LATE response for query A can never overwrite newer results for
  // query B (it is discarded, not applied). loadMore() inherits the
  // current generation; a superseding search discards its page too.
  int _generation = 0;

  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    final generation = ++_generation;
    state = BusinessSearchState(
      isLoading: true,
      query: query,
      category: category,
      verified: verified,
      subcategory: subcategory,
    );
    try {
      final page = await _service.searchBusinesses(
        q: query,
        category: category,
        verified: verified,
        subcategory: subcategory,
      );
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        results: page.businesses,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoading: false,
        clearLoadMoreError: true,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.nextCursor == null) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final page = await _service.searchBusinesses(
        q: state.query,
        category: state.category,
        verified: state.verified,
        subcategory: state.subcategory,
        cursor: state.nextCursor,
      );
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        results: [...state.results, ...page.businesses],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      // REVIEW §5 — a failed pagination keeps the ALREADY-LOADED results
      // untouched; only the inline tail retry becomes visible. Retrying
      // calls loadMore() again with the SAME nextCursor, so results are
      // never dropped or duplicated.
      state = state.copyWith(isLoadingMore: false, loadMoreError: e.toString());
    }
  }

  void clear() => state = const BusinessSearchState();
}

final businessSearchProvider =
    StateNotifierProvider<BusinessSearchNotifier, BusinessSearchState>(
      (ref) => BusinessSearchNotifier(BusinessService()),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Nearby Search (offset pagination)
// ─────────────────────────────────────────────────────────────────────────────

class NearbySearchState {
  final List<BusinessLocation> locations;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int? nextPage;
  final String? error;
  // Replay params for loadMore.
  final double lat;
  final double lng;
  final double radiusKm;
  final String? category;
  final String? query;
  final bool? verified;

  const NearbySearchState({
    this.locations = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextPage,
    this.error,
    this.lat = 0,
    this.lng = 0,
    this.radiusKm = 10,
    this.category,
    this.query,
    this.verified,
  });

  NearbySearchState copyWith({
    List<BusinessLocation>? locations,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? nextPage,
    String? error,
    double? lat,
    double? lng,
    double? radiusKm,
    String? category,
    String? query,
    bool? verified,
    bool clearError = false,
    bool clearNextPage = false,
  }) {
    return NearbySearchState(
      locations: locations ?? this.locations,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextPage: clearNextPage ? null : (nextPage ?? this.nextPage),
      error: clearError ? null : (error ?? this.error),
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusKm: radiusKm ?? this.radiusKm,
      category: category ?? this.category,
      query: query ?? this.query,
      verified: verified ?? this.verified,
    );
  }
}

class NearbySearchNotifier extends StateNotifier<NearbySearchState> {
  final BusinessService _service;
  NearbySearchNotifier(this._service) : super(const NearbySearchState());

  // NEAR-YOU STALE-RESPONSE GUARD (Programme G3): every searchNearby()
  // bumps the generation. A response carries the generation of the request
  // that produced it and is DISCARDED unless it is still current — the
  // user can change the category, the query or the position while a slow
  // request is in flight, and the LAST-ARRIVING stale response must never
  // overwrite the newer authoritative one. (Same identity pattern as the
  // canonical businessSearchProvider, REVIEW §5.) clear() bumps too, so
  // in-flight responses for a cleared feed die instead of resurrecting it.
  int _generation = 0;

  Future<void> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    String? q,
    bool? verified,
  }) async {
    final generation = ++_generation;
    state = NearbySearchState(
      isLoading: true,
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
      category: category,
      query: q,
      verified: verified,
    );
    try {
      final page = await _service.searchNearby(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        category: category,
        q: q,
        verified: verified,
        page: 0,
      );
      // STALE — a newer searchNearby (or a clear) already superseded this
      // request. Its page is dropped whole, never spliced into new state.
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        locations: page.locations,
        hasMore: page.hasMore,
        nextPage: page.nextPage,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.nextPage == null) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _service.searchNearby(
        lat: state.lat,
        lng: state.lng,
        radiusKm: state.radiusKm,
        category: state.category,
        q: state.query,
        verified: state.verified,
        page: state.nextPage!,
      );
      // STALE — a fresh searchNearby superseded the page this tail fetch
      // belonged to. Splicing its rows in would duplicate or resurrect
      // the old feed, so it is dropped whole.
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        locations: [...state.locations, ...page.locations],
        hasMore: page.hasMore,
        nextPage: page.nextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void clear() {
    _generation++;
    state = const NearbySearchState();
  }
}

final nearbySearchProvider =
    StateNotifierProvider<NearbySearchNotifier, NearbySearchState>(
      (ref) => NearbySearchNotifier(BusinessService()),
    );

// ── Featured businesses (§2.3 of Marketplace Enhancement Spec) ──────────────
// Client-side sort: highest averageRating among currently loaded results.
// Swap for a dedicated backend endpoint later without touching UI code.
final featuredBusinessesProvider = Provider.autoDispose<List<BusinessProfile>>((
  ref,
) {
  final state = ref.watch(businessSearchProvider);
  final results = state.results;
  if (results.isEmpty) return [];
  final sorted = List<BusinessProfile>.from(results)
    ..sort((a, b) => b.averageRating.compareTo(a.averageRating));
  return sorted.take(5).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// One-shot family providers (reviews + products by bizId)
// ─────────────────────────────────────────────────────────────────────────────

final businessReviewsProvider = FutureProvider.family<ReviewPage, String>((
  ref,
  bizId,
) {
  return BusinessService().getReviews(bizId);
});

final businessProductsProvider = FutureProvider.family<ProductPage, String>((
  ref,
  bizId,
) {
  return BusinessService().getBusinessProducts(bizId);
});

// ─────────────────────────────────────────────────────────────────────────────
// My Invoices
// ─────────────────────────────────────────────────────────────────────────────

class MyInvoicesState {
  final List<BusinessInvoice> invoices;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextCursor;
  final String? statusFilter;
  final String? error;

  const MyInvoicesState({
    this.invoices = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.statusFilter,
    this.error,
  });

  MyInvoicesState copyWith({
    List<BusinessInvoice>? invoices,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    String? statusFilter,
    String? error,
    bool clearError = false,
    bool clearCursor = false,
    bool clearStatus = false,
  }) {
    return MyInvoicesState(
      invoices: invoices ?? this.invoices,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      statusFilter: clearStatus ? null : (statusFilter ?? this.statusFilter),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MyInvoicesNotifier extends StateNotifier<MyInvoicesState> {
  final BusinessService _service;
  MyInvoicesNotifier(this._service) : super(const MyInvoicesState());

  Future<void> load({String? status}) async {
    state = MyInvoicesState(isLoading: true, statusFilter: status);
    try {
      final page = await _service.getMyInvoices(status: status);
      if (!mounted) return;
      state = state.copyWith(
        invoices: page.invoices,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.nextCursor == null) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _service.getMyInvoices(
        status: state.statusFilter,
        cursor: state.nextCursor,
      );
      if (!mounted) return;
      state = state.copyWith(
        invoices: [...state.invoices, ...page.invoices],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final myInvoicesProvider =
    StateNotifierProvider<MyInvoicesNotifier, MyInvoicesState>(
      (ref) => MyInvoicesNotifier(BusinessService()),
    );

// ─────────────────────────────────────────────────────────────────────────────
// My Orders
// ─────────────────────────────────────────────────────────────────────────────

class MyOrdersState {
  final List<BusinessOrder> orders;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextCursor;
  final String? error;

  const MyOrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  MyOrdersState copyWith({
    List<BusinessOrder>? orders,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    String? error,
    bool clearError = false,
    bool clearCursor = false,
  }) {
    return MyOrdersState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MyOrdersNotifier extends StateNotifier<MyOrdersState> {
  final BusinessService _service;
  MyOrdersNotifier(this._service) : super(const MyOrdersState());

  Future<void> load() async {
    state = const MyOrdersState(isLoading: true);
    try {
      final page = await _service.getMyOrders();
      if (!mounted) return;
      state = state.copyWith(
        orders: page.orders,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.nextCursor == null) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _service.getMyOrders(cursor: state.nextCursor);
      if (!mounted) return;
      state = state.copyWith(
        orders: [...state.orders, ...page.orders],
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final myOrdersProvider = StateNotifierProvider<MyOrdersNotifier, MyOrdersState>(
  (ref) => MyOrdersNotifier(BusinessService()),
);
