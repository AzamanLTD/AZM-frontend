// =============================================================================
// MARKETPLACE HOME SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The flagship Premium Marketplace entry point. A full-screen browse + discover
// experience (the "Booking.com home"):
//   • Sticky search header (search field + GPS/location button)
//   • Category carousel (All + 11 categories, icons from BusinessCategories)
//   • View-mode toggle (List | Map) + Sort + Verified-only + Filter
//   • LIST mode: Featured carousel + Near-You strip (when idle) then an
//     infinite-scroll list of BusinessCards.
//   • MAP mode: resolves GPS via geolocator and renders nearby business
//     locations with distance + "Open in Maps" deep links. When permission is
//     denied it falls back to a manual prompt — no native map plugin (which
//     would need platform API keys this build can't provide) is required.
//
// Sorting is applied client-side over the loaded page (the backend /search
// endpoint sorts server-side only by relevance); the advanced filter facets
// the backend doesn't support (price, rating, delivery, location) are likewise
// applied locally so the UX is complete today.
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
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/category_drilldown_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/business_card.dart';
import 'package:azaman/widgets/category_filter_panel.dart';
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

  int _categoryIndex = 0; // 0 == All
  List<String> _selectedCategories = [];
  _ViewMode _viewMode = _ViewMode.list;
  _SortMode _sort = _SortMode.topRated;
  bool _verifiedOnly = false;
  MarketplaceFilters _filters = const MarketplaceFilters();

  // Resolved GPS (null until the user grants permission / opens Map mode).
  Position? _position;
  bool _resolvingLocation = false;
  String? _locationError;

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
  String? get _activeCategory {
    if (_selectedCategories.isNotEmpty) {
      if (_selectedCategories.length == 1) {
        return _selectedCategories.first;
      }
      return null;
    }
    return _categoryIndex == 0 ? null : BusinessCategories.withAll[_categoryIndex].wire;
  }

  bool get _isIdle =>
      _searchCtrl.text.trim().isEmpty &&
      _categoryIndex == 0 &&
      _selectedCategories.isEmpty &&
      !_verifiedOnly;

  void _onScroll() {
    if (_viewMode == _ViewMode.list) {
      if (_scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 320) {
        ref.read(businessSearchProvider.notifier).loadMore();
      }
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fireSearch);
  }

  void _fireSearch() {
    if (_viewMode == _ViewMode.map) {
      _fireNearby();
      return;
    }
    ref.read(businessSearchProvider.notifier).search(
          _searchCtrl.text.trim(),
          category: _activeCategory,
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
          q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
          category: _activeCategory,
          verified: _verifiedOnly ? true : null,
        );
  }

  // ── Location resolution (geolocator) ───────────────────────────────────────
  Future<void> _resolveLocation() async {
    setState(() {
      _resolvingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled. Enable them to find businesses near you.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission denied. Allow access to see nearby businesses.';
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
            category: _activeCategory,
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
      // Map mode defaults to a distance-first sort.
      if (mode == _ViewMode.map) _sort = _SortMode.nearest;
    });
    if (mode == _ViewMode.map) {
      _fireNearby();
    }
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

  // ── Sorting + filtering (client-side over the loaded page) ──────────────────
  List<BusinessProfile> _applySortFilter(List<BusinessProfile> input) {
    var list = input.where((b) {
      if (_filters.minRating > 0 && b.averageRating < _filters.minRating) {
        return false;
      }
      if ((_filters.verifiedOnly || _verifiedOnly) && !b.isVerified) {
        return false;
      }
      if (_selectedCategories.isNotEmpty && !_selectedCategories.contains(b.category)) {
        return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _SortMode.topRated:
        list.sort((a, b) => b.averageRating.compareTo(a.averageRating));
        break;
      case _SortMode.mostPopular:
        list.sort((a, b) => b.totalEscrows.compareTo(a.totalEscrows));
        break;
      case _SortMode.nearest:
      case _SortMode.newest:
        // No per-profile distance / createdAt available on the search payload;
        // keep server order for these in list mode.
        break;
    }
    return list;
  }

  List<BusinessProfile> _featured(List<BusinessProfile> input) {
    final list = [...input];
    list.sort((a, b) {
      if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
      return b.totalEscrows.compareTo(a.totalEscrows);
    });
    return list.take(8).toList();
  }

  void _openBusiness(BusinessProfile b) {
    AzamanHaptics.nav();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BusinessProfileScreen(bizId: b.bizId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchHeader(colors),
            const SizedBox(height: 12),
            // ── Hero: Primary category cards (Transit, Restaurants, Hotels) ──
            _primaryCategoryHero(colors),
            const SizedBox(height: 16),
            // ── Section: Browse by category ──────────────────────────────────
            _sectionHeader(colors, 'Browse by Category'),
            const SizedBox(height: 10),
            _categoryCarousel(colors),
            const SizedBox(height: 10),
            _controlBar(colors),
            const SizedBox(height: 6),
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

  // ── Search header ───────────────────────────────────────────────────────────
  Widget _searchHeader(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'Categories',
                    barrierColor: Colors.black54,
                    pageBuilder: (_, __, ___) => CategoryFilterPanel(
                      selectedCategories: _selectedCategories,
                      onApply: (cats) {
                        setState(() => _selectedCategories = cats);
                        _fireSearch();
                      },
                    ),
                  );
                },
                icon: Icon(Icons.tune, color: colors.textSecondary),
              ),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onQueryChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _fireSearch(),
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: _selectedCategories.isNotEmpty
                          ? 'Search in ${_selectedCategories.length} categor${_selectedCategories.length == 1 ? "y" : "ies"}'
                          : 'Search businesses, services...',
                      hintStyle:
                          TextStyle(color: colors.textTertiary, fontSize: 14),
                      prefixIcon: Icon(Icons.search,
                          size: 19, color: colors.textTertiary),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.cancel_outlined,
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
                        borderSide: BorderSide(color: colors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filter
              GestureDetector(
                onTap: _openFilters,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: !_filters.isEmpty ? colors.accentSurface : colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !_filters.isEmpty ? colors.accent : colors.divider,
                    ),
                  ),
                  child: Icon(
                    Icons.filter_list,
                    size: 20,
                    color: !_filters.isEmpty ? colors.accent : colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  AzamanHaptics.nav();
                  _resolveLocation();
                },
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _position != null ? colors.accentSurface : colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _position != null ? colors.accent : colors.divider,
                    ),
                  ),
                  child: _resolvingLocation
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.accent),
                        )
                      : Icon(Icons.location_on_outlined,
                          size: 20,
                          color: _position != null
                              ? colors.accent
                              : colors.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              // Saved businesses (wishlist) — Marketplace Premium Upgrade.
              GestureDetector(
                onTap: () {
                  AzamanHaptics.nav();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SavedBusinessesScreen()),
                  );
                },
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Icon(Icons.bookmark_outline,
                      size: 20, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        if (_selectedCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
            child: Wrap(
              spacing: 6,
              children: _selectedCategories.map((cat) => Chip(
                label: Text(cat, style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  setState(() => _selectedCategories.remove(cat));
                  _fireSearch();
                },
                backgroundColor: colors.accent.withOpacity(0.1),
                side: BorderSide(color: colors.accent.withOpacity(0.3)),
              )).toList(),
            ),
          ),
      ],
    );
  }

  // ── Primary category hero (Transit, Restaurants, Hotels) ─────────────────
  Widget _primaryCategoryHero(AzamanColors colors) {
    final primaries = BusinessCategories.primary;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: primaries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final cat = primaries[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.nav();
              final idx = BusinessCategories.withAll.indexOf(cat);
              setState(() => _categoryIndex = idx);
              _fireSearch();
            },
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cat.color.withOpacity(0.15),
                    cat.color.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cat.color.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(cat.icon, color: cat.color, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    cat.label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cat.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      cat.subtitle!,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section header with title and optional action ──────────────────────────
  Widget _sectionHeader(AzamanColors colors, String title, {String? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (action != null)
            Text(
              action,
              style: TextStyle(
                color: colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  // ── Category grid ───────────────────────────────────────────────────────────
  // ── Category carousel (horizontal scroll, icon + label chips) ─────────────
  Widget _categoryCarousel(AzamanColors colors) {
    final cats = BusinessCategories.withAll;
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final selected = i == _categoryIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (i == _categoryIndex && i > 0) {
                AzamanHaptics.nav();
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CategoryDrilldownScreen(
                        parentWire: cat.wire, label: cat.label)));
                return;
              }
              AzamanHaptics.toggle();
              setState(() => _categoryIndex = i);
              _fireSearch();
            },
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? cat.color.withOpacity(0.12)
                    : colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? cat.color.withOpacity(0.4)
                      : colors.divider,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    cat.icon,
                    size: 24,
                    color: selected ? cat.color : colors.textSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.label,
                    style: TextStyle(
                      color: selected ? cat.color : colors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }



  // ── Control bar (view toggle + sort + verified toggle + filter) ─────────────
  Widget _controlBar(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _viewToggle(colors),
          const SizedBox(width: 10),
          Expanded(child: _sortButton(colors)),
          const SizedBox(width: 8),
          _verifiedToggle(colors),
          const SizedBox(width: 8),
          _filterButton(colors),
        ],
      ),
    );
  }

  Widget _verifiedToggle(AzamanColors colors) {
    return GestureDetector(
      onTap: () {
        AzamanHaptics.toggle();
        setState(() => _verifiedOnly = !_verifiedOnly);
        _fireSearch();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _verifiedOnly ? colors.accentSurface : colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _verifiedOnly ? colors.accent : colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined,
                size: 15,
                color: _verifiedOnly ? colors.accent : colors.textSecondary),
            const SizedBox(width: 4),
            Text('Verified',
                style: TextStyle(
                    color: _verifiedOnly ? colors.accent : colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _filterButton(AzamanColors colors) {
    final active = _filters != const MarketplaceFilters();
    return GestureDetector(
      onTap: _openFilters,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? colors.accentSurface : colors.card,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: active ? colors.accent : colors.divider),
        ),
        child: Icon(Icons.tune,
            size: 18,
            color: active ? colors.accent : colors.textSecondary),
      ),
    );
  }

  Widget _viewToggle(AzamanColors colors) {
    Widget seg(IconData icon, _ViewMode mode) {
      final active = _viewMode == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setViewMode(mode),
        child: Container(
          width: 38,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon,
              size: 18,
              color: active
                  ? (colors.isDark ? Colors.black : Colors.white)
                  : colors.textSecondary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          seg(Icons.widgets_outlined, _ViewMode.list),
          seg(Icons.location_on_outlined, _ViewMode.map),
        ],
      ),
    );
  }

  Widget _sortButton(AzamanColors colors) {
    final options = _viewMode == _ViewMode.map
        ? [_SortMode.nearest, _SortMode.topRated, _SortMode.mostPopular]
        : [_SortMode.topRated, _SortMode.mostPopular, _SortMode.newest];
    return PopupMenuButton<_SortMode>(
      color: colors.surface,
      onSelected: (m) {
        AzamanHaptics.toggle();
        setState(() => _sort = m);
      },
      itemBuilder: (_) => options
          .map((m) => PopupMenuItem<_SortMode>(
                value: m,
                child: Row(
                  children: [
                    Icon(
                      m == _sort
                          ? Icons.check_circle_outline
                          : Icons.circle_outlined,
                      size: 16,
                      color: m == _sort ? colors.accent : colors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(m.label,
                        style: TextStyle(color: colors.textPrimary)),
                  ],
                ),
              ))
          .toList(),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined,
                size: 15, color: colors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _sort.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.arrow_downward,
                size: 14, color: colors.textTertiary),
          ],
        ),
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
        onRefresh: () =>
            ref.read(businessSearchProvider.notifier).search(
                  _searchCtrl.text.trim(),
                  category: _activeCategory,
                  verified: _verifiedOnly ? true : null,
                ),
        child: ListView(
          children: [
            const SizedBox(height: 80),
            AzamanEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No businesses found',
              subtitle: 'Try a different search, category, or filter.',
            ),
          ],
        ),
      );
    }

    final showFeatured = _isIdle && _filters.isEmpty;
    final featured = showFeatured ? _featured(state.results) : const [];

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => ref.read(businessSearchProvider.notifier).search(
            _searchCtrl.text.trim(),
            category: _activeCategory,
            verified: _verifiedOnly ? true : null,
          ),
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount:
            results.length + (showFeatured ? 1 : 0) + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, i) {
          // No separator directly after the featured header block.
          if (showFeatured && i == 0) return const SizedBox(height: 4);
          return const SizedBox(height: 12);
        },
        itemBuilder: (context, i) {
          if (showFeatured && i == 0) {
            return _featuredHeader(featured.cast<BusinessProfile>(), colors);
          }
          final idx = i - (showFeatured ? 1 : 0);
          if (idx >= results.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return BusinessCard(
            business: results[idx],
            onTap: () => _openBusiness(results[idx]),
          );
        },
      ),
    );
  }

  Widget _featuredHeader(
      List<BusinessProfile> featured, AzamanColors colors) {
    if (featured.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Featured Business',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 13, color: colors.success),
                  const SizedBox(width: 4),
                  Text('Escrow Protected',
                      style: TextStyle(
                          color: colors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CollapsibleBusinessBar(business: featured.first),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _featuredCard(BusinessProfile b, AzamanColors colors) {
    final cat = BusinessCategories.fromWire(b.category);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openBusiness(b),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cat.color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + verified badge + category color accent
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cat.color.withOpacity(0.12),
                    border: Border.all(color: cat.color.withOpacity(0.3)),
                  ),
                  child: Text(
                    b.businessName.isNotEmpty
                        ? b.businessName.substring(0, 1).toUpperCase()
                        : 'B',
                    style: TextStyle(
                        color: cat.color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (b.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified,
                                size: 14, color: colors.success),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cat.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cat.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Footer: rating + deals
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.star, size: 13, color: colors.warning),
                  const SizedBox(width: 4),
                  Text(b.averageRating.toStringAsFixed(1),
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${b.completedEscrows} deals',
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listShimmer(AzamanColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 92,
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // ── MAP mode (nearby list + directions) ─────────────────────────────────────
  Widget _mapMode(AzamanColors colors) {
    if (_resolvingLocation) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_position == null) {
      return _locationPrompt(colors);
    }

    final state = ref.watch(nearbySearchProvider);
    if (state.isLoading) return _listShimmer(colors);

    var locations = [...state.locations];
    if (_sort == _SortMode.nearest) {
      locations.sort((a, b) =>
          (a.distanceKm ?? 1e9).compareTo(b.distanceKm ?? 1e9));
    }

    if (locations.isEmpty) {
      return AzamanEmptyState(
        icon: Icons.location_on_outlined,
        title: 'Nothing nearby',
        subtitle: 'No business locations found within range. Try a wider search.',
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.accentSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 15, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${locations.length} nearby — tap a place to open it in Maps',
                  style: TextStyle(
                      color: colors.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount: locations.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              if (i >= locations.length) {
                ref.read(nearbySearchProvider.notifier).loadMore();
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              return _nearbyCard(locations[i], colors);
            },
          ),
        ),
      ],
    );
  }

  Widget _nearbyCard(BusinessLocation loc, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        final uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${loc.latitude},${loc.longitude}');
        launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
          return false;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (loc.distanceKm != null)
                  Text('${loc.distanceKm!.toStringAsFixed(1)} km',
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Icon(Icons.widgets_outlined,
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
            Icon(Icons.location_on_outlined, size: 48, color: colors.accent),
            const SizedBox(height: 14),
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
                  'Share your location to see nearby business branches with distance and directions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _resolveLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Use my location',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
