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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/advanced_filter_sheet.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/screens/marketplace/business_register_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';

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

  bool get _isIdle =>
      _searchCtrl.text.trim().isEmpty &&
      _selectedCategory == null &&
      !_verifiedOnly &&
      _filters.isEmpty;

  void _onScroll() {
    if (_viewMode == _ViewMode.list &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 320) {
      ref.read(businessSearchProvider.notifier).loadMore();
    }
    
    // Collapse stories if scrolled down by more than 10 pixels
    final shouldCollapse = _scrollCtrl.offset > 10;
    if (_storiesCollapsed != shouldCollapse) {
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
          b.averageRating < _filters.minRating) return false;
      if ((_filters.verifiedOnly || _verifiedOnly) && !b.isVerified)
        return false;
      if (_selectedCategory != null &&
          b.category != _selectedCategory) return false;
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

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: _businessFab(colors),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(colors),
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
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: _storiesCollapsed
                          ? const SizedBox.shrink()
                          : MarketplaceExpandedStories(
                              onOpenBusiness: (bizId) {
                                setState(() => _expandedBizId = bizId);
                              },
                              onBrowsePressed: () {
                                setState(() => _selectedCategory = null);
                              },
                            ),
                    ),
                    _categoryStrip(colors),
                    if (_selectedCategory == null && _searchCtrl.text.isEmpty)
                      _featuredCarousel(colors),
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
    );
  }

  // ── Business registration / dashboard entry point ───────────────────────────
  // Moved here from the settings drawer (2026-07-06) — lives where businesses
  // are actually browsed. Shows "Register Business" if the signed-in user has
  // no business profile yet, or "Your Business" (deep-links to their
  // dashboard) once they're registered.
  Widget _businessFab(AzamanColors colors) {
    final bizState = ref.watch(myBusinessProvider);

    // Avoid a flash of the wrong state while the initial fetch is in flight.
    if (bizState.isLoading && !bizState.hasLoaded) {
      return const SizedBox.shrink();
    }

    final isRegistered = bizState.profile != null;

    // 2026-07-08: shrunk from a FloatingActionButton.extended (icon+text
    // pill) to just a circular emoji bubble — same tap target/destination,
    // less visual weight sitting over the marketplace feed.
    return Tooltip(
      message: isRegistered ? 'Your Business' : 'Register Business',
      child: FloatingActionButton(
        heroTag: 'marketplace_business_fab',
        backgroundColor: colors.accent,
        foregroundColor: Colors.white,
        onPressed: () {
          AzamanHaptics.nav();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => isRegistered
                ? const BusinessDashboardScreen()
                : const BusinessRegisterScreen(),
          ));
        },
        child: Text(isRegistered ? '🏬' : '🏪', style: const TextStyle(fontSize: 22)),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(colors: [colors.accent, colors.accent]).createShader(bounds),
                            child: Text('Explore', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.6, height: 1.1)),
                          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
                          Text(
                            'Find trusted businesses',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Collapsed avatars between Explore text and Search button
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: _storiesCollapsed
                          ? Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: MarketplaceCollapsedAvatars(
                                onTap: () {
                                  _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Search — directly after "Explore", in line with the view toggle.
                    // Tapping it morphs this whole row into an inline search field.
                    _iconAction(
                      icon: Icons.search_rounded,
                      onTap: _openSearch,
                      colors: colors,
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
                                ? [BoxShadow(color: colors.accent.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 3))]
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
    return GestureDetector(
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
    return GestureDetector(
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
    // "All" is a real first entry now (null wire value) — biggest chip in
    // the strip, everything else shrinks slightly to make room for it.
    final categories = <(String?, dynamic, String)>[
      (null, Icons.apps_rounded, 'All'),
      ('FOOD_BEVERAGE', HugeIcons.strokeRoundedRestaurant01, 'Restaurants'),
      // Wire value fixed 2026-07-06: hotels are registered under REAL_ESTATE
      // (see BusinessCategory enum + business portal Onboarding.jsx) — the
      // old 'HOSPITALITY' value here was never assigned to any business, so
      // this chip silently returned zero results. Label kept broad ("Hotels
      // & Stay") since REAL_ESTATE also covers guesthouses/resorts/short-stay.
      ('REAL_ESTATE', HugeIcons.strokeRoundedBuilding05, 'Hotels & Stay'),
      ('LOGISTICS', HugeIcons.strokeRoundedBus01, 'Transit'),
      ('RETAIL', HugeIcons.strokeRoundedShoppingBag01, 'Retail'),
      // Same bug, same fix: these two wire values didn't exist in the
      // backend BusinessCategory enum at all (real values are
      // FREELANCE_SERVICES / HEALTH_WELLNESS) — both chips returned zero
      // results no matter what was registered.
      ('FREELANCE_SERVICES', HugeIcons.strokeRoundedWrench01, 'Services'),
      ('HEALTH_WELLNESS', HugeIcons.strokeRoundedBlushBrush01, 'Beauty'),
    ];
    // Shrunk 2026-07-08 (Stan: "a bit too big for my liking") — trimmed
    // height/padding/icon+font sizes across the board, and every chip (not
    // just the active one) now carries a subtle resting shadow so the strip
    // reads as a row of small floating cards instead of flat pills.
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final catItem = categories[i];
          final isAll = catItem.$1 == null;
          final isActive = _selectedCategory == catItem.$1;
          final iconSize = isAll ? 20.0 : 16.0;
          final fontSize = isAll ? 12.0 : 11.0;
          final hPad = isAll ? 14.0 : 12.0;
          final vPad = isAll ? 10.0 : 8.0;
          return GestureDetector(
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _selectedCategory = isAll ? null : (isActive ? null : catItem.$1));
              _fireSearch();
            },
            child: AnimatedContainer(
              duration: 300.ms, curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                color: isActive ? colors.accentSurface : colors.card,
                borderRadius: BorderRadius.circular(isAll ? 10 : 9),
                border: Border.all(color: isActive ? colors.accent : colors.divider, width: isActive ? 1.2 : 0.5),
                boxShadow: [
                  BoxShadow(
                    color: isActive ? colors.accent.withOpacity(0.18) : Colors.black.withOpacity(0.06),
                    blurRadius: isActive ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  isAll
                      ? Icon(catItem.$2 as IconData, size: iconSize, color: isActive ? colors.accent : colors.textSecondary)
                      : HugeIcon(icon: catItem.$2, size: iconSize, color: isActive ? colors.accent : colors.textSecondary),
                  SizedBox(height: 2),
                  Text(catItem.$3, style: TextStyle(fontSize: fontSize, fontWeight: isActive || isAll ? FontWeight.w700 : FontWeight.w500, color: isActive ? colors.accent : colors.textSecondary)),
                ],
              ),
            ),
          ).animate().fadeIn(delay: (i * 60).ms, duration: 250.ms).slideX(begin: 0.2, end: 0, delay: (i * 60).ms, duration: 250.ms, curve: Curves.easeOutCubic);
        },
      ),
    );
  }

  // ── "Featured Near You" carousel ────────────────────────────────────────────
  // Only shown on the unfiltered/un-searched home feed (2026-07-08) — once a
  // category is selected or a search is active, this makes way for the
  // regular results list so it doesn't compete for attention.

  List<BusinessProfile> _topRated(List<BusinessProfile> all) {
    final rated = all.where((b) => b.averageRating > 0).toList()
      ..sort((a, b) => b.averageRating.compareTo(a.averageRating));
    return rated.take(10).toList();
  }

  Widget _featuredCarousel(AzamanColors colors) {
    final state = ref.watch(businessSearchProvider);

    if (state.isLoading) return _featuredShimmer(colors);

    final featured = _topRated(state.results);
    if (featured.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Featured Near You',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.textPrimary)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final b = featured[i];
                return _FeaturedBusinessCard(
                  business: b,
                  colors: colors,
                  onTap: () {
                    AzamanHaptics.nav();
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => BusinessProfileScreen(bizId: b.bizId)));
                  },
                )
                    .animate()
                    .fadeIn(delay: (i * 70).ms, duration: 320.ms)
                    .slideX(begin: 0.15, end: 0, delay: (i * 70).ms, duration: 320.ms, curve: Curves.easeOutCubic);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _featuredShimmer(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 15, width: 140, decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: Shimmer.fromColors(
              baseColor: colors.card,
              highlightColor: colors.softSurface,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (_, __) => Container(
                  width: 280,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active category chip ────────────────────────────────────────────────────

  Widget _activeCategoryChip(AzamanColors colors) {
    final wire = _selectedCategory!;
    final cat = BusinessCategories.fromWire(wire);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = null;
                _expandedBizId = null;
              });
              _fireSearch();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              decoration: BoxDecoration(
                color: cat.color.withOpacity(0.09),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: cat.color.withOpacity(0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.icon, size: 13, color: cat.color),
                  const SizedBox(width: 5),
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cat.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.close_rounded,
                      size: 13, color: cat.color.withOpacity(0.6)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
      return RefreshIndicator(
        color: colors.accent,
        onRefresh: _refresh,
        child: ListView(
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
                  Text(_searchCtrl.text.isNotEmpty ? 'Try a different search term' : 'Be the first to register here',
                    style: TextStyle(fontSize: 13, color: colors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _refresh,
      child: ListView.builder(
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
      ),
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
      return const Center(child: CircularProgressIndicator());
    }

    final locations = state.locations;
    if (locations.isEmpty) {
      return RefreshIndicator(
        color: colors.accent,
        onRefresh: _fireNearby,
        child: ListView(children: [
          const SizedBox(height: 60),
          AzamanEmptyState(
            icon: Icons.location_off_outlined,
            title: 'No businesses nearby',
            subtitle: 'Try expanding your search area.',
          ),
        ]),
      );
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _fireNearby,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
              itemCount: locations.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (_, i) =>
                  _nearbyCard(locations[i], colors),
            ),
          ),
        ],
      ),
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


// ─────────────────────────────────────────────────────────────────────────────
// FeaturedBusinessCard — wide "Featured Near You" carousel card (2026-07-08)
//
// ~280px wide: large cover image, business avatar overlapping the bottom
// edge of the image (like a business card tucked into a photo), name +
// star rating below.
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedBusinessCard extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _FeaturedBusinessCard({
    required this.business,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = business.showcaseUrls.isNotEmpty ? business.showcaseUrls.first : business.logoUrl;
    final cat = BusinessCategories.fromWire(business.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover image
                SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: cat.color.withOpacity(0.15)),
                          errorWidget: (_, __, ___) => Container(color: cat.color.withOpacity(0.15)),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [cat.color, cat.color.withOpacity(0.5)],
                            ),
                          ),
                          child: Center(child: Icon(cat.icon, size: 36, color: Colors.white.withOpacity(0.5))),
                        ),
                ),
                // Name + rating (indented to make room for the overlapping avatar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 26, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: colors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          RatingStars(rating: business.averageRating, size: 12, showNumber: true),
                          if (business.isVerified) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, size: 13, color: colors.accent),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Avatar — squircle (matches chat story rings)
            Positioned(
              left: 14,
              top: 118 - 24,
              child: Container(
                width: 48, height: 48,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: ContinuousRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: business.logoUrl != null
                      ? CachedNetworkImage(imageUrl: business.logoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: cat.color.withOpacity(0.2),
                          child: Icon(cat.icon, size: 20, color: cat.color),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
