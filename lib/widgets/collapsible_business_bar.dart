// lib/widgets/collapsible_business_bar.dart
// =============================================================================
// AZAMAN — COLLAPSIBLE BUSINESS BAR (Marketplace Redesign, 2026-07-04)
//
// Three-level interaction pattern (Bolt Food model):
//   Collapsed → Expanded → Full profile page
//
// The parent controls isExpanded to enforce accordion behavior (only one
// bar expanded at a time). Usage pattern:
//
//   CollapsibleBusinessBar(
//     key: ValueKey(b.bizId),
//     business: b,
//     isExpanded: _expandedBizId == b.bizId,
//     onToggle: () => setState(() {
//       _expandedBizId = _expandedBizId == b.bizId ? null : b.bizId;
//     }),
//   )
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class CollapsibleBusinessBar extends ConsumerWidget {
  final BusinessProfile business;
  final bool isExpanded;
  final VoidCallback onToggle;
  final double? distanceKm;

  const CollapsibleBusinessBar({
    super.key,
    required this.business,
    required this.isExpanded,
    required this.onToggle,
    this.distanceKm,
  });

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openProfile(BuildContext context) {
    AzamanHaptics.nav();
    context.push('/business/${business.bizId}');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Returns the first usable image URL for the cover (logo → first product image).
  String? _coverUrl() {
    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return business.logoUrl;
    }
    for (final prod in business.products) {
      if (prod.imageUrls.isNotEmpty) return prod.imageUrls.first;
    }
    return null;
  }

  /// CTA button label tailored to the business vertical.
  String _ctaLabel() {
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        return 'View Menu';
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return 'See Rooms';
      case 'LOGISTICS':
        return 'Book a Seat';
      default:
        return 'View Business';
    }
  }

  /// One-line vertical-specific stat shown in the expanded preview.
  /// Returns null when no useful data is available at the list level.
  String? _verticalStat() {
    final products = business.products;
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        if (products.isNotEmpty) {
          return '${products.length} item${products.length == 1 ? '' : 's'} on the menu';
        }
        return 'Tap to browse the menu';
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return 'Tap to see available rooms & pricing';
      case 'LOGISTICS':
        return 'Tap to view scheduled trips & seats';
      default:
        if (products.isNotEmpty) {
          return '${products.length} product${products.length == 1 ? '' : 's'} available';
        }
        return null;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final cat = BusinessCategories.fromWire(business.category);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: isExpanded
          ? _expandedCard(context, colors, cat)
          : _collapsedBar(context, colors, cat),
    );
  }

  // ── Collapsed bar ────────────────────────────────────────────────────────────
  //
  // Layout: [Logo 42px] | [Name / category dot + label + rating + distance] | [↓]
  // Height: ~68px — slim, scannable, no buttons.

  Widget _collapsedBar(
      BuildContext context, AzamanColors colors, BusinessCategory cat) {
    return GestureDetector(
      onTap: () {
        AzamanHaptics.toggle();
        onToggle();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            // Logo / icon
            _logo(colors, cat, size: 42),
            const SizedBox(width: 12),
            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          business.businessName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (business.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded,
                            size: 13, color: colors.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Vertical color dot
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: cat.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // Rating
                      if (business.averageRating > 0) ...[
                        Container(
                          margin:
                              const EdgeInsets.symmetric(horizontal: 6),
                          width: 2,
                          height: 2,
                          decoration: BoxDecoration(
                            color: colors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(Icons.star_rounded,
                            size: 11,
                            color: const Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          business.averageRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      // Distance
                      if (distanceKm != null) ...[
                        Container(
                          margin:
                              const EdgeInsets.symmetric(horizontal: 6),
                          width: 2,
                          height: 2,
                          decoration: BoxDecoration(
                            color: colors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          '${distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Chevron
            Icon(Icons.keyboard_arrow_down_rounded,
                color: colors.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }

  // ── Expanded card ────────────────────────────────────────────────────────────
  //
  // Layout (top→bottom):
  //   Cover photo 150px (with collapse button + name overlay at bottom)
  //   Category dot · label · ★ rating · n reviews
  //   Vertical-specific stat line
  //   [Full-width CTA button in category color]

  Widget _expandedCard(
      BuildContext context, AzamanColors colors, BusinessCategory cat) {
    final cover = _coverUrl();
    final stat = _verticalStat();

    return GestureDetector(
      // Tapping the card body (not the button) does nothing — prevents
      // accidental navigation. Navigation only via the CTA button.
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(colors.isDark ? 0.28 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Cover photo ──────────────────────────────────────────────
            SizedBox(
              height: 155,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo or placeholder
                  if (cover != null)
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          _coverPlaceholder(colors, cat),
                      errorWidget: (_, __, ___) =>
                          _coverPlaceholder(colors, cat),
                    )
                  else
                    _coverPlaceholder(colors, cat),

                  // Bottom gradient scrim
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),

                  // Collapse button (top-right)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () {
                        AzamanHaptics.toggle();
                        onToggle();
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  // Business name + verified overlay (bottom-left)
                  Positioned(
                    left: 14,
                    right: 52,
                    bottom: 12,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.businessName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              shadows: [
                                Shadow(
                                    color: Colors.black54,
                                    blurRadius: 8)
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (business.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Details section ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category + rating row
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cat.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (business.averageRating > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.star_rounded,
                            size: 13,
                            color: const Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          business.averageRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (business.completedEscrows > 0)
                          Text(
                            '  ·  ${business.completedEscrows} reviews',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                          ),
                      ],
                    ],
                  ),

                  // Vertical-specific stat line
                  if (stat != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      stat,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // CTA button — full width, category color
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _openProfile(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cat.color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Text(
                        _ctaLabel(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Widget _logo(AzamanColors colors, BusinessCategory cat,
      {required double size}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: business.logoUrl != null && business.logoUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: business.logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  _logoPlaceholder(colors, cat, size: size),
              errorWidget: (_, __, ___) =>
                  _logoPlaceholder(colors, cat, size: size),
            )
          : _logoPlaceholder(colors, cat, size: size),
    );
  }

  Widget _logoPlaceholder(AzamanColors colors, BusinessCategory cat,
      {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cat.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(cat.icon, size: size * 0.46, color: cat.color),
    );
  }

  Widget _coverPlaceholder(AzamanColors colors, BusinessCategory cat) {
    return Container(
      color: cat.color.withOpacity(0.07),
      child: Center(
        child: Icon(cat.icon,
            size: 52, color: cat.color.withOpacity(0.25)),
      ),
    );
  }
}

