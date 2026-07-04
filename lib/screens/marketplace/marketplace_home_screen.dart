// lib/screens/marketplace/marketplace_home_screen.dart
// =============================================================================
// AZAMAN — MARKETPLACE HOME SCREEN (Redesign, 2026-07-04)
//
// Structure (top → bottom):
//   _header()              — title + bookmark + filter icon (opens endDrawer)
//   _searchBar()           — full-width search bar, context-aware placeholder
//   _activeCategoryChip()  — shown only when a category is active (clearable)
//   _resultsBar()          — slim row: count · Sort ▼ · Verified pill · Filter
//   Expanded(_listMode() or _mapMode())
//
// endDrawer = CategoryFilterDrawer (slides in from right on filter tap).
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
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/category_filter_drawer.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessSearchProvider.notifier).search('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
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
      endDrawer: CategoryFilterDrawer(
        selectedCategory: _selectedCategory,
        onSelected: (cat) {
          setState(() {
            _selectedCategory = cat;
            // Collapse any expanded bar when category changes
            _expandedBizId = null;
          });
          _fireSearch();
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(colors),
            const SizedBox(height: 10),
            _searchBar(colors),
            if (_selectedCategory != null) ...[
              const SizedBox(height: 6),
              _activeCategoryChip(colors),
            ],
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
    );
  }

  // ── Header (title + actions) ────────────────────────────────────────────────

  Widget _header(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: colors.textPrimary,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
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
          const SizedBox(width: 8),

          // Saved businesses
          _iconAction(
            icon: Icons.bookmark_outline_rounded,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SavedBusinessesScreen()),
              );
            },
            colors: colors,
          ),
          const SizedBox(width: 8),

          // Filter / categories (opens endDrawer)
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () {
                AzamanHaptics.toggle();
                Scaffold.of(ctx).openEndDrawer();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _selectedCategory != null
                      ? colors.accentSurface
                      : colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedCategory != null
                        ? colors.accent
                        : colors.divider,
                    width: _selectedCategory != null ? 1.5 : 0.5,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: _selectedCategory != null
                          ? colors.accent
                          : colors.textSecondary,
                    ),
                    if (_selectedCategory != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  // ── Search bar ──────────────────────────────────────────────────────────────

  Widget _searchBar(AzamanColors colors) {
    final catLabel = _selectedCategory != null
        ? BusinessCategories.labelFor(_selectedCategory)
            .toLowerCase()
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _fireSearch(),
        style: TextStyle(color: colors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: catLabel != null
              ? 'Search $catLabel...'
              : 'Search all businesses...',
          hintStyle:
              TextStyle(color: colors.textTertiary, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: colors.textTertiary),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.cancel_rounded,
                      size: 18, color: colors.textTertiary),
                  onPressed: () {
                    _searchCtrl.clear();
                    _fireSearch();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: colors.card,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: colors.divider, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: colors.divider, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: colors.accent, width: 1.5),
          ),
        ),
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
            AzamanEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No businesses found',
              subtitle: _selectedCategory != null
                  ? 'No ${BusinessCategories.labelFor(_selectedCategory)} businesses yet. Try a different category.'
                  : 'Try a different search or category.',
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
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
              AzamanHaptics.toggle();
              setState(() {
                _expandedBizId =
                    _expandedBizId == b.bizId ? null : b.bizId;
              });
            },
          );
        },
      ),
    );
  }

  // ── LIST shimmer ────────────────────────────────────────────────────────────

  Widget _listShimmer(AzamanColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 60),
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

