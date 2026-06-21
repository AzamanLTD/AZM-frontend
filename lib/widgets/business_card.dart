// =============================================================================
// BUSINESS CARD — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Full-width card used in marketplace search results and featured lists.
// Layout: circular logo + name / bizId chip / category, a verified badge,
// the average rating stars and the completed-deals count.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/rating_stars.dart';

class BusinessCard extends ConsumerWidget {
  final BusinessProfile business;
  final VoidCallback onTap;

  const BusinessCard({
    super.key,
    required this.business,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _logo(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          business.businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (business.isVerified) ...[
                        const SizedBox(width: 5),
                        Icon(HugeIconsSolid.checkmarkCircle01,
                            size: 15, color: colors.success),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _bizIdChip(colors),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          business.categoryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      RatingStars(rating: business.averageRating, size: 14),
                      const SizedBox(width: 10),
                      Icon(HugeIconsStroke.checkmarkBadge01,
                          size: 12, color: colors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${business.completedEscrows} deals',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(HugeIconsSolid.arrowRight01,
                size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _logo(AzamanColors colors) {
    final url = business.logoUrl;
    final placeholder = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accentSurface,
      ),
      child: Text(
        business.businessName.isNotEmpty
            ? business.businessName.substring(0, 1).toUpperCase()
            : 'B',
        style: TextStyle(
          color: colors.accent,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (url == null || url.isEmpty) return placeholder;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _bizIdChip(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        business.bizId,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
