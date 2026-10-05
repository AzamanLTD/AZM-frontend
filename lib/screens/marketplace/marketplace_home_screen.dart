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

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_nav_focus.dart';
import 'package:azaman/providers/marketplace_search_binding.dart';
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/models/story_model.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:shimmer/shimmer.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum _ViewMode { list, map }

enum _SortMode { topRated, mostPopular, nearest, newest }

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
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;
  // Live results while typing: debounce the already-updated provider text
  // into the existing search plumbing.
  Timer? _debounce;

  // Category filter — wire value string (null = All)
  String? _selectedCategory;

  // Accordion — which bar is currently expanded
  String? _expandedBizId;

  // Story height is driven by scroll offset — no manual toggle needed.
  // At offset 0: fully expanded (96px). At offset 96: fully collapsed (0px).
  // Location permission requested flag
  bool _locationRequested = false;

  // View / sort / filter state
  _ViewMode _viewMode = _ViewMode.list;
  _SortMode _sort = _SortMode.topRated;

  // Location
  Position? _position;
  bool _resolvingLocation = false;
  String? _locationError;

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
    _scrollCtrl.addListener(_onScroll);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        setState(() => _scrollOffset = _scrollCtrl.offset);
      }
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
    _scrollCtrl.dispose();
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

  /// CORRECTION I: the search field lives in the focused Marketplace nav
  /// band and writes to the AUTHORITATIVE provider through the SAME
  /// [MarketplaceSearchBinding] seam this screen always used — no second
  /// search provider exists. The screen reacts to committed text changes
  /// with its existing debounced plumbing. Called from build via
  /// `ref.listen` so the response is part of the normal build cycle.
  void _onProviderTextChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fireSearch);
  }

  void _fireSearch() {
    if (_viewMode == _ViewMode.map) {
      _fireNearby();
      return;
    }
    ref.read(businessSearchProvider.notifier).search(
          _query,
          category: _selectedCategory,
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
      if (_selectedCategory != null &&
          !_categoryMatchesBusiness(b.category, _selectedCategory!)) {
        return false;
      }
      return true;
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

  Future<void> _refresh() {
    return ref.read(businessSearchProvider.notifier).search(
          _query,
          category: _selectedCategory,
        );
  }

  // ── Back + search clear (correction H/I) ────────────────────────────────────
  //
  // Back semantics: a committed search clears first; otherwise the bare
  // marketplace root lets the system back do its thing.

  void _handleBack() {
    if (_searchActive) _clearSearch();
  }

  /// Clears the AUTHORITATIVE provider — the focused-nav search field
  /// mirrors the committed text out of it, and the provider listener
  /// re-fires the results.
  void _clearSearch() {
    AzamanHaptics.toggle();
    _debounce?.cancel();
    _binding.clear();
    _fireSearch();
  }

  // ── Root build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // CORRECTION I: the focused-nav search field writes to the AUTHORITATIVE
    // provider through the SAME [MarketplaceSearchBinding] seam this screen
    // always used — no second search provider exists. The screen reacts to
    // committed text changes with its existing debounced plumbing.
    ref.listen(marketplaceSearchProvider.select((s) => s.text),
        (_, text) {
      _onProviderTextChanged(text);
    });

    // Scroll-driven gradient (0 at top → full when scrolled 120px)
    final expandRatio = (_scrollOffset / 120).clamp(0.0, 1.0);
    // §16 — the story rail's collapse now speaks the SAME grammar as
    // chat's story rail: shared travel (StoryRailCollapse.travelPx),
    // the shared snap threshold, and reduced-motion handling that
    // lands directly instead of sliding. No second Telegram-like
    // implementation lives in this file anymore.
    final storyExpandRatio = StoryRailCollapse.ratio(
      scrollOffset: _scrollOffset,
      reducedMotion: !AzMotion.of(context).travel,
    );

    final searchActive =
        ref.watch(marketplaceSearchProvider.select((s) => s.isActive));
    // Back semantics (correction H): the marketplace root is ONE result
    // screen. A committed search clears first; otherwise the system back
    // does its normal thing.
    final canPop = !searchActive;

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
            // CORRECTION I: tapping anywhere on Marketplace content (while
            // the user is on this root screen) restores the focused
            // Marketplace nav — the "…" exit is a presentation change of
            // the SAME tab, and content interaction brings it back. The
            // Listener is observational: it never consumes or blocks the
            // child's own taps and gestures.
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) {
                  if (!ref.read(marketplaceNavFocusProvider)) {
                    ref
                        .read(marketplaceNavFocusProvider.notifier)
                        .state = true;
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Stories: smooth scroll-driven height (Telegram-style) ──
                    SizedBox(
                      height: StoryRailCollapse.extentPx * storyExpandRatio,
                      width: double.infinity,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: StoryRailCollapse.extentPx,
                          maxHeight: StoryRailCollapse.extentPx,
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
                    // ── §11: the category SPEED DIAL is the category
                    // system (radial fan grammar) + Near You as the only
                    // additional control. §12: no star/featured surface.
                    _controlRow(colors),
                    Expanded(
                      child: _viewMode == _ViewMode.list
                          ? _listMode(colors)
                          : _mapMode(colors),
                    ),
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
    // CORRECTION I: the search affordance no longer lives in this screen —
    // the focused Marketplace nav band owns the search field, bound to the
    // AUTHORITATIVE provider. The header keeps the story avatars slot, the
    // storefront management, order history, and the list/map view toggle.
    final storyExpandRatio = StoryRailCollapse.ratio(
      scrollOffset: _scrollOffset,
      reducedMotion: !AzMotion.of(context).travel,
    );
    final storyCollapsedOpacity = (1.0 - storyExpandRatio).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
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
                _viewSeg(
                    Icons.location_on_outlined, _ViewMode.map, colors),
              ],
            ),
          ),
        ],
      ),
    );
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

  // The category set the marketplace actually supports today (§11):
  // All is a REAL selectable state (wire null), then every currently
  // supported primary marketplace category. Icons match the category
  // system's existing icon treatments.
  static const List<CategoryDialItem> _dialCategories = [
    CategoryDialItem(
        wire: null, icon: Icons.apps_rounded, label: 'All'),
    CategoryDialItem(
        wire: 'FOOD_BEVERAGE',
        icon: Icons.restaurant_rounded,
        label: 'Eat'),
    CategoryDialItem(
        wire: 'RETAIL', icon: Icons.shopping_bag_rounded, label: 'Shop'),
    CategoryDialItem(
        wire: 'LOGISTICS',
        icon: Icons.directions_bus_rounded,
        label: 'Ride'),
    CategoryDialItem(
        wire: 'REAL_ESTATE',
        icon: Icons.apartment_rounded,
        label: 'Stay'),
    CategoryDialItem(
        wire: 'FREELANCE_SERVICES',
        icon: Icons.handyman_rounded,
        label: 'Services'),
    CategoryDialItem(
        wire: 'HEALTH_WELLNESS',
        icon: Icons.spa_rounded,
        label: 'Wellness'),
  ];

  // EXPERIENCE PASS §11 — the category SPEED DIAL is THE category system.
  // The radial fan / goo-morph arms remain the visual grammar; the old row
  // of standalone category buttons (correction H) is gone — the spec
  // explicitly rejects a second flat control row. Near You stays as the
  // ONLY additional control, with a location icon in the same visual
  // language, driving the existing near-you map machinery.
  Widget _controlRow(AzamanColors colors) {
    final nearYou = _viewMode == _ViewMode.map;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // UX-CORRECTION: the dial is COMPACT — intrinsic pill width, no
          // Expanded stretch. The radial fan anchors to the pill's real
          // box; a stretched slot made the whole empty row-width part of
          // the anchor (and the fan fanned off a rect the eye doesn't
          // see). The pill and Near You sit together at the left, in the
          // same pill language.
          CategorySpeedDial(
            key: const ValueKey('marketplace-category-dial'),
            categories: _dialCategories,
            selectedWire: _selectedCategory,
            colors: colors,
            onSelected: (wire) {
              AzamanHaptics.toggle();
              setState(() => _selectedCategory = wire);
              _fireSearch();
            },
          ),
          const SizedBox(width: AzSpace.sm),
          // Near You — the ONLY control outside the category selector
          // (location icon, same pill language). Toggling off returns to
          // the list view.
          GestureDetector(
            key: const ValueKey('marketplace-near-you'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.toggle();
              _setViewMode(nearYou ? _ViewMode.list : _ViewMode.map);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: nearYou
                    ? colors.accent.withValues(alpha: 0.12)
                    : colors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: nearYou ? colors.accent : colors.divider,
                  width: nearYou ? 1.2 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_rounded,
                      size: 14,
                      color: nearYou ? colors.accent : colors.textTertiary),
                  const SizedBox(width: 5),
                  Text(
                    'Near You',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          nearYou ? FontWeight.w700 : FontWeight.w600,
                      color: nearYou ? colors.accent : colors.textSecondary,
                    ),
                  ),
                ],
              ),
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
                    _query.isNotEmpty
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
