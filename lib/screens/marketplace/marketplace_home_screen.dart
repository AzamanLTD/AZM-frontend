// lib/screens/marketplace/marketplace_home_screen.dart
// =============================================================================
// AZAMAN — MARKETPLACE HOME SCREEN (Redesign, 2026-07-04)
//
// Structure (top → bottom):
//   _header()              — title + view toggle, morphs into an expandable
//                             search field (tap the search icon; tap the
//                             back arrow or elsewhere on the page to retract)
//   _activeCategoryChip()  — shown only when a category is active (clearable)
//   _resultsBar()          — slim row: count · Sort ▼ · Verified pill · Filter
//   Expanded(_listMode() or _mapMode())
//
// Category selection now lives entirely in the horizontal _categoryStrip()
// (the old side endDrawer was removed as redundant, 2026-07-06).
// All list items are CollapsibleBusinessBar — no BusinessCard in the main feed.
// Accordion: only one bar expanded at a time via _expandedBizId.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_search_binding.dart';
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/utils/business_hours.dart';
import 'package:azaman/widgets/marketplace/discovery/discovery_header.dart';
import 'package:azaman/widgets/marketplace/discovery/intent_rail.dart';
import 'package:azaman/widgets/marketplace/discovery/local_pulse.dart';
import 'package:azaman/widgets/marketplace/discovery/merchant_card.dart';
import 'package:azaman/widgets/marketplace/discovery/resume_card.dart';
import 'package:azaman/widgets/marketplace/discovery/utility_rail.dart';
import 'package:azaman/widgets/marketplace/discovery/world_deck.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/marketplace/advanced_filter_sheet.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/models/story_model.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:shimmer/shimmer.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum _ViewMode { list, map }

enum _SortMode { topRated, mostPopular, nearest, newest }

/// Marketplace tab modes (portal milestone, 2026-09-30):
///  - portal  — destination identity + "choose your world" deck. The bare
///              tab opens here; the worlds ARE the primary storefront.
///  - explore — the full search / filter / list / map machinery, entered
///              by picking a world, "Explore all", or a launcher category.
/// Static by construction: the portal runs no autonomous decorative
/// animation, so it is inherently reduced-motion safe.
enum _MarketplaceHomeMode { portal, explore }

extension _SortLabel on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.topRated:
        return 'Top Rated';
      case _SortMode.mostPopular:
        return 'Most Popular';
      case _SortMode.nearest:
        return 'Nearest';
      case _SortMode.newest:
        return 'Newest';
    }
  }
}

class MarketplaceHomeScreen extends ConsumerStatefulWidget {
  const MarketplaceHomeScreen({super.key, this.initialCategory});

  /// Wire value of the vertical to open with: `'RETAIL'`, `'FOOD_BEVERAGE'`,
  /// `'LOGISTICS'`, `'HOSPITALITY'` or `'REAL_ESTATE'` (the wire the in-app
  /// category dial itself sends for Hotels). `null` or an unknown value opens
  /// the marketplace unfiltered ("All").
  ///
  /// Added for the TASK-010b vertical launcher and future deep links.
  final String? initialCategory;

