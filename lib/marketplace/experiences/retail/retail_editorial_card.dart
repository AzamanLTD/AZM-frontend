/// Editorial product card (Overhaul 03 §2.1).
///
/// Image-first, 4:5, name and price only. No star counts, no "sold N"
/// (`totalOrders` is business analytics, not shopper truth). Stock is omitted
/// because `BusinessProduct` exposes no authoritative stock field. Price is a
/// *carried* value rendered with the money face; nothing is computed here.
library;

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class RetailEditorialCard extends StatelessWidget {
  final BusinessProduct product;
  final AzamanColors colors;
  final bool saved;

  /// Quick peek (long-press). Null disables the gesture.
  final VoidCallback? onPeek;

  /// Full detail (tap).
  final VoidCallback onOpen;
  final VoidCallback? onToggleSave;

  const RetailEditorialCard({
    super.key,
    required this.product,
    required this.colors,
    required this.onOpen,
    this.onPeek,
    this.onToggleSave,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = product.primaryImage;
    return RepaintBoundary(
      child: GestureDetector(
        key: ValueKey('retail_editorial_${product.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        onLongPress: onPeek == null
            ? null
            : () {
                AzamanHaptics.selection();
                onPeek!();
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AzRadius.lg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      AzamanNetworkImage(imageUrl: image, fit: BoxFit.cover)
                    else
                      Container(
                        color: colors.softSurface,
                        alignment: Alignment.center,
                        child: Icon(HugeIconsSolid.shoppingBag01, color: colors.textTertiary),
                      ),
                    if (onToggleSave != null)
                      Positioned(
                        top: AzSpace.sm,
                        right: AzSpace.sm,
                        child: _SaveDot(saved: saved, colors: colors, onTap: onToggleSave!),
                      ),
                    if (!product.isActive)
                      Positioned.fill(
                        child: Container(
                          color: colors.background.withValues(alpha: .55),
                          alignment: Alignment.center,
                          child: Text(
                            'Unavailable',
                            style: AzText.label.copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AzSpace.sm),
            Text(
              product.name,
              style: AzText.body.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AzSpace.xxs),
            Text(
              AzMoney.usdc(product.priceUsdc),
              style: AzText.money(colors.textPrimary, size: 14, weight: FontWeight.w700, tracking: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveDot extends StatelessWidget {
  final bool saved;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SaveDot({required this.saved, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface.withValues(alpha: .9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          AzamanHaptics.toggle();
          onTap();
        },
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            saved ? HugeIconsSolid.bookmark02 : HugeIconsSolid.bookmark01,
            size: 16,
            color: saved ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}