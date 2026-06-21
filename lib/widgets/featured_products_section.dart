// =============================================================================
// FEATURED PRODUCTS SECTION — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Loads up to 6 products for a business and renders them as a horizontal
// "Products & Services" carousel of ProductCard(isHorizontal: true). Shows
// shimmer placeholders while loading and collapses to nothing when the
// business has no products.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/product_card.dart';

class FeaturedProductsSection extends ConsumerStatefulWidget {
  final String bizId;
  final ValueChanged<BusinessProduct>? onOrder;

  const FeaturedProductsSection({
    super.key,
    required this.bizId,
    this.onOrder,
  });

  @override
  ConsumerState<FeaturedProductsSection> createState() =>
      _FeaturedProductsSectionState();
}

class _FeaturedProductsSectionState
    extends ConsumerState<FeaturedProductsSection> {
  bool _loading = true;
  List<BusinessProduct> _products = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page =
          await BusinessService().getBusinessProducts(widget.bizId, limit: 6);
      if (!mounted) return;
      setState(() {
        _products = page.products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (_loading) return _shimmerRow(colors);
    if (_products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Products & Services',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: _products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => ProductCard(
              product: _products[i],
              isHorizontal: true,
              onOrder: (p) => widget.onOrder?.call(p),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shimmerRow(AzamanColors colors) {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 160,
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
