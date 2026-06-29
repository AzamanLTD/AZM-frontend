import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/business_card.dart';

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
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          _showBusinessList ? _selectedSubcategory ?? widget.label : widget.label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
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
          Expanded(
            child: _showBusinessList ? _businessList(colors) : _subcategoryGrid(colors),
          ),
        ],
      ),
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
              Icon(HugeIconsSolid.grid, size: 48, color: colors.textTertiary),
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
          return AzamanEmptyState(
            icon: HugeIconsSolid.grid,
            title: 'No subcategories',
            subtitle: 'No subcategories available for this category yet.',
          );
        }
        return GridView.builder(
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
                  colors: [colors.accent.withOpacity(0.3), colors.card],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
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
                      color: colors.accent.withOpacity(0.8),
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

    final results = state.results;
    if (results.isEmpty) {
      return AzamanEmptyState(
        icon: HugeIconsSolid.store01,
        title: 'No businesses found',
        subtitle: 'No businesses listed in this subcategory yet.',
      );
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => ref.read(businessSearchProvider.notifier).search(
            '',
            category: widget.parentWire,
            subcategory: _selectedSubcategory,
          ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: results.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i >= results.length) {
            ref.read(businessSearchProvider.notifier).loadMore();
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
            business: results[i],
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      BusinessProfileScreen(bizId: results[i].bizId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
