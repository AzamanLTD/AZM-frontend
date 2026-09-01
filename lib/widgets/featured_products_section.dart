// =============================================================================
// FEATURED PRODUCTS SECTION — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Loads up to 6 products for a business and presents a premium horizontal
// "peek" carousel: one dominant product with the next item partially visible.
// Products are ordered by totalOrders so the preview surfaces genuine popular
// items rather than inventing a separate recommendation source.
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
  final String title;
  final Future<ProductPage> Function(String bizId)? productLoader;

  const FeaturedProductsSection({
    super.key,
    required this.bizId,
    this.onOrder,
    this.title = 'Popular picks',
    this.productLoader,
  });

  @override
  ConsumerState<FeaturedProductsSection> createState() =>
      _FeaturedProductsSectionState();
}

class _FeaturedProductsSectionState
    extends ConsumerState<FeaturedProductsSection> {
  bool _loading = true;
  List<BusinessProduct> _products = const [];
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.78);
    _load();
  }

  Future<void> _load() async {
    try {
      final page = widget.productLoader != null
          ? await widget.productLoader!(widget.bizId)
          : await BusinessService().getBusinessProducts(widget.bizId, limit: 6);
      if (!mounted) return;
      final products = [...page.products]
        ..sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
      setState(() {
        _products = products.take(6).toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _previous() {
    if (_page <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_page >= _products.length - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_products.length > 1) ...[
                _arrowButton(
                  icon: Icons.chevron_left_rounded,
                  enabled: _page > 0,
                  onTap: _previous,
                  colors: colors,
                ),
                const SizedBox(width: 6),
                _arrowButton(
                  icon: Icons.chevron_right_rounded,
                  enabled: _page < _products.length - 1,
                  onTap: _next,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: PageView.builder(
            controller: _pageController,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemCount: _products.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  var scale = 1.0;
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions) {
                    final page = _pageController.page ?? _page.toDouble();
                    final distance = (page - index).abs().clamp(0.0, 1.0);
                    scale = 1.0 - (distance * 0.05);
                  }
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: index == 0 ? 16 : 6,
                          right: index == _products.length - 1 ? 16 : 6,
                        ),
                        child: ProductCard(
                          product: _products[index],
                          isHorizontal: true,
                          onOrder: (p) => widget.onOrder?.call(p),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_products.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _products.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == _page ? 18 : 6,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == _page ? colors.accent : colors.divider,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _arrowButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required AzamanColors colors,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        maximumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
        backgroundColor: colors.card,
        foregroundColor:
            enabled ? colors.textPrimary : colors.textTertiary.withValues(alpha: 0.4),
        side: BorderSide(color: colors.divider, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
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
