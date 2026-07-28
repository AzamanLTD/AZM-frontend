// =============================================================================
// Storefront Discovery Screen
//
// Browse businesses with published SDUI storefronts. Customers can search,
// filter by category, and tap a storefront card to view the full storefront.
//
// Part of Phase 2: Storefront Discovery + Web Presence.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../storefront/providers/storefront_provider.dart';
import '../storefront/services/storefront_tracking_service.dart';
import '../providers/theme_provider.dart';
import 'storefront_screen.dart';

class StorefrontDiscoveryScreen extends ConsumerStatefulWidget {
  const StorefrontDiscoveryScreen({super.key});

  @override
  ConsumerState<StorefrontDiscoveryScreen> createState() => _StorefrontDiscoveryScreenState();
}

class _StorefrontDiscoveryScreenState extends ConsumerState<StorefrontDiscoveryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _search;
  String? _category;
  int _offset = 0;
  final int _limit = 20;
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _allResults = [];
  bool _hasMore = true;
  bool _isLoadingMore = false;

  static const _categories = [
    {'label': 'All', 'value': null},
    {'label': 'Food & Beverage', 'value': 'FOOD_BEVERAGE'},
    {'label': 'Retail', 'value': 'RETAIL'},
    {'label': 'Hospitality', 'value': 'HOSPITALITY'},
    {'label': 'Health & Beauty', 'value': 'HEALTH_BEAUTY'},
    {'label': 'Services', 'value': 'SERVICES'},
    {'label': 'Logistics', 'value': 'LOGISTICS'},
    {'label': 'Other', 'value': 'OTHER'},
  ];

  void _doSearch() {
    setState(() {
      _search = _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim();
      _offset = 0;
      _allResults = [];
      _hasMore = true;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final service = ref.read(storefrontServiceProvider);
      final newResults = await service.discoverStorefronts(
        query: _search,
        category: _category,
        limit: _limit,
        offset: _offset + _limit,
      );
      setState(() {
        _allResults.addAll(newResults);
        _offset += _limit;
        _hasMore = newResults.length == _limit;
        _isLoadingMore = false;
      });
    } catch (_) {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final query = StorefrontDiscoveryQuery(
      search: _search,
      category: _category,
      limit: _limit,
      offset: 0,
    );
    final asyncResults = ref.watch(storefrontDiscoveryProvider(query));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Discover Storefronts', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.receipt_long_rounded, color: colors.textPrimary),
            onPressed: () => context.pushNamed('storefront-order-history'),
            tooltip: 'My Orders',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _doSearch(),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search businesses...',
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: colors.textSecondary, size: 20),
                suffixIcon: _search != null
                    ? IconButton(
                        icon: Icon(Icons.close, color: colors.textSecondary, size: 18),
                        onPressed: () { _searchCtrl.clear(); _doSearch(); },
                      )
                    : null,
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final isSelected = _category == cat['value'];
                return FilterChip(
                  label: Text(cat['label']!),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _category = isSelected ? null : cat['value'] as String?;
                      _offset = 0;
                      _allResults = [];
                      _hasMore = true;
                    });
                  },
                  selectedColor: colors.accent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : colors.textSecondary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  backgroundColor: colors.surface,
                  side: BorderSide(color: colors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                );
              },
            ),
          ),

          // Results
          Expanded(
            child: asyncResults.when(
              loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: colors.textSecondary),
                      const SizedBox(height: 16),
                      Text('Could not load storefronts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      const SizedBox(height: 8),
                      Text(err.toString(), style: TextStyle(fontSize: 13, color: colors.textSecondary), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              data: (results) {
                // Merge initial page with loaded pages
                final display = _offset == 0 ? results : _allResults;
                if (display.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront_outlined, size: 48, color: colors.textSecondary),
                          const SizedBox(height: 16),
                          Text('No storefronts found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                          const SizedBox(height: 8),
                          Text('Try a different search or category filter.', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: display.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= display.length) {
                      return Center(child: Padding(padding: const EdgeInsets.all(16), child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2)));
                    }
                    return _StorefrontCard(
                      data: display[i],
                      colors: colors,
                      onTap: () {
                        final bizId = display[i]['businessProfileId'] as String;
                        final bizName = (display[i]['business'] as Map<String, dynamic>?)?['businessName'] as String?;
                        // Track discovery tap
                        StorefrontTrackingService.instance.trackEvent(bizId, 'storefront_view', {'source': 'discovery'});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StorefrontScreen(
                              businessProfileId: bizId,
                              businessName: bizName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StorefrontCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _StorefrontCard({required this.data, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final business = data['business'] as Map<String, dynamic>? ?? {};
    final theme = data['theme'] as Map<String, dynamic>? ?? {};
    final name = business['businessName'] as String? ?? 'Unknown';
    final category = business['category'] as String? ?? '';
    final logoUrl = business['logoUrl'] as String?;
    final coverUrl = business['coverPhotoUrl'] as String?;
    final rating = business['averageRating'] != null ? (business['averageRating'] as num).toDouble() : null;
    final reviewCount = business['reviewCount'] as int? ?? 0;
    final description = business['description'] as String?;
    final tileCount = data['tileCount'] as int? ?? 0;
    final accent = theme['accent'] as String? ?? 
        '#${colors.accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image or accent gradient
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: coverUrl != null
                    ? Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _CoverFallback(accent: accent))
                    : _CoverFallback(accent: accent),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.divider),
                      color: colors.background,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: logoUrl != null
                          ? Image.network(logoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.store, color: colors.textSecondary, size: 24))
                          : Icon(Icons.store, color: colors.textSecondary, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (rating != null && rating > 0) ...[
                              Icon(Icons.star, size: 14, color: Colors.amber[600]),
                              const SizedBox(width: 2),
                              Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                              const SizedBox(width: 4),
                              Text('($reviewCount)', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                              const SizedBox(width: 8),
                            ],
                            Text(_categoryLabel(category), style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                          ],
                        ),
                        if (description != null && description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(description!, style: TextStyle(fontSize: 12, color: colors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),

                  // Tile count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$tileCount widgets',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'FOOD_BEVERAGE': return 'Food & Beverage';
      case 'RETAIL': return 'Retail';
      case 'HOSPITALITY': return 'Hospitality';
      case 'HEALTH_BEAUTY': return 'Health & Beauty';
      case 'SERVICES': return 'Services';
      case 'LOGISTICS': return 'Logistics';
      case 'REAL_ESTATE': return 'Real Estate';
      default: return 'Business';
    }
  }
}

class _CoverFallback extends StatelessWidget {
  final String accent;
  const _CoverFallback({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(int.parse('0xFF${accent.replaceAll('#', '')}')).withOpacity(0.3),
            Color(int.parse('0xFF${accent.replaceAll('#', '')}')).withOpacity(0.1),
          ],
        ),
      ),
      child: Center(child: Icon(Icons.storefront, size: 36, color: Color(int.parse('0xFF${accent.replaceAll('#', '')}')))),
    );
  }
}
