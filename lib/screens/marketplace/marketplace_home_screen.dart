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
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/advanced_filter_sheet.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/models/story_model.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/screens/marketplace/business_register_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shimmer/shimmer.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/config.dart';

enum _ViewMode { list, map }

enum _SortMode { topRated, mostPopular, nearest, newest }

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
  const MarketplaceHomeScreen({super.key});

  @override
  ConsumerState<MarketplaceHomeScreen> createState() =>
      _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState
    extends ConsumerState<MarketplaceHomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;
  Timer? _debounce;

  // Category filter — wire value string (null = All)
  String? _selectedCategory;

  // Accordion — which bar is currently expanded
  String? _expandedBizId;

  // Header search — collapsed icon <-> expanded inline search field
  bool _searchExpanded = false;
  bool _searchFocused = false;
  final _searchFocusNode = FocusNode();

  // Telegram-style stories collapse state
  bool _storiesCollapsed = false;
  // Cooldown to prevent story collapse/expand oscillation when content is short
  DateTime _lastStoryToggle = DateTime.fromMillisecondsSinceEpoch(0);
  // Location permission requested flag
  bool _locationRequested = false;

  // View / sort / filter state
  _ViewMode _viewMode = _ViewMode.list;
  _SortMode _sort = _SortMode.topRated;
  bool _verifiedOnly = false;
  MarketplaceFilters _filters = const MarketplaceFilters();

  // Location
  Position? _position;
  bool _resolvingLocation = false;
  String? _locationError;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        setState(() => _scrollOffset = _scrollCtrl.offset);
      }
    });
    _searchFocusNode.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocusNode.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessSearchProvider.notifier).search('');
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
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Query plumbing ─────────────────────────────────────────────────────────

  void _onScroll() {
    if (_viewMode == _ViewMode.list &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 320) {
      ref.read(businessSearchProvider.notifier).loadMore();
    }

    // Collapse/expand stories based on scroll position, with hysteresis
    // and a cooldown to prevent oscillation when
    // is collapsed and scrollable content is short (the 96px height
    // change from stories collapsing can otherwise create a loop).
    final now = DateTime.now();
    if (now.difference(_lastStoryToggle).inMilliseconds < 500) return;

    // Hysteresis: collapse at >50, expand at <15 — the gap prevents
    // the layout change from immediately re-triggering the opposite action.
    final shouldCollapse = _scrollCtrl.offset > (_storiesCollapsed ? 80 : 50);
    if (_storiesCollapsed != shouldCollapse) {
      _lastStoryToggle = now;
      setState(() => _storiesCollapsed = shouldCollapse);
    }
  }

  void _onQueryChanged(String value) {
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
          _searchCtrl.text.trim(),
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
          q: _searchCtrl.text.trim().isEmpty
              ? null
              : _searchCtrl.text.trim(),
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
            q: _searchCtrl.text.trim().isEmpty
                ? null
                : _searchCtrl.text.trim(),
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
          b.category != _selectedCategory) {
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
          _searchCtrl.text.trim(),
          category: _selectedCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  // ── Root build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // Scroll-driven gradient (0 at top → full when scrolled 120px)
    final expandRatio = (_scrollOffset / 120).clamp(0.0, 1.0);

    return Scaffold(
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
                  if (_searchExpanded) _closeSearch();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: _storiesCollapsed ? 0 : 96,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 96,
                          maxHeight: 96,
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
                    _categoryStrip(colors),
                    const SizedBox(height: 2),
                    _resultsBar(colors),
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
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const BusinessDashboardScreen(),
                    ));
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
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BusinessRegisterScreen(),
                  ));
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
    final catLabel = _selectedCategory != null
        ? BusinessCategories.labelFor(_selectedCategory).toLowerCase()
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Stack(
        children: [
          // ── Collapsed state: title + view toggle + search icon ──────────
          AnimatedSlide(
            offset: _searchExpanded ? const Offset(-0.2, 0) : Offset.zero,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _searchExpanded ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: _searchExpanded,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Stories shown as collapsed avatars in the header when scrolled
                    // down. At top, the full stories row appears below the header
                    // so no title text is needed here — removing the "Explore"
                    // text eliminates the vertical-letter-wrap bug on scroll.
                    if (_storiesCollapsed)
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
                      onTap: () => context.pushNamed('storefront-order-history'),
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
            offset: _searchExpanded ? Offset.zero : const Offset(0.2, 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _searchExpanded ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: !_searchExpanded,
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
                              color: _searchFocused ? colors.accent : Colors.transparent,
                              width: 1.4,
                            ),
                            boxShadow: _searchFocused
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
                            onSubmitted: (_) => _fireSearch(),
                            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: catLabel != null
                                  ? 'Search $catLabel...'
                                  : 'Search all businesses...',
                              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w400),
                              icon: Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                ? GestureDetector(onTap: () { _searchCtrl.clear(); _fireSearch(); setState(() {}); },
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
    setState(() => _searchExpanded = true);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchExpanded) return;
    AzamanHaptics.toggle();
    _searchFocusNode.unfocus();
    setState(() => _searchExpanded = false);
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

  Widget _categoryStrip(AzamanColors colors) {
    // Speed-dial category picker — shows only the current category as a
    // labeled chip ("Category" label above it). Tapping opens a radial
    // fan of the other categories using the liquid goo speed-dial.
    final categories = <CategoryDialItem>[
      CategoryDialItem(wire: null, icon: Icons.apps_rounded, label: 'All'),
      CategoryDialItem(wire: 'FOOD_BEVERAGE', icon: Icons.restaurant_rounded, label: 'Restaurants'),
      CategoryDialItem(wire: 'REAL_ESTATE', icon: Icons.apartment_rounded, label: 'Hotels'),
      CategoryDialItem(wire: 'LOGISTICS', icon: Icons.directions_bus_rounded, label: 'Transit'),
      CategoryDialItem(wire: 'RETAIL', icon: Icons.shopping_bag_rounded, label: 'Retail'),
      CategoryDialItem(wire: 'FREELANCE_SERVICES', icon: Icons.handyman_rounded, label: 'Services'),
      CategoryDialItem(wire: 'HEALTH_WELLNESS', icon: Icons.spa_rounded, label: 'Beauty'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: CategorySpeedDial(
          categories: categories,
          selectedWire: _selectedCategory,
          colors: colors,
          onSelected: (wire) {
            setState(() => _selectedCategory = wire);
            _fireSearch();
          },
        ),
      ),
    );
  }

  /// Opens the story viewer for a business's stories (not their profile).
  void _openBusinessStories(BuildContext context, String bizId) async {
    if (AppConfig.demoMode) {
      // In demo mode, create demo story groups with placeholder content
      // so the story viewer opens properly instead of redirecting to the
      // business profile page.
      final demoGroups = _buildDemoStoryGroups(bizId);
      if (context.mounted) {
        await StoryViewerScreen.open(context, groups: demoGroups, initialGroupIndex: 0, heroTag: 'marketplace-story-ring-$bizId');
      }
      return;
    }
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

  /// Builds demo story groups for a business in demo mode.
  List<StoryGroup> _buildDemoStoryGroups(String bizId) {
    return [
      StoryGroup(
        authorId: 0,
        authorUsername: 'Demo Business',
        authorAvatarUrl: null,
        hasUnseen: true,
        isBoosted: false,
        stories: [
          StoryItem(
            id: 'demo-story-1',
            mediaUrl: 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800',
            mediaType: 'IMAGE',
            caption: 'Welcome to our store! 🎉',
            durationSeconds: 5,
            boosted: false,
            seen: false,
            createdAt: DateTime.now(),
          ),
          StoryItem(
            id: 'demo-story-2',
            mediaUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800',
            mediaType: 'IMAGE',
            caption: 'Check out our latest products',
            durationSeconds: 5,
            boosted: false,
            seen: false,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    ];
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

  Widget _resultsBar(AzamanColors colors) {
    final state = ref.watch(businessSearchProvider);
    final count = _applySortFilter(state.results).length;
    final hasFilters = !_filters.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        children: [
          // Count
          if (!state.isLoading && count > 0)
            Text(
              '$count business${count == 1 ? '' : 'es'}',
              style: TextStyle(
                fontSize: 12,
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (!state.isLoading && count > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: colors.divider,
                shape: BoxShape.circle,
              ),
            ),

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

          const Spacer(),

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

  // ── LIST mode ──────────────────────────────────────────────────────────────

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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
      itemCount: locations.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _nearbyCard(locations[i], colors),
    );
  }

  Widget _nearbyCard(BusinessLocation loc, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        final uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${loc.latitude},${loc.longitude}');
        launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.location_on_outlined,
                  size: 20, color: colors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loc.label.isNotEmpty ? loc.label : 'Branch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loc.distanceKm != null)
                  Text(
                    '${loc.distanceKm!.toStringAsFixed(1)} km',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 4),
                Icon(Icons.near_me_outlined,
                    size: 16, color: colors.textTertiary),
              ],
            ),
          ],
        ),
      ),
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
