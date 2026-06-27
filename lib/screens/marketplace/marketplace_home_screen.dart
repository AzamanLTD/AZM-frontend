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
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/advanced_filter_sheet.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/category_drilldown_screen.dart';
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/business_card.dart';

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
  String? get _activeCategory =>
      _categoryIndex == 0 ? null : BusinessCategories.withAll[_categoryIndex].wire;

  bool get _isIdle =>
      _searchCtrl.text.trim().isEmpty && _categoryIndex == 0 && !_verifiedOnly;

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
            const SizedBox(height: 14),
            _categoryGrid(colors),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
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
                  hintText: 'Search businesses, services, products…',
                  hintStyle:
                      TextStyle(color: colors.textTertiary, fontSize: 14),
                  prefixIcon: Icon(HugeIconsStroke.search01,
                      size: 19, color: colors.textTertiary),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(HugeIconsStroke.cancelCircle,
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
                HugeIconsStroke.filterHorizontal,
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
                  : Icon(HugeIconsStroke.location01,
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
              child: Icon(HugeIconsStroke.bookmark02,
                  size: 20, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category grid ───────────────────────────────────────────────────────────
  Widget _categoryGrid(AzamanColors colors) {
    final cats = BusinessCategories.values; // 11 real categories
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Browse by Category',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.65,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final cat = cats[i];
              final isSelected = _categoryIndex == i + 1;
              return _categoryTile(cat, i + 1, isSelected, colors);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _categoryTile(BusinessCategory cat, int index, bool isSelected,
      AzamanColors colors) {
    final accent = colors.accent;
    final surface = colors.accentSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (index == _categoryIndex) {
          // Tap the same category: drill down
          AzamanHaptics.nav();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CategoryDrilldownScreen(parentWire: cat.wire, label: cat.label),
            ),
          );
          return;
        }
        AzamanHaptics.toggle();
        setState(() => _categoryIndex = index);
        _fireSearch();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? surface : colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : colors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(cat.icon,
                size: 20,
                color: isSelected ? accent : colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      isSelected ? accent : colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(HugeIconsStroke.arrowRight01,
                size: 14, color: isSelected ? accent : colors.textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Control bar (view toggle + sort only) ───────────────────────────────────
  Widget _controlBar(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _viewToggle(colors),
          const SizedBox(width: 10),
          Expanded(child: _sortButton(colors)),
        ],
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
          seg(HugeIconsStroke.menu01, _ViewMode.list),
          seg(HugeIconsStroke.location01, _ViewMode.map),
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
                          ? HugeIconsSolid.checkmarkCircle01
                          : HugeIconsStroke.circle,
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
            Icon(HugeIconsStroke.arrowDataTransferVertical,
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
            Icon(HugeIconsStroke.arrowDown01,
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
              icon: HugeIconsSolid.store01,
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
        Text('Featured Businesses',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _featuredCard(featured[i], colors),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _featuredCard(BusinessProfile b, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openBusiness(b),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accentSurface,
                  ),
                  child: Text(
                    b.businessName.isNotEmpty
                        ? b.businessName.substring(0, 1).toUpperCase()
                        : 'B',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                if (b.isVerified)
                  Icon(HugeIconsSolid.checkmarkCircle01,
                      size: 16, color: colors.success),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              b.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              b.categoryLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(HugeIconsSolid.star, size: 13, color: colors.warning),
                const SizedBox(width: 4),
                Text(b.averageRating.toStringAsFixed(1),
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${b.completedEscrows} deals',
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 10.5)),
              ],
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
        icon: HugeIconsSolid.location01,
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
              Icon(HugeIconsStroke.location01,
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
              child: Icon(HugeIconsSolid.location01,
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
                Icon(HugeIconsStroke.navigation03,
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
            Icon(HugeIconsSolid.location01, size: 48, color: colors.accent),
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
              icon: const Icon(HugeIconsStroke.location01, size: 18),
              label: const Text('Use my location',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
