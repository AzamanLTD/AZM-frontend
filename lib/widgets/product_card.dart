// =============================================================================
// PRODUCT CARD — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Two layouts:
//   • horizontal (160px wide) — used in the "Products & Services" carousel.
//   • full-width — used in the products grid (GridView, 2 columns).
//
// Photos load via CachedNetworkImage with a graceful grey placeholder /
// error fallback so scrolling a grid doesn't re-fetch Cloudinary URLs.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class ProductCard extends ConsumerWidget {
  final BusinessProduct product;
  final ValueChanged<BusinessProduct> onOrder;
  final bool isHorizontal;

  const ProductCard({
    super.key,
    required this.product,
    required this.onOrder,
    this.isHorizontal = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final onAccent = colors.isDark ? Colors.black : Colors.white;

    final card = Container(
      width: isHorizontal ? 160 : null,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: isHorizontal ? 1.4 : 1.5,
            child: _image(colors),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${product.priceUsdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (product.estimatedDelivery != null &&
                    product.estimatedDelivery!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(HugeIconsStroke.clock01,
                          size: 11, color: colors.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          product.estimatedDelivery!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () {
                      AzamanHaptics.confirm();
                      onOrder(product);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: onAccent,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Order',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return card;
  }

  Widget _image(AzamanColors colors) {
    final url = product.primaryImage;
    if (url == null || url.isEmpty) return _placeholder(colors);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => _placeholder(colors),
      errorWidget: (_, __, ___) => _placeholder(colors),
    );
  }

  Widget _placeholder(AzamanColors colors) {
    return Container(
      color: colors.softSurface,
      alignment: Alignment.center,
      child: Icon(HugeIconsStroke.image01, color: colors.textTertiary, size: 28),
    );
  }
}
