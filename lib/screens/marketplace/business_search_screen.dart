// lib/screens/marketplace/business_search_screen.dart
// =============================================================================
// BUSINESS SEARCH SCREEN — Marketplace Premium Upgrade (2026-06-21)
//
// Full-screen premium search experience:
//   • Autofocused search field with clear button
//   • Recent searches (SharedPreferences, max 8)
//   • Trending categories grid (when idle)
//   • Inline sort chip bar (Top Rated / Most Popular / Newest)
//   • Verified-only toggle
//   • Filter button → AdvancedFilterSheet
//   • Infinite-scroll results with premium BusinessCard (tall=true)
//   • Result count badge
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/advanced_filter_sheet.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/business_card.dart';
import 'package:azaman/widgets/nav_transitions.dart';

enum _Sort { topRated, mostPopular, newest }

extension _SortLabel on _Sort {
  String get label {
    switch (this) {
      case _Sort.topRated:
        return 'Top Rated';
      case _Sort.mostPopular:
        return 'Most Popular';
      case _Sort.newest:
        return 'Newest';
    }
  }
}

class BusinessSearchScreen extends ConsumerStatefulWidget {
  const BusinessSearchScreen({super.key});

  @override
  ConsumerState<BusinessSearchScreen> createState() =>
      _BusinessSearchScreenState();
}

