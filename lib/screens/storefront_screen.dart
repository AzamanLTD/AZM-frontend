// =============================================================================
// Storefront Screen — Customer-facing
//
// Displays a business's published storefront to customers using the SDUI
// renderer. Fires storefront_view on load and wraps all widgets with
// visibility + interaction tracking.
//
// Phase 4: Now includes a "Browse & Order" section below the SDUI storefront
// that shows the business's product catalog with direct ordering via the
// existing TicketCreateSheet escrow flow.
//
// Used from:
//   - Marketplace search results → tap business → storefront tab
//   - Deep links → /storefront/:businessProfileId
//   - QR code scan → storefront
//   - Storefront Discovery screen → tap a card
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../storefront/providers/storefront_provider.dart';
import '../storefront/core/storefront_renderer.dart';
import '../storefront/services/storefront_tracking_service.dart';
import 'storefront_order_sheet.dart';
import '../storefront/core/scroll_to_products_notification.dart';
import '../storefront/widgets/storefront_skeleton.dart';
import '../providers/theme_provider.dart';

class StorefrontScreen extends ConsumerStatefulWidget {
  final String businessProfileId;
  final String? businessName;

  const StorefrontScreen({
    super.key,
    required this.businessProfileId,
    this.businessName,
  });

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  bool _viewTracked = false;
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _productsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Fire storefront_view event on screen load (fire-and-forget)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_viewTracked) {
        StorefrontTrackingService.instance.trackEvent(
          widget.businessProfileId,
          'storefront_view',
          {'source': 'flutter_app'},
        );
        _viewTracked = true;
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _shareStorefront() {
    StorefrontTrackingService.instance.trackEvent(
      widget.businessProfileId,
      'share_click',
      {'widgetType': 'app_bar'},
    );
    final shareUrl = 'https://azaman.app/storefront/${widget.businessProfileId}';
    Share.share(
      'Check out ${widget.businessName ?? 'this business'} on AZAMAN! $shareUrl',
      subject: '${widget.businessName ?? 'Storefront'} on AZAMAN',
    );
  }

  Future<void> _openOrderSheet(Map<String, dynamic> product) async {
    StorefrontTrackingService.instance.trackEvent(
      widget.businessProfileId,
      'cta_click',
      {'ctaType': 'order', 'productId': product['id']},
    );
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StorefrontOrderSheet(
        businessProfileId: widget.businessProfileId,
        businessName: widget.businessName ?? 'Business',
        product: product,
      ),
    );
    if (result != null && mounted) {
      final order = result['order'] as Map<String, dynamic>?;
      final orderRef = order?['orderRef'] as String? ?? 'N/A';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Order Placed!')]),
          content: Text('Your order has been placed successfully.\n\nOrder Ref: $orderRef\n\nThe business will be notified and your order is now awaiting payment.',
            style: const TextStyle(fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final renderAsync = ref.watch(storefrontRenderProvider(widget.businessProfileId));
    final productsAsync = ref.watch(storefrontProductsProvider(widget.businessProfileId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          widget.businessName ?? 'Storefront',
          style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: colors.textSecondary),
            onPressed: _shareStorefront,
          ),
        ],
      ),
      body: renderAsync.when(
        loading: () => const StorefrontSkeleton(),
        error: (err, stack) => _ErrorState(
          error: err.toString(),
          onRetry: () => ref.invalidate(storefrontRenderProvider(widget.businessProfileId)),
          colors: colors,
        ),
        data: (response) {
          if (response == null) {
            return _NoStorefrontState(colors: colors);
          }

          // Build the SDUI storefront + products section
          return RefreshIndicator(
            color: colors.accent,
            onRefresh: () async {
              ref.invalidate(storefrontRenderProvider(widget.businessProfileId));
              ref.invalidate(storefrontProductsProvider(widget.businessProfileId));
              await ref.read(storefrontRenderProvider(widget.businessProfileId).future);
            },
            child: NotificationListener<ScrollToProductsNotification>(
            onNotification: (_) {
              final ctx = _productsKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic, alignment: 0.0);
              }
              return true;
            },
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
              // SDUI Storefront widgets
              SliverToBoxAdapter(
                child: StorefrontRenderer(
                  response: response,
                  businessProfileId: widget.businessProfileId,
                ),
              ),

              // "Browse & Order" section (Phase 4)
              SliverToBoxAdapter(
                key: _productsKey,
                child: _ProductsSection(
                  productsAsync: productsAsync,
                  colors: colors,
                  onOrder: (product) {
                    // Build a minimal BusinessProfile from the render response
                    final biz = BusinessProfile(
                      id: widget.businessProfileId,
                      bizId: '',
                      userId: 0,
                      businessName: response.business?.name ?? widget.businessName ?? 'Business',
                      category: response.business?.category ?? 'OTHER',
                      description: null,
                      logoUrl: response.business?.logoUrl,
                      coverPhotoUrl: response.business?.coverPhotoUrl,
                      isVerified: false,
                      averageRating: response.business?.averageRating ?? 0.0,
                      reviewCount: 0,
                    );
                    _openOrderSheet(business: biz, product: product);
                  },
                  onTrackProductTap: (productId) {
                    StorefrontTrackingService.instance.trackEvent(
                      widget.businessProfileId,
                      'product_tap',
                      {'productId': productId},
                    );
                  },
                ),
              ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}

// ── Products Section (Phase 4) ────────────────────────────────────────────────

class _ProductsSection extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> productsAsync;
  final AzamanColors colors;
  final void Function(Map<String, dynamic> product) onOrder;
  final void Function(String productId) onTrackProductTap;

  const _ProductsSection({
    required this.productsAsync,
    required this.colors,
    required this.onOrder,
    required this.onTrackProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return productsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(), // Silently hide on error — storefront still works
      data: (data) {
        final products = (data['products'] as List?) ?? [];
        if (products.isEmpty) return const SizedBox.shrink();

        final businessName = (data['business'] as Map<String, dynamic>?)?['name'] as String?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section divider
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 20, color: colors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Browse & Order',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    '${products.length} items',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Tap a product to order directly from $businessName',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),

            // Product grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: products.length,
              itemBuilder: (ctx, i) {
                final p = products[i] as Map<String, dynamic>;
                return _ProductCard(
                  data: p,
                  colors: colors,
                  onTap: () {
                    onTrackProductTap(p['id'] as String);
                    onOrder(p);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _ProductCard({required this.data, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Product';
    final description = data['description'] as String?;
    final price = (data['priceUsdc'] as num?)?.toDouble() ?? 0.0;
    final imageUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final tags = (data['tags'] as List?)?.cast<String>() ?? [];
    final prepMins = data['preparationMins'] as int?;
    final imageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 1.2,
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _ProductImageFallback(colors: colors))
                    : _ProductImageFallback(colors: colors),
              ),
            ),

            // Product info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description, style: TextStyle(fontSize: 11, color: colors.textSecondary),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const Spacer(),
                    // Tags row
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: tags.take(2).map((tag) => _TagChip(tag: tag, colors: colors)).toList(),
                      ),
                    const SizedBox(height: 4),
                    // Price + Order button
                    Row(
                      children: [
                        Text(
                          '\$${price.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.accent),
                        ),
                        if (prepMins != null) ...[
                          const SizedBox(width: 6),
                          Text('~${prepMins}min', style: TextStyle(fontSize: 10, color: colors.textSecondary)),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Order', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ],
                    ),
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

class _TagChip extends StatelessWidget {
  final String tag;
  final AzamanColors colors;

  const _TagChip({required this.tag, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: colors.accent),
      ),
    );
  }
}

class _ProductImageFallback extends StatelessWidget {
  final AzamanColors colors;
  const _ProductImageFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.background,
      child: Center(child: Icon(Icons.inventory_2_outlined, size: 32, color: colors.textSecondary)),
    );
  }
}

// ── Error / Empty States ───────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AzamanColors colors;

  const _ErrorState({required this.error, required this.onRetry, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text('Could not load storefront', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(fontSize: 13, color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, style: ElevatedButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _NoStorefrontState extends StatelessWidget {
  final AzamanColors colors;

  const _NoStorefrontState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text('No storefront published yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text('This business hasn\'t published their storefront. Check back later!', style: TextStyle(fontSize: 13, color: colors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
