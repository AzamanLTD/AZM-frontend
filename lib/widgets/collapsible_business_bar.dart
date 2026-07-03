import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/rating_stars.dart';

class CollapsibleBusinessBar extends ConsumerStatefulWidget {
  final BusinessProfile business;
  final double? distanceKm;

  const CollapsibleBusinessBar({
    super.key,
    required this.business,
    this.distanceKm,
  });

  @override
  ConsumerState<CollapsibleBusinessBar> createState() => _CollapsibleBusinessBarState();
}

class _CollapsibleBusinessBarState extends ConsumerState<CollapsibleBusinessBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  void _openProfile() {
    context.push('/business-market/${widget.business.bizId}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final b = widget.business;

    String? coverUrl;
    for (final prod in b.products) {
      if (prod.imageUrls.isNotEmpty) {
        coverUrl = prod.imageUrls.first;
        break;
      }
    }
    coverUrl ??= b.logoUrl;

    if (!_expanded) {
      // COLLAPSED — thin bar
      return GestureDetector(
        onTap: _toggle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: b.logoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: b.logoUrl!,
                        width: 36, height: 36, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(width: 36, height: 36, color: colors.accent.withOpacity(0.1)),
                      )
                    : Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: colors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.store, size: 18, color: colors.accent),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.businessName, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary,
                    ), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        if (b.averageRating > 0) ...[
                          RatingStars(rating: b.averageRating, size: 12),
                          const SizedBox(width: 4),
                        ],
                        if (widget.distanceKm != null)
                          Text('${widget.distanceKm!.toStringAsFixed(1)} km',
                            style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: colors.textTertiary, size: 20),
            ],
          ),
        ),
      );
    }

    // EXPANDED — full card
    return GestureDetector(
      onTap: _openProfile,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider, width: 0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: coverUrl ?? '',
                height: 120, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 120, color: colors.accent.withOpacity(0.1)),
                errorWidget: (_, __, ___) => Container(
                  height: 120, color: colors.accent.withOpacity(0.1),
                  child: Center(child: Icon(Icons.store, size: 32, color: colors.accent)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(b.businessName, style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary,
                        )),
                      ),
                      if (b.isVerified)
                        Icon(Icons.verified, size: 16, color: colors.accent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (b.averageRating > 0) ...[
                        RatingStars(rating: b.averageRating, size: 14),
                        const SizedBox(width: 4),
                        Text('${b.averageRating.toStringAsFixed(1)}',
                          style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                        const SizedBox(width: 8),
                      ],
                      Text(b.category, style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                    ],
                  ),
                  if (widget.distanceKm != null) ...[
                    const SizedBox(height: 4),
                    Text('${widget.distanceKm!.toStringAsFixed(1)} km away',
                      style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _openProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(b.category == 'FOOD_BEVERAGE' ? 'Order Now' : 'View Details',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _toggle,
                        icon: Icon(Icons.keyboard_arrow_up, color: colors.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