class _BusinessSearchScreenState extends ConsumerState<BusinessSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  int _categoryIndex = 0;
  _Sort _sort = _Sort.topRated;
  bool _verifiedOnly = false;
  MarketplaceFilters _filters = const MarketplaceFilters();
  List<String> _recentSearches = [];
  bool _hasSearched = false;

  static const _kRecentKey = 'recent_biz_searches';
  static const _kMaxRecent = 8;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentKey) ?? [];
    if (mounted) setState(() => _recentSearches = list);
  }

  Future<void> _saveRecent(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = [query, ..._recentSearches.where((s) => s != query)]
        .take(_kMaxRecent)
        .toList();
    await prefs.setStringList(_kRecentKey, list);
    if (mounted) setState(() => _recentSearches = list);
  }

  Future<void> _clearRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentKey);
    if (mounted) setState(() => _recentSearches = []);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(businessSearchProvider.notifier).loadMore();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _hasSearched = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), _fire);
  }

  void _fire({String? override}) {
    final q = override ?? _searchCtrl.text.trim();
    if (q.isNotEmpty) _saveRecent(q);
    setState(() => _hasSearched = q.isNotEmpty);
    final cat = _categoryIndex == 0
        ? null
        : BusinessCategories.withAll[_categoryIndex].wire;
    ref.read(businessSearchProvider.notifier).search(
          q,
          category: cat,
          verified: _verifiedOnly ? true : null,
        );
  }

  void _pickCategory(int i) {
    AzamanHaptics.toggle();
    setState(() {
      _categoryIndex = i;
      _hasSearched = true;
    });
    _fire();
  }

  void _pickRecent(String q) {
    _searchCtrl.text = q;
    _searchCtrl.selection = TextSelection.collapsed(offset: q.length);
    _fire(override: q);
    _focusNode.unfocus();
  }

  Future<void> _openFilters() async {
    final result = await AdvancedFilterSheet.show(context, _filters);
    if (result == null) return;
    setState(() => _filters = result);
    _fire();
  }

  List<BusinessProfile> _sorted(List<BusinessProfile> input) {
    final list = input.where((b) {
      if (_filters.minRating > 0 && b.averageRating < _filters.minRating) {
        return false;
      }
      if ((_filters.verifiedOnly || _verifiedOnly) && !b.isVerified) {
        return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.topRated:
        list.sort((a, b) => b.averageRating.compareTo(a.averageRating));
        break;
      case _Sort.mostPopular:
        list.sort((a, b) => b.totalEscrows.compareTo(a.totalEscrows));
        break;
      case _Sort.newest:
        break; // keep server order
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(businessSearchProvider);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchBar(colors),
            _controlRow(colors),
            Expanded(
              child: _hasSearched
                  ? _results(state, colors)
                  : _idleState(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 22),
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: _onQueryChanged,
                onSubmitted: (v) => _fire(override: v),
                textInputAction: TextInputAction.search,
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search businesses, services, products…',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.textTertiary),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _hasSearched = false);
                          },
                          child: Icon(Icons.cancel_outlined, size: 18, color: colors.textTertiary),
                        )
                      : null,
                  filled: true,
                  fillColor: colors.card,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlRow(AzamanColors colors) {
    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          // Sort chips
          for (final s in _Sort.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  AzamanHaptics.toggle();
                  setState(() => _sort = s);
                  if (_hasSearched) _fire();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _sort == s ? colors.accent : colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _sort == s ? colors.accent : colors.divider,
                    ),
                  ),
                  child: Text(
                    s.label,
                    style: TextStyle(
                      color: _sort == s
                          ? (colors.isDark ? Colors.black : Colors.white)
                          : colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          // Verified toggle
          GestureDetector(
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _verifiedOnly = !_verifiedOnly);
              if (_hasSearched) _fire();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _verifiedOnly ? colors.success : colors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _verifiedOnly ? colors.success : colors.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 13,
                    color: _verifiedOnly
                        ? (colors.isDark ? Colors.black : Colors.white)
                        : colors.textTertiary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Verified',
                    style: TextStyle(
                      color: _verifiedOnly
                          ? (colors.isDark ? Colors.black : Colors.white)
                          : colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Filter button
          GestureDetector(
            onTap: _openFilters,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: !_filters.isEmpty ? colors.accentSurface : colors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: !_filters.isEmpty ? colors.accent : colors.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list,
                      size: 13,
                      color: !_filters.isEmpty ? colors.accent : colors.textTertiary),
                  const SizedBox(width: 5),
                  Text(
                    'Filters${!_filters.isEmpty ? " •" : ""}',
                    style: TextStyle(
                      color: !_filters.isEmpty ? colors.accent : colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  // ── Idle state (recent searches + trending categories) ────────────────────
  Widget _idleState(AzamanColors colors) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          _sectionHeader(colors, 'Recent Searches', onClear: _clearRecents),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches.map((q) {
              return GestureDetector(
                onTap: () => _pickRecent(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 13, color: colors.textTertiary),
                      const SizedBox(width: 6),
                      Text(q,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
        _sectionHeader(colors, 'Browse Categories'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: BusinessCategories.values.length,
          itemBuilder: (_, i) {
            final cat = BusinessCategories.values[i];
            return GestureDetector(
              onTap: () {
                _searchCtrl.text = cat.label;
                _pickCategory(i + 1); // +1 because index 0 is "All"
              },
              child: Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(cat.icon, size: 28, color: colors.accent),
                    const SizedBox(height: 6),
                    Text(
                      cat.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _sectionHeader(AzamanColors colors, String title, {VoidCallback? onClear}) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        if (onClear != null)
          GestureDetector(
            onTap: onClear,
            child: Text(
              'Clear',
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // ── Results list ──────────────────────────────────────────────────────────
  Widget _results(BusinessSearchState state, AzamanColors colors) {
    if (state.isLoading && state.results.isEmpty) return _shimmer(colors);
    final sorted = _sorted(state.results);
    if (sorted.isEmpty && !state.isLoading) {
      return const AzamanEmptyState(
        icon: Icons.storefront_outlined,
        title: 'No businesses found',
        subtitle: 'Try adjusting your search or filters.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sorted.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '${sorted.length}${state.hasMore ? '+' : ''} results',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: sorted.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              if (i >= sorted.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final biz = sorted[i];
              return BusinessCard(
                business: biz,
                tall: true,
                onTap: () => pushWithVerticalTransition(context, BusinessProfileScreen(bizId: biz.bizId)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _shimmer(AzamanColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => Container(
        height: 240,
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
