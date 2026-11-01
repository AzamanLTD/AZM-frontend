// lib/widgets/marketplace/nearby_business_row.dart
// =============================================================================
// AZAMAN — NEAR YOU BUSINESS ROW (Programme G2)
//
// A distance-forward row for the Near You proximity feed. Renders EXACTLY
// the facts the nearby payload carries (the slim embedded profile: name,
// category, logo, verified) plus the server-computed distanceKm — never a
// fabricated rating, price line or "popular" badge. Tapping opens the
// business profile through the canonical route (bizId), the same surface
// the marketplace list uses.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/scale_tap.dart';

class NearbyBusinessRow extends ConsumerWidget {
  const NearbyBusinessRow({super.key, required this.location, this.onTap});

  /// A nearby payload row (with the embedded profile facts + distanceKm).
  final BusinessLocation location;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    final categoryWire = location.businessCategory;
    final categoryLabel = categoryWire == null || categoryWire.isEmpty
        ? 'Business'
        : BusinessCategories.labelFor(categoryWire);
    final categoryColor = categoryWire == null || categoryWire.isEmpty
        ? colors.textTertiary
        : BusinessCategories.fromWire(categoryWire).color;

    final distance = location.distanceKm;
    final String? distanceLabel = distance == null
        ? null
        : distance < 1
        ? '${(distance * 1000).round()} m away'
        : '${distance.toStringAsFixed(1)} km away';

    final name = location.businessName ?? location.label;

    return ScaleTap(
      key: ValueKey('nearby-row-${location.id}'),
      onTap: () {
        AzamanHaptics.nav();
        onTap?.call();
      },
      child: Semantics(
        label:
            '$name. $categoryLabel.'
            '${distanceLabel != null ? ' $distanceLabel.' : ''}'
            '${location.businessVerified == true ? ' Verified.' : ''}',
        button: true,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              // Circular avatar: the real logo when the payload carries
              // one; the category glyph otherwise (an honest fallback, not
              // a fabricated logo).
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: (location.businessLogoUrl ?? '').isEmpty
                    ? Icon(
                        _glyphFor(categoryWire),
                        size: 20,
                        color: categoryColor,
                      )
                    : AzamanNetworkImage(
                        imageUrl: location.businessLogoUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (location.businessVerified == true) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: colors.accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            categoryLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: categoryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // City when the payload carries it — never a
                        // guessed location string.
                        if ((location.city ?? '').isNotEmpty)
                          Flexible(
                            child: Text(
                              location.city!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Distance is the row's trailing fact — the entire reason
              // the Near You feed exists. Server-computed, rounded the
              // way the backend rounds it (0.1 km precision).
              if (distanceLabel != null)
                Text(
                  distanceLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _glyphFor(String? wire) {
    switch (wire?.trim().toUpperCase()) {
      case 'FOOD_BEVERAGE':
        return Icons.restaurant_rounded;
      case 'RETAIL':
        return Icons.shopping_bag_rounded;
      case 'LOGISTICS':
        return Icons.directions_bus_rounded;
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return Icons.apartment_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }
}
