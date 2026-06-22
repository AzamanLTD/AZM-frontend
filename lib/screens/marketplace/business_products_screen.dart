// =============================================================================
// BUSINESS PRODUCTS SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Full product catalogue for a business as a 2-column grid with infinite
// scroll. Tapping a product's Order button opens the TicketCreateSheet in
// business mode with the product (and its business) preselected.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/product_card.dart';

class BusinessProductsScreen extends ConsumerStatefulWidget {
  final String bizId;
  final String? businessName;

  const BusinessProductsScreen({
    super.key,
    required this.bizId,
    this.businessName,
  });

  @override
  ConsumerState<BusinessProductsScreen> createState() =>
      _BusinessProductsScreenState();
}

class _BusinessProductsScreenState
    extends ConsumerState<BusinessProductsScreen> {
  final _service = BusinessService();
  final _scrollCtrl = ScrollController();

  final List<BusinessProduct> _products = [];
  BusinessProfile? _business;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _service.getBusinessByBizId(widget.bizId).then((b) {
      if (mounted) setState(() => _business = b);
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final page = await _service.getBusinessProducts(widget.bizId);
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(page.products);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await _service.getBusinessProducts(widget.bizId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _products.addAll(page.products);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _order(BusinessProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TicketCreateSheet(
        preselectedBusiness: _business,
        preselectedProduct: product,
      ),
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
          widget.businessName ?? 'Products',
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? _shimmerGrid(colors)
          : _products.isEmpty
              ? AzamanEmptyState(
                  icon: HugeIconsSolid.shoppingBag01,
                  title: 'No products yet',
                  subtitle: 'This business hasn\'t listed any products.',
                )
              : GridView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: _products.length,
                  itemBuilder: (_, i) => ProductCard(
                    product: _products[i],
                    onOrder: _order,
                  ),
                ),
    );
  }

  Widget _shimmerGrid(AzamanColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
