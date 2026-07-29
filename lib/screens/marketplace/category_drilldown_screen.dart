import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_shimmer.dart';
import 'package:azaman/widgets/animated_rating_stars.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Subcategory provider — fetches subcategories for a given parent category wire
// ─────────────────────────────────────────────────────────────────────────────

final subcategoryProvider =
    FutureProvider.family<List<BusinessSubcategory>, String>(
  (ref, parentWire) async {
    final response =
        await apiClient.get('/business/subcategories?parentWire=$parentWire');
    final body = jsonDecode(response.body);
    final data = body['subcategories'] as List<dynamic>? ??
        body['data'] as List<dynamic>? ??
        [];
    return data
        .map((e) => BusinessSubcategory.fromJson(e as Map<String, dynamic>))
        .where((s) => s.isActive)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// CategoryDrilldownScreen — two-level navigation:
//   Level 1: subcategory grid for the selected parent category
//   Level 2: filtered business list for the selected subcategory
// ─────────────────────────────────────────────────────────────────────────────

class CategoryDrilldownScreen extends ConsumerStatefulWidget {
  final String parentWire;
  final String label;

  const CategoryDrilldownScreen({
    super.key,
    required this.parentWire,
    required this.label,
  });

  @override
  ConsumerState<CategoryDrilldownScreen> createState() =>
      _CategoryDrilldownScreenState();
}

class _CategoryDrilldownScreenState
    extends ConsumerState<CategoryDrilldownScreen> {
  String? _selectedSubcategory;
  bool _showBusinessList = false;

  void _selectSubcategory(BusinessSubcategory sub) {
    AzamanHaptics.nav();
    setState(() {
      _selectedSubcategory = sub.wire;
      _showBusinessList = true;
    });
    ref.read(businessSearchProvider.notifier).search(
          '',
          category: widget.parentWire,
          subcategory: sub.wire,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: RefreshIndicator(
        color: colors.accent,
        onRefresh: () async {
          if (_showBusinessList) {
            ref.read(businessSearchProvider.notifier).search(
                  '',
                  category: widget.parentWire,
                  subcategory: _selectedSubcategory,
                );
          } else {
            ref.invalidate(subcategoryProvider(widget.parentWire));
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true, expandedHeight: 120,
              backgroundColor: colors.surface, foregroundColor: colors.textPrimary,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () {
                  if (_showBusinessList) {
                    setState(() {
                      _showBusinessList = false;
                      _selectedSubcategory = null;
                    });
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(_showBusinessList ? _selectedSubcategory ?? widget.label : widget.label, 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                background: _categoryGradient(widget.parentWire, colors),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'Marketplace',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(' › ', style: TextStyle(color: colors.textTertiary, fontSize: 10)),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _showBusinessList ? _businessList(colors) : _subcategoryGrid(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryGradient(String category, AzamanColors colors) {
    final gradients = {
      'FOOD_BEVERAGE': [const Color(0xFFFF6B6B), const Color(0xFFEE5A24)],
      // Real wire value is REAL_ESTATE (hotels/guesthouses/resorts/short-stay
      // — see BusinessCategory enum). Kept the old 'HOSPITALITY' key too in
      // case any stale deep-link still passes it, but it's unreachable now.
      'REAL_ESTATE': [const Color(0xFF4834DF), const Color(0xFF6C5CE7)],
      'HOSPITALITY': [const Color(0xFF4834DF), const Color(0xFF6C5CE7)],
      'LOGISTICS': [const Color(0xFF00B894), const Color(0xFF00CEC9)],
      'RETAIL': [const Color(0xFFD4AF37), const Color(0xFFF0B90B)],
      'FREELANCE_SERVICES': [const Color(0xFF0984E3), const Color(0xFF74B9FF)],
      'SERVICE': [const Color(0xFF0984E3), const Color(0xFF74B9FF)],
      'HEALTH_WELLNESS': [const Color(0xFFFD79A8), const Color(0xFFE84393)],
    };
    final c = gradients[category] ?? [colors.accent, colors.accentSecondary];
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c)),
      child: Center(child: Icon(Icons.storefront_outlined, size: 32, color: Colors.white.withValues(alpha: 0.3))),
    );
  }

  // ── Level 1: Subcategory grid ───────────────────────────────────────────────
  Widget _subcategoryGrid(AzamanColors colors) {
    final async = ref.watch(subcategoryProvider(widget.parentWire));

    return async.when(
      loading: () => _gridShimmer(colors),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view_outlined, size: 48, color: colors.textTertiary),
              const SizedBox(height: 12),
              Text(
                'Could not load categories',
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      data: (subcategories) {
        if (subcategories.isEmpty) {
          return const AzamanEmptyState(
            icon: Icons.grid_view_outlined,
            title: 'No subcategories',
            subtitle: 'No subcategories available for this category yet.',
          );
        }
        return GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.4,
          ),
          itemCount: subcategories.length,
          itemBuilder: (_, i) =>
              _subcategoryTile(subcategories[i], colors),
        );
      },
    );
  }

  Widget _subcategoryTile(
      BusinessSubcategory sub, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectSubcategory(sub),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: sub.imageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(sub.imageUrl!),
                  fit: BoxFit.cover,
                )
              : null,
          gradient: sub.imageUrl == null
              ? LinearGradient(
                  colors: [colors.accent.withValues(alpha: 0.3), colors.card],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Colors.transparent, Colors.black54],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${sub.displayOrder} businesses',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                sub.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridShimmer(AzamanColors colors) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.4,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // ── Level 2: Filtered business list ─────────────────────────────────────────
  Widget _businessList(AzamanColors colors) {
    final state = ref.watch(businessSearchProvider);

    if (state.isLoading) {
      return GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
        itemCount: 6,
        itemBuilder: (_, __) => const PremiumShimmerBox(width: double.infinity, height: double.infinity, radius: 16),
      );
    }

    final results = state.results;
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: colors.textTertiary),
              const SizedBox(height: 12),
              Text('No businesses found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              const SizedBox(height: 8),
              Text('No businesses listed in this subcategory yet.', textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
      itemCount: results.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= results.length) {
          ref.read(businessSearchProvider.notifier).loadMore();
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final b = results[i];
        return _premiumBusinessTile(b, colors)
          .animate().fadeIn(delay: (i * 60).ms, duration: 300.ms)
          .slideY(begin: 0.15, end: 0, delay: (i * 60).ms, duration: 300.ms, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget _premiumBusinessTile(BusinessProfile b, AzamanColors colors) {
    return GestureDetector(
      onTap: () => context.push('/business/${b.bizId}'),
      child: Container(
        decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider, width: 0.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: b.logoUrl != null
                  ? CachedNetworkImage(imageUrl: b.logoUrl!, fit: BoxFit.cover, width: double.infinity,
                      placeholder: (_, __) => const PremiumShimmerBox(width: double.infinity, height: 100, radius: 0))
                  : _categoryGradient(b.category, colors),
              ),
            ),
            Expanded(flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(b.businessName, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: colors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (b.isVerified) ...[const SizedBox(width: 4), Icon(Icons.verified_rounded, size: 12, color: colors.accent)],
                    ]),
                    const SizedBox(height: 4),
                    AnimatedRatingStars(rating: b.averageRating, size: 11),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