  @override
  ConsumerState<MarketplaceHomeScreen> createState() =>
      _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState
    extends ConsumerState<MarketplaceHomeScreen> {
  // Mirrors `marketplaceSearchProvider.text` into the explore TextField. The
  // provider is the single owner of search state (Overhaul 02 §4); the
  // controller only exists because a TextField needs one.
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _portalScroll = ScrollController();
  double _scrollOffset = 0;
  // Live results while typing: debounce the already-updated provider text
  // into the existing search plumbing.
  Timer? _debounce;

  // Category filter — wire value string (null = All)
  String? _selectedCategory;

  // Portal (2026-09-30): which surface the tab is showing.
  _MarketplaceHomeMode _mode = _MarketplaceHomeMode.portal;

  // Accordion — which bar is currently expanded
  String? _expandedBizId;

  // Header search — expanded/focused state lives in marketplaceSearchProvider
  // (`isActive` / `focused`); this node is only the TextField's focus owner.
  final _searchFocusNode = FocusNode();

  // Portal utility filter (Overhaul 02 §7.4) — a client-side predicate over
  // the loaded results; the server query is untouched.
  UtilityFilter? _utility;

  // Story height is driven by scroll offset — no manual toggle needed.
  // At offset 0: fully expanded (96px). At offset 96: fully collapsed (0px).
  // Location permission requested flag
  bool _locationRequested = false;

  // Invalidates asynchronous world-entry work when a newer interaction starts.
  int _exploreGeneration = 0;

  // View / sort / filter state
  _ViewMode _viewMode = _ViewMode.list;
  _SortMode _sort = _SortMode.topRated;
  bool _verifiedOnly = false;
  MarketplaceFilters _filters = const MarketplaceFilters();

  // Location
  Position? _position;
  bool _resolvingLocation = false;
  String? _locationError;

  // §2: Featured rail collapsed by default
  bool _featuredExpanded = false;

  // §1: Google Map controller
  GoogleMapController? _mapController;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Seed the category BEFORE the first post-frame search, so a launcher or a
    // deep link lands on an already-filtered marketplace rather than flashing
    // "All" and then filtering a frame later.
    _selectedCategory = _validatedInitialCategory();
    // A launcher / deep link with a valid category lands directly in the
    // pre-filtered explore view (existing behaviour). The bare tab opens
    // on the portal — the worlds deck is the primary destination.
    if (_selectedCategory != null) {
      _mode = _MarketplaceHomeMode.explore;
    }
    _scrollCtrl.addListener(_onScroll);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        setState(() => _scrollOffset = _scrollCtrl.offset);
      }
    });
    _searchFocusNode.addListener(() {
      if (mounted) _binding.onFocus(_searchFocusNode.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessSearchProvider.notifier)
          .search('', category: _selectedCategory);
      // Prefetch the signed-in user's own business profile so the
      // Register/Your-Business FAB shows the correct state immediately
      // instead of waiting on whatever triggered it before (opening the
      // settings drawer, which the user may never do on this screen).
      final biz = ref.read(myBusinessProvider);
      if (!biz.hasLoaded && !biz.isLoading) {
        ref.read(myBusinessProvider.notifier).load();
      }
      // Request location permission but don't
      // block the UI — demo data still shows regardless of permission.
      if (!_locationRequested) {
        _locationRequested = true;
        _requestLocationPermission();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _portalScroll.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Unified search state (Overhaul 02 §4) ─────────────────────────────────

  MarketplaceSearchBinding get _binding => MarketplaceSearchBinding(ref);

  /// The committed query text — read from the provider, never from the
  /// controller, so the in-pill search (when it lands) and this screen agree.
  String get _query => ref.read(marketplaceSearchProvider).text.trim();

  bool get _searchActive => ref.read(marketplaceSearchProvider).isActive;

  /// Wire values a launcher or deep link may use to open the marketplace with a
  /// vertical already selected. Includes `REAL_ESTATE` because that is the wire
  /// the in-app category dial itself sends for Hotels (`_controlRow`).
  static const Set<String> _launchableCategoryWires = <String>{
    'FOOD_BEVERAGE',
    'RETAIL',
    'LOGISTICS',
    'HOSPITALITY',
    'REAL_ESTATE',
  };

  /// Normalises [MarketplaceHomeScreen.initialCategory] into a wire the dial
  /// already understands, or `null` for "open unfiltered".
  ///
  /// Why an allowlist rather than `BusinessCategories.fromWire`: `fromWire`
  /// does not model `REAL_ESTATE` and falls back to `OTHER` (see F-029), so
  /// round-tripping a hotel launch through it would mislabel the result. The
  /// allowlist accepts exactly what the app itself can send today, and nothing
  /// else — an unrecognised value is a caller bug, not a licence to guess.
  String? _validatedInitialCategory() {
    final wire = widget.initialCategory;
    if (wire == null || wire.trim().isEmpty) return null;
    final normalised = wire.trim().toUpperCase();
    return _launchableCategoryWires.contains(normalised) ? normalised : null;
  }

  // ── Query plumbing ─────────────────────────────────────────────────────────

  void _onScroll() {
    if (_viewMode == _ViewMode.list &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 320) {
      ref.read(businessSearchProvider.notifier).loadMore();
    }

    // Story expand/collapse is now handled via NotificationListener
    // (UserScrollNotification) in the build method — see _handleScrollNotification.
  }

  // Story expand/collapse is now driven directly by _scrollOffset.
  // No manual toggle or direction detection needed — the height
  // interpolates smoothly with scroll position, just like Telegram.

  void _onQueryChanged(String value) {
    ++_exploreGeneration;
    _binding.onChanged(value);
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 400), _fireSearch);
  }

  void _fireSearch() {
    if (_viewMode == _ViewMode.map) {
      _fireNearby();
      return;
    }
    ref.read(businessSearchProvider.notifier).search(
          _query,
          category: _selectedCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  Future<void> _fireNearby() async {
    final pos = _position;
    if (pos == null) {
      await _resolveLocation();
      return;
    }
    ref.read(nearbySearchProvider.notifier).searchNearby(
          lat: pos.latitude,
          lng: pos.longitude,
          q: _query.isEmpty ? null : _query,
          category: _selectedCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _resolvingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _resolvingLocation = false;
      });
      ref.read(nearbySearchProvider.notifier).searchNearby(
            lat: pos.latitude,
            lng: pos.longitude,
            q: _query.isEmpty ? null : _query,
            category: _selectedCategory,
            verified: _verifiedOnly ? true : null,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingLocation = false;
        _locationError = e.toString();
      });
    }
  }

  /// Request location permission without blocking — still shows demo data.
  Future<void> _requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() => _position = pos);
        }
      }
    } catch (_) {
      // Silently fail — demo data shows regardless
    }
  }

  void _setViewMode(_ViewMode mode) {
    if (_viewMode == mode) return;
    AzamanHaptics.toggle();
    setState(() {
      _viewMode = mode;
      if (mode == _ViewMode.map) _sort = _SortMode.nearest;
    });
    if (mode == _ViewMode.map) _fireNearby();
  }

  Future<void> _openFilters() async {
    final result = await AdvancedFilterSheet.show(context, _filters);
    if (result == null) return;
    setState(() {
      _filters = result;
      _verifiedOnly = result.verifiedOnly || _verifiedOnly;
    });
    _fireSearch();
  }

  // ── Sort + filter (client-side) ─────────────────────────────────────────────

  /// Client-side category match that tolerates the historical hotel launcher
  /// wire value REAL_ESTATE: the backend/demo search already normalizes it to
  /// HOSPITALITY, but a literal equality here would empty the result list.
  bool _categoryMatchesBusiness(
      String businessCategory, String selectedCategory) {
    final actual = businessCategory.trim().toUpperCase();
    final wanted = selectedCategory.trim().toUpperCase();
    if (wanted == 'REAL_ESTATE') {
      return actual == 'HOSPITALITY' || actual == 'REAL_ESTATE';
    }
    return actual == wanted;
  }

  List<BusinessProfile> _applySortFilter(
      List<BusinessProfile> input) {
    var list = input.where((b) {
      if (_filters.minRating > 0 &&
          b.averageRating < _filters.minRating) {
        return false;
      }
      if ((_filters.verifiedOnly || _verifiedOnly) && !b.isVerified) {
        return false;
      }
      if (_selectedCategory != null &&
          !_categoryMatchesBusiness(b.category, _selectedCategory!)) {
        return false;
      }
      return _utilityPredicate(b);
    }).toList();

    switch (_sort) {
      case _SortMode.topRated:
        list.sort((a, b) =>
            b.averageRating.compareTo(a.averageRating));
        break;
      case _SortMode.mostPopular:
        list.sort((a, b) =>
            b.completedEscrows.compareTo(a.completedEscrows));
        break;
      case _SortMode.newest:
        break;
      case _SortMode.nearest:
        break;
    }
    return list;
  }

  /// Overhaul 02 §7.4 — utility chips are client-side predicates over the
  /// loaded results. `nearMe` is not a predicate (it switches to the map).
  bool _utilityPredicate(BusinessProfile b) {
    switch (_utility) {
      case null:
      case UtilityFilter.nearMe:
        return true;
      case UtilityFilter.openNow:
        // Use the same sampled clock as the portal snapshot so every card in
        // one render is evaluated against one deterministic instant.
        final now = ref.read(discoverySnapshotProvider).now;
        return b.openStateAt(now) == OpenState.open;
      case UtilityFilter.topRated:
        return b.averageRating >= 4.0 && b.reviewCount >= 5;
      case UtilityFilter.saved:
        return ref.read(savedBusinessesProvider).contains(b.bizId);
    }
  }

  void _onUtility(UtilityFilter? filter) {
    setState(() {
      _utility = filter;
      if (filter == UtilityFilter.topRated) _sort = _SortMode.topRated;
    });
    if (filter == UtilityFilter.nearMe) {
      if (_mode == _MarketplaceHomeMode.portal) _enterExplore(null);
      _setViewMode(_ViewMode.map);
      return;
    }
    if (filter != null && _mode == _MarketplaceHomeMode.portal) {
      _enterExplore(null);
    }
  }

  void _onIntent(DiscoveryIntentItem item) {
    if (item.worldWire != null) {
      _enterExplore(item.worldWire);
      return;
    }
    if (item.signal == DiscoverySignal.nearby) {
      _onUtility(UtilityFilter.nearMe);
      return;
    }
    if (item.savesOnly) {
      context.push(AzRoutes.savedBusinesses);
      return;
    }
    if (item.recentOnly) {
      final wire = ref.read(worldMemoryProvider.notifier).mostRecentWire();
      if (wire != null) _enterExplore(wire);
    }
  }

  Future<void> _refresh() {
    return ref.read(businessSearchProvider.notifier).search(
          _query,
          category: _selectedCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  // ── Portal mode (2026-09-30) ───────────────────────────────────────────────
  //
  // The bare marketplace tab is a destination, not a search results page:
  // identity header → "choose your world" deck → stories rail → featured
  // picks → explore-all. Everything derives from the same
  // businessSearchProvider state the explore view uses — no new providers,
  // no extra network traffic beyond the unfiltered search the tab already
  // fires on init / return.

  Future<void> _enterExplore(String? wire) async {
    AzamanHaptics.selection();
    final generation = ++_exploreGeneration;
    setState(() {
      _mode = _MarketplaceHomeMode.explore;
      if (wire != null) {
        _selectedCategory = wire;
      }
    });
    final search = ref.read(marketplaceSearchProvider.notifier);
    if (wire == null) {
      search.setScope(MarketplaceSearchScope.marketplace);
      return;
    }
    search.setScope(MarketplaceSearchScope.world, worldWire: wire);

    // World memory (Overhaul 02 §5): coming back to a world within 30 minutes
    // restores its query and scroll offset only after the CURRENT request has
    // completed. This prevents a stale result set from satisfying the old
    // "results.isNotEmpty" guard during async navigation.
    final memory = ref.read(worldMemoryProvider.notifier).recall(wire);
    final remembered = memory?.query;
    if (remembered != null && remembered.isNotEmpty) {
      _searchCtrl.text = remembered;
      search.changed(remembered);
      // The screen's search path owns category/view/verified filters, so do
      // not bypass it with the notifier's generic fetch.
      unawaited(search.submit(fetch: false));
    }

    final queryAtRequest = _query;
    await _fetchExploreResults();

    if (!mounted ||
        generation != _exploreGeneration ||
        _mode != _MarketplaceHomeMode.explore ||
        _selectedCategory != wire ||
        _query != queryAtRequest) {
      return;
    }

    final offset = memory?.scrollOffset ?? 0;
    if (offset <= 0 || !_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (offset <= max && ref.read(businessSearchProvider).results.isNotEmpty) {
      _scrollCtrl.jumpTo(offset);
    }
  }

  Future<void> _fetchExploreResults() {
    if (_viewMode == _ViewMode.map) return _fireNearby();
    return ref.read(businessSearchProvider.notifier).search(
          _query,
          category: _selectedCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  void _returnToPortal() {
    ++_exploreGeneration;
    AzamanHaptics.selection();
    final wire = _selectedCategory;
    if (wire != null) {
      ref.read(worldMemoryProvider.notifier).remember(
            wire,
            query: _query,
            scrollOffset: _scrollCtrl.hasClients ? _scrollCtrl.offset : 0,
          );
    }
    setState(() {
      _mode = _MarketplaceHomeMode.portal;
      _selectedCategory = null;
      _searchCtrl.clear();
    });
    _searchFocusNode.unfocus();
    ref
        .read(marketplaceSearchProvider.notifier)
        .setScope(MarketplaceSearchScope.marketplace);
    // World counts + featured picks are derived from the UNFILTERED result
    // set — refresh it so the portal reflects the whole catalog, not the
    // last category the user was browsing.
    ref
        .read(businessSearchProvider.notifier)
        .search('', category: null, verified: null);
  }

  /// Back semantics (brief §17), one place: search first, then explore →
  /// portal. The store route pops on its own (it is a pushed route).
  bool _handleBack() {
    if (_searchActive) {
      _closeSearch();
      return true;
    }
    if (_mode == _MarketplaceHomeMode.explore) {
      _returnToPortal();
      return true;
    }
    return false;
  }

  /// Slim affordance above the explore machinery: returns to the portal
  /// surface of the SAME tab instance (no nested marketplace routes).
  Widget _exploreBar(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _returnToPortal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_arrow_left_rounded,
                    color: colors.textSecondary, size: 20),
                const SizedBox(width: 2),
                Text(
                  'Marketplace',
                  key: const ValueKey('marketplace_back_to_portal'),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portalBody(AzamanColors colors) {
    // Overhaul 02 §8 — one CustomScrollView owns the portal. Every section
    // renders only from loaded data; signals the gateway cannot compute are
    // simply absent.
    final snapshot = ref.watch(discoverySnapshotProvider);
    final supported =
        ref.watch(marketplaceDiscoveryGatewayProvider).supportedSignals;
    return NotificationListener<ResumeIntentNotification>(
      onNotification: (n) {
        final wire = n.intent.worldWire;
        if (wire != null) _enterExplore(wire);
        return true;
      },
      child: CustomScrollView(
        key: const ValueKey('marketplace_portal_body'),
        controller: _portalScroll,
        physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
              child: DiscoveryHeader(onSearchTap: _focusSearch)),
          const SliverToBoxAdapter(child: ResumeCard()),
          SliverToBoxAdapter(child: IntentRail(onSelect: _onIntent)),
          const SliverToBoxAdapter(child: SizedBox(height: AzSpace.sm)),
          SliverToBoxAdapter(
            child: WorldDeck(
              cards: buildWorldCards(snapshot, supported),
              colors: colors,
              onEnter: _enterExplore,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AzSpace.lg)),
          SliverToBoxAdapter(
              child: UtilityRail(active: _utility, onChanged: _onUtility)),
          SliverToBoxAdapter(child: _portalStories(colors)),
          SliverToBoxAdapter(child: LocalPulse(onFilter: _onUtility)),
          SliverToBoxAdapter(child: _portalFeatured(colors, snapshot)),
          SliverToBoxAdapter(child: _portalExploreAll(colors)),
          const SliverPadding(padding: AzSpace.navClearance),
        ],
      ),
    );
  }

  /// The portal's search hint enters explore (where the field lives today)
  /// and focuses it. When the in-pill nav field lands it binds to the same
  /// provider (`MarketplaceSearchBinding`), so this only changes mode.
  void _focusSearch() {
    if (_mode == _MarketplaceHomeMode.portal) _enterExplore(null);
    _openSearch();
  }

  Widget _portalStories(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 96,
        width: double.infinity,
        child: MarketplaceExpandedStories(
          onOpenBusiness: (bizId) {
            _openBusinessStories(context, bizId);
          },
          onBrowsePressed: () => _enterExplore(null),
        ),
      ),
    );
  }

  /// Featured picks are an intentional, always-visible part of the portal
  /// (in explore mode the collapsible `_featuredSection` stays). Items are
  /// `MerchantCard`s (Overhaul 02 §7.8).
  Widget _portalFeatured(AzamanColors colors, DiscoverySnapshot snapshot) {
    final featured = snapshot.featured;
    if (featured.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Icon(Icons.star_rounded, size: 16, color: colors.accent),
              const SizedBox(width: 6),
              Text('Featured picks near you',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      fontSize: 13)),
            ],
          ),
        ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            key: const ValueKey('marketplace_portal_featured'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final b = featured[i];
              return MerchantCard(
                business: b,
                distanceKm: snapshot.distanceOf(b),
                onOpen: () => context.push(AzRoutes.businessProfile(b.bizId)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _portalExploreAll(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('marketplace_explore_all'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.background,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _enterExplore(null),
          icon: const Icon(Icons.apps_rounded, size: 18),
          label: const Text('Explore all businesses',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }

  // ── Root build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // Scroll-driven gradient (0 at top → full when scrolled 120px)
    final expandRatio = (_scrollOffset / 120).clamp(0.0, 1.0);
    // Story bar: fully expanded at offset 0, fully collapsed at offset 96.
    // Smooth interpolation — no hard toggle, just like Telegram.
    final storyExpandRatio = 1.0 - (_scrollOffset / 96).clamp(0.0, 1.0);

    final searchActive =
        ref.watch(marketplaceSearchProvider.select((s) => s.isActive));
    // Back semantics (Overhaul 02 §4.1): search clears first, then explore
    // returns to the portal; only the bare portal lets the system pop.
    final canPop = !searchActive && _mode == _MarketplaceHomeMode.portal;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
      backgroundColor: colors.background,
      // FAB removed — store management moved to the storefront button (item 9)
      body: SafeArea(
        bottom: false,
        child: AzPullToRefresh(
          onRefresh: () => _viewMode == _ViewMode.list ? _refresh() : _fireNearby(),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Phase 3.4: Collapsible gradient behind header ───────────────
            Stack(
              children: [
                // Gradient that fades in as user scrolls
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: expandRatio,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.accent.withValues(alpha: 0.08),
                              colors.background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _header(colors),
              ],
            ),
            const SizedBox(height: 10),
            // Tapping anywhere below the header (category strip, results bar,
            // or the list/map itself) retracts the search field if it's open —
            // "clicking somewhere else" collapses it back to the icon.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (searchActive) _closeSearch();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_mode == _MarketplaceHomeMode.portal)
                      Expanded(child: _portalBody(colors))
                    else ...[
                      // ── Back to the portal (single tab surface, no
                      //    nested marketplace routes) ─────────────────────
                      _exploreBar(colors),
                      // ── Stories: smooth scroll-driven height (Telegram-style) ──
                      SizedBox(
                        height: 96 * storyExpandRatio,
                        width: double.infinity,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: 96,
                            maxHeight: 96,
                            child: Opacity(
                              opacity: storyExpandRatio.clamp(0.0, 1.0),
                              child: MarketplaceExpandedStories(
                                onOpenBusiness: (bizId) {
                                  _openBusinessStories(context, bizId);
                                },
                                onBrowsePressed: () {
                                  setState(() => _selectedCategory = null);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── Combined control row: category selector + buttons ───
                      _controlRow(colors),
                      // §2: Featured rail (collapsed by default)
                      _featuredSection(colors),
                      Expanded(
                        child: _viewMode == _ViewMode.list
                            ? _listMode(colors)
                            : _mapMode(colors),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
      ),
    );
  }

  // ── Store management sheet (replaces old FAB) ──────────────────────────────
  // The FAB was removed — store management now lives in the storefront
  // button in the header. See _showStoreManagementSheet().
  void _showStoreManagementSheet(AzamanColors colors) {
    final bizState = ref.read(myBusinessProvider);
    final isRegistered = bizState.profile != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Your Stores',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (isRegistered) ...[
                // Show existing store
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    AzamanHaptics.nav();
                    // NEW-A: canonical business dashboard route.
                    context.push(AzRoutes.businessMarketDashboard);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.softSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.divider, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: colors.accentSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: bizState.profile?.logoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AzamanNetworkImage(
                                    imageUrl: bizState.profile!.logoUrl!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(Icons.store_rounded, color: colors.accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bizState.profile?.businessName ?? 'My Store',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to manage',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Add store button (always visible)
              GestureDetector(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  AzamanHaptics.nav();
                  // NEW-A: canonical /business/register route.
                  context.push(AzRoutes.businessRegister);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add_rounded, color: colors.isDark ? Colors.black : Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isRegistered ? 'Add another store' : 'Register your business',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header (title + actions) ────────────────────────────────────────────────

  Widget _header(AzamanColors colors) {
    final search = ref.watch(marketplaceSearchProvider);
    final searchExpanded = search.isActive;
    final searchFocused = search.focused;
    final storyExpandRatio = 1.0 - (_scrollOffset / 96).clamp(0.0, 1.0);
    final storyCollapsedOpacity = (1.0 - storyExpandRatio).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Stack(
        children: [
          // ── Collapsed state: title + view toggle + search icon ──────────
          AnimatedSlide(
            offset: searchExpanded ? const Offset(-0.2, 0) : Offset.zero,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: searchExpanded ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: searchExpanded,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Collapsed avatars fade in as stories section collapses.
                    if (storyCollapsedOpacity > 0.5)
                      Expanded(
                        child: MarketplaceCollapsedAvatars(
                          onTap: () {
                            _scrollCtrl.animateTo(0,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOut);
                          },
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),

                    // Search — directly after the title/avatars slot, in line with the view toggle.
                    // Tapping it morphs this whole row into an inline search field.
                    _iconAction(
                      icon: Icons.search_rounded,
                      onTap: _openSearch,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),

                    // Store management — shows your stores + add button
                    _iconAction(
                      icon: Icons.storefront_rounded,
                      onTap: () => _showStoreManagementSheet(colors),
                      colors: colors,
                      activeColor: colors.accent,
                    ),
                    const SizedBox(width: 8),

                    // My Orders
                    _iconAction(
                      icon: Icons.receipt_long_rounded,
                      // NEW-A: canonical /my-orders location.
                      onTap: () => context.push(AzRoutes.storefrontOrderHistory),
                      colors: colors,
                      activeColor: colors.accent,
                    ),
                    const SizedBox(width: 8),

                    // View mode toggle (list / map)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: colors.divider, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          _viewSeg(
                              Icons.view_agenda_outlined, _ViewMode.list, colors),
                          _viewSeg(Icons.location_on_outlined, _ViewMode.map,
                              colors),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded state: back arrow + inline search field ─────────────
          // Slides in from the right as the collapsed row slides/fades out —
          // reads as the search "pushing" the other buttons off-screen.
          AnimatedSlide(
            offset: searchExpanded ? Offset.zero : const Offset(0.2, 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: searchExpanded ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: !searchExpanded,
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _closeSearch,
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: 34,
                          height: 44,
                          child: Icon(Icons.arrow_back_rounded,
                              size: 20, color: colors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: searchFocused ? colors.accent : Colors.transparent,
                              width: 1.4,
                            ),
                            boxShadow: searchFocused
                                ? [BoxShadow(color: colors.accent.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 3))]
                                : null,
                          ),
                          child: PremiumGlassContainer(
                            blur: 12, opacity: 0.06, borderRadius: 14,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            enableShadow: false,
                            child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            onChanged: _onQueryChanged,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _commitSearch(),
                            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: _binding.placeholders(search).first,
                              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w400),
                              icon: Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                ? GestureDetector(onTap: () { _searchCtrl.clear(); _binding.onChanged(''); _fireSearch(); setState(() {}); },
                                    child: Icon(Icons.close_rounded, size: 18, color: colors.textTertiary))
                                : null,
                            ),
                          ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSearch() {
    AzamanHaptics.nav();
    _binding.onFocus(true);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchActive) return;
    AzamanHaptics.toggle();
    _debounce?.cancel();
    final hadText = _query.isNotEmpty;
    _searchFocusNode.unfocus();
    _searchCtrl.clear();
    _binding.clear();
    // Clearing a committed query must also clear its results.
    if (hadText) _fireSearch();
  }

  /// Keyboard "search": cancel the pending debounce, run the query through the
  /// screen's own plumbing (view mode, verified, category), and let the
  /// provider record the recent search without fetching a second time.
  void _commitSearch() {
    _debounce?.cancel();
    _searchFocusNode.unfocus();
    _fireSearch();
    ref.read(marketplaceSearchProvider.notifier).submit(fetch: false);
  }

  Widget _viewSeg(
      IconData icon, _ViewMode mode, AzamanColors colors) {
    final active = _viewMode == mode;
    return ScaleTap(
      onTap: () => _setViewMode(mode),
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color: active
                ? (colors.isDark ? Colors.black : Colors.white)
                : colors.textSecondary),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required VoidCallback onTap,
    required AzamanColors colors,
    Color? activeColor,
  }) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Icon(icon,
            size: 20,
            color: activeColor ?? colors.textSecondary),
      ),
    );
  }

  Widget _controlRow(AzamanColors colors) {
    final categories = <CategoryDialItem>[
      CategoryDialItem(wire: null, icon: Icons.apps_rounded, label: 'All'),
      CategoryDialItem(wire: 'FOOD_BEVERAGE', icon: Icons.restaurant_rounded, label: 'Restaurants'),
      CategoryDialItem(wire: 'REAL_ESTATE', icon: Icons.apartment_rounded, label: 'Hotels'),
      CategoryDialItem(wire: 'LOGISTICS', icon: Icons.directions_bus_rounded, label: 'Transit'),
      CategoryDialItem(wire: 'RETAIL', icon: Icons.shopping_bag_rounded, label: 'Retail'),
    ];

    final hasFilters = !_filters.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Category selector (left side)
          CategorySpeedDial(
            categories: categories,
            selectedWire: _selectedCategory,
            colors: colors,
            onSelected: (wire) {
              setState(() => _selectedCategory = wire);
              _fireSearch();
            },
          ),
          const Spacer(),
          // Sort dropdown
          PopupMenuButton<_SortMode>(
            color: colors.surface,
            elevation: 4,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            onSelected: (m) {
              AzamanHaptics.toggle();
              setState(() => _sort = m);
            },
            itemBuilder: (_) {
              final opts = _viewMode == _ViewMode.map
                  ? [_SortMode.nearest, _SortMode.topRated]
                  : [
                      _SortMode.topRated,
                      _SortMode.mostPopular,
                      _SortMode.newest
                    ];
              return opts
                  .map((m) => PopupMenuItem(
                        value: m,
                        height: 44,
                        child: Row(children: [
                          Icon(
                            m == _sort
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: m == _sort
                                ? colors.accent
                                : colors.textTertiary,
                          ),
                          const SizedBox(width: 10),
                          Text(m.label,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: m == _sort
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ]),
                      ))
                  .toList();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _sort.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 15, color: colors.textTertiary),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Verified pill
          GestureDetector(
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _verifiedOnly = !_verifiedOnly);
              _fireSearch();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _verifiedOnly
                    ? colors.accentSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _verifiedOnly
                      ? colors.accent
                      : colors.divider,
                  width: _verifiedOnly ? 1.5 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _verifiedOnly
                        ? Icons.verified_rounded
                        : Icons.verified_outlined,
                    size: 12,
                    color: _verifiedOnly
                        ? colors.accent
                        : colors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Verified',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _verifiedOnly
                          ? colors.accent
                          : colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Advanced filter
          GestureDetector(
            onTap: _openFilters,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasFilters
                    ? colors.accentSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      hasFilters ? colors.accent : colors.divider,
                  width: hasFilters ? 1.5 : 0.5,
                ),
              ),
              child: Icon(Icons.filter_list_rounded,
                  size: 15,
                  color: hasFilters
                      ? colors.accent
                      : colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the story viewer for a business's stories (not their profile).
  /// Both production and demo mode use the same API route — in demo mode the
  /// DemoInterceptor supplies the seeded business-specific story response.
  void _openBusinessStories(BuildContext context, String bizId) async {
    try {
      final res = await apiClient.get('/stories/business/$bizId');
      final body = jsonDecode(res.body);
      final groups = (body['groups'] as List? ?? [])
          .map((g) => StoryGroup.fromJson(g as Map<String, dynamic>))
          .toList();
      if (groups.isNotEmpty && context.mounted) {
        await StoryViewerScreen.open(context, groups: groups, initialGroupIndex: 0, heroTag: 'marketplace-story-ring-$bizId');
      } else if (context.mounted) {
        context.push('/business/$bizId');
      }
    } catch (_) {
      if (context.mounted) {
        context.push('/business/$bizId');
      }
    }
  }

  String _categoryLabel(String? cat) {
    switch (cat) {
      case 'FOOD_BEVERAGE': return 'restaurants';
      case 'REAL_ESTATE': return 'hotels & stays';
      case 'LOGISTICS': return 'transit services';
      case 'RETAIL': return 'retail shops';
      case 'FREELANCE_SERVICES': return 'service providers';
      case 'HEALTH_WELLNESS': return 'beauty & wellness';
      default: return 'businesses';
    }
  }

  // ── Results bar (slim control row) ─────────────────────────────────────────

  // ── Featured rail (§2) — collapsed by default ─────────────────────────────

  Widget _featuredSection(AzamanColors colors) {
    final featured = ref.watch(featuredBusinessesProvider);
    if (featured.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AzamanHaptics.toggle();
            setState(() => _featuredExpanded = !_featuredExpanded);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 6),
                Text('Featured picks near you',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                        fontSize: 13)),
                const Spacer(),
                AnimatedRotation(
                  turns: _featuredExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: colors.textTertiary, size: 20),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          child: _featuredExpanded
              ? _featuredRail(featured, colors)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _featuredRail(
      List<BusinessProfile> featured, AzamanColors colors) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(
          width: 260,
          child: _FeaturedCard(business: featured[i], colors: colors),
        ),
      ),
    );
  }

  // ── Real map mode (§1) ─────────────────────────────────────────────────────

  Set<Marker> _buildMarkers(List<BusinessLocation> locations) {
    return locations.map((loc) {
      final cat = BusinessCategories.fromWire(
          loc.businessProfileId.isNotEmpty ? 'OTHER' : 'OTHER');
      // Use default marker with hue derived from category color as first pass
      final hue = _hueFromColor(cat.color);
      return Marker(
        markerId: MarkerId(loc.id),
        position: LatLng(loc.latitude, loc.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _showBusinessPreviewSheet(loc),
      );
    }).toSet();
  }

  double _hueFromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    return hsv.hue;
  }

  void _showBusinessPreviewSheet(BusinessLocation loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => FutureBuilder(
        future: BusinessService().getBusinessByBizId(loc.businessProfileId),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final business = snap.data;
          if (business == null) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('Business not found'),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Consumer(builder: (ctx2, ref, _) {
              final colors = ref.watch(themeProvider).colors;
              return Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CollapsibleBusinessBar(
                  key: ValueKey('map-preview-\${loc.id}'),
                  business: business,
                  isExpanded: true,
                  onToggle: () => Navigator.of(ctx2).pop(),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _recenterButton(AzamanColors colors) {
    return GestureDetector(
      onTap: () {
        if (_position != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(_position!.latitude, _position!.longitude),
            ),
          );
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.my_location_rounded, color: colors.accent, size: 22),
      ),
    );
  }

  static const _darkMapStyleJson = r'''
  [
    {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#000000"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a2a3e"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9a9a9a"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b2a"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e1e30"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2a2a3e"}]}
  ]
  ''';

  // ── List mode ──────────────────────────────────────────────────────────────

  Widget _listMode(AzamanColors colors) {
    final state = ref.watch(businessSearchProvider);

    if (state.isLoading) return _listShimmer(colors);

    final results = _applySortFilter(state.results);

    if (results.isEmpty) {
      return ListView(
          children: [
            const SizedBox(height: 60),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    child: LottieBuilder.asset('assets/animations/success.json', width: 120, height: 120, repeat: false),
                  )
                    .animate().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 12),
                  Text('No businesses found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    _searchCtrl.text.isNotEmpty
                        ? 'Try a different search term or category'
                        : _selectedCategory != null
                            ? 'No ${_categoryLabel(_selectedCategory)} yet — be the first!'
                            : 'Be the first to register here',
                    style: TextStyle(fontSize: 13, color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        );
      }

    return ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 120),
        itemCount: results.length + (state.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          // Infinite-scroll loader sentinel
          if (i >= results.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final b = results[i];
          return CollapsibleBusinessBar(
            key: ValueKey(b.bizId),
            business: b,
            isExpanded: _expandedBizId == b.bizId,
            onToggle: () {
              setState(() {
                _expandedBizId = _expandedBizId == b.bizId ? null : b.bizId;
              });
            },
            distanceKm: b.locations.isNotEmpty ? b.locations.first.distanceKm : null,
          ).animate().fadeIn(delay: (i * 50).ms, duration: 300.ms, curve: Curves.easeOutCubic).slideY(begin: 0.15, end: 0, delay: (i * 50).ms, duration: 300.ms, curve: Curves.easeOutCubic);
        },
    );
  }

  // ── LIST shimmer ────────────────────────────────────────────────────────────

  Widget _listShimmer(AzamanColors colors) {
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.softSurface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 60),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          height: 68,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 13, width: 160, color: colors.divider),
                    const SizedBox(height: 7),
                    Container(height: 10, width: 100, color: colors.divider),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MAP mode (unchanged from previous version) ─────────────────────────────

  Widget _mapMode(AzamanColors colors) {
    final state = ref.watch(nearbySearchProvider);

    if (_position == null) return _locationPrompt(colors);

    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonBlock(width: double.infinity, height: 120, borderRadius: BorderRadius.circular(16)),
            const SizedBox(height: 12),
            SkeletonBlock(width: double.infinity, height: 80, borderRadius: BorderRadius.circular(12)),
            const SizedBox(height: 12),
            ...List.generate(3, (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SkeletonBlock(width: double.infinity, height: 56, borderRadius: BorderRadius.circular(12)),
            )),
          ],
        ),
      );
    }

    final locations = state.locations;
    if (locations.isEmpty) {
      return ListView(children: const [
          SizedBox(height: 60),
          AzamanEmptyState(
            icon: Icons.location_off_outlined,
            title: 'No businesses nearby',
            subtitle: 'Try expanding your search area.',
          ),
        ]);
    }

    // §1: Real embedded GoogleMap instead of a list view
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_position!.latitude, _position!.longitude),
            zoom: 14,
          ),
          markers: _buildMarkers(locations),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) => _mapController = controller,
          style: colors.isDark ? _darkMapStyleJson : null,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _recenterButton(colors),
        ),
      ],
    );
  }

  Widget _locationPrompt(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_on_outlined,
                  size: 36, color: colors.accent),
            ),
            const SizedBox(height: 18),
            Text(
              'Find businesses near you',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _locationError ??
                  'Share your location to see nearby businesses with distances.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _resolveLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor:
                    colors.isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _resolvingLocation
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.isDark
                              ? Colors.black
                              : Colors.white),
                    )
                  : const Icon(Icons.location_on_outlined, size: 18),
              label: Text(
                  _resolvingLocation
                      ? 'Locating...'
                      : 'Use my location',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}


// =============================================================================
// ── Portal world card (2026-09-30) ───────────────────────────────────────────

/// Immutable view-model for one portal world: the category identity plus a
/// truthful count and preview derived from the loaded search state.
class _FeaturedCard extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;

  const _FeaturedCard({required this.business, required this.colors});

  String? _coverUrl(BusinessCategory cat) {
    if (business.showcaseUrls.isNotEmpty) return business.showcaseUrls.first;
    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return business.logoUrl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cat = BusinessCategories.fromWire(business.category);
    final coverUrl = _coverUrl(cat);

    return GestureDetector(
      onTap: () {
        AzamanHaptics.nav();
        context.push('/business/\${business.bizId}');
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.isDark ? 0.22 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image (taller)
              SizedBox(
                height: 120,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverUrl != null)
                      AzamanNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(cat),
                        errorWidget: (_, __, ___) => _placeholder(cat),
                      )
                    else
                      _placeholder(cat),
                    // Category tag overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        color: cat.color.withValues(alpha: 0.82),
                        child: Text(
                          cat.label.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.businessName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (business.isVerified)
                          Icon(Icons.verified_rounded, size: 12, color: colors.accent),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (business.averageRating > 0) ...[
                          Icon(Icons.star_rounded, size: 11, color: const Color(0xFFF59E0B)),
                          const SizedBox(width: 2),
                          Text(
                            business.averageRating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (business.locations.isNotEmpty) ...[
                          Builder(builder: (_) {
                            final status = currentOpenStatus(business.locations.first.operatingHours);
                            if (status == OpenStatus.open)
                              return StatusDot(color: Colors.green, label: 'Open');
                            if (status == OpenStatus.closingSoon)
                              return StatusDot(color: Colors.orange, label: 'Closing soon');
                            if (status == OpenStatus.closed)
                              return StatusDot(color: colors.textTertiary, label: 'Closed');
                            return const SizedBox.shrink();
                          }),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BusinessCategory cat) => Container(
        color: cat.color.withValues(alpha: 0.12),
        child: Center(child: Icon(cat.icon, size: 30, color: cat.color.withValues(alpha: 0.5))),
      );
}
