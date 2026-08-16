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

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/animated_rating_stars.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/screens/marketplace/leave_review_sheet.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

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


  // ── Collapsed bar (screenshot aesthetic) ─────────────────────────────────────
  //
  // Tall row with a large square-ish flush image on the left (no internal
  // border-radius — outer card clips), bold business name, category label,
  // rating, and a right chevron. Clean and scannable — matches the meal-list
  // screenshot reference provided 2026-07-11.
  //
  // Height: 88px — noticeably taller than the old 68px so the image has room.

  Widget _collapsedBar(
      BuildContext context, AzamanColors colors, BusinessCategory cat) {
    final coverUrl = _bestCoverUrl(cat);
    return GestureDetector(
      onTap: () {
        AzamanHaptics.toggle();
        onToggle();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        height: 90,
        decoration: BoxDecoration(
          // Subtle purple hue tint on vendor cards — blends the category
          // color with the card surface for a cohesive brand feel.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cat.color.withValues(alpha: colors.isDark ? 0.08 : 0.05),
              colors.card,
            ],
            stops: const [0.0, 0.35],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: cat.color.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.isDark ? 0.22 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Left image tile (88×88) ───────────────────────────────────
            Stack(
              children: [
                SizedBox(
                  width: 90,
                  height: double.infinity,
                  child: coverUrl != null
                      ? AzamanNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _imgPlaceholder(cat),
                          errorWidget: (_, __, ___) => _imgPlaceholder(cat),
                        )
                      : _imgPlaceholder(cat),
                ),
                // Category colour label overlay at bottom-left
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    color: cat.color.withValues(alpha: 0.82),
                    child: Text(
                      cat.label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ── Text content ──────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Name + bookmark
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.businessName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _BookmarkToggle(bizId: business.bizId, colors: colors),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Subtitle row: rating stars + verified
                    Row(
                      children: [
                        if (business.averageRating > 0) ...[
                          AnimatedRatingStars(
                            rating: business.averageRating,
                            size: 11,
                            filledColor: const Color(0xFFF59E0B),
                            emptyColor: colors.divider,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            business.averageRating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (business.isVerified)
                          Icon(Icons.verified_rounded,
                              size: 13, color: colors.accent),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Description preview or vertical stat
                    Text(
                      _subtitleLine(),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // ── Chevron ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: Icon(Icons.chevron_right_rounded,
                      color: colors.textTertiary, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Best image for the collapsed tile — prefers a real Unsplash cover seeded
  /// per category, falls back to logoUrl, then null.
  String? _bestCoverUrl(BusinessCategory cat) {
    // Use showcaseUrls first (set by portal), then logoUrl.
    if (business.showcaseUrls.isNotEmpty) return business.showcaseUrls.first;
    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return business.logoUrl;
    }
    // Per-category Unsplash fallback — deterministic by bizId hash so each
    // business always gets the same image but different businesses in the
    // same category look varied.
    final fallbacks = _categoryFallbacks(cat);
    if (fallbacks.isEmpty) return null;
    final idx = business.bizId.codeUnits
        .fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7FFFFFFF) %
        fallbacks.length;
    return fallbacks[idx];
  }

  String _subtitleLine() {
    if (business.description != null && business.description!.isNotEmpty) {
      return business.description!;
    }
    return _verticalStat() ??
        BusinessCategories.fromWire(business.category).label;
  }

  Widget _imgPlaceholder(BusinessCategory cat) => Container(
        color: cat.color.withValues(alpha: 0.12),
        child: Center(
          child: Icon(cat.icon, size: 34, color: cat.color.withValues(alpha: 0.5)),
        ),
      );

  /// Per-category Unsplash image pool (real food/product/venue photos, no emoji).
  static List<String> _categoryFallbacks(BusinessCategory cat) {
    const food = [
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80',
      'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&q=80',
      'https://images.unsplash.com/photo-1512058564366-18510be2db19?w=400&q=80',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&q=80',
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400&q=80',
    ];
    const retail = [
      'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=400&q=80',
      'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=400&q=80',
      'https://images.unsplash.com/photo-1607082348824-0a96f2a4b9da?w=400&q=80',
    ];
    const hotel = [
      'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=400&q=80',
      'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=400&q=80',
      'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=400&q=80',
    ];
    const transit = [
      'https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=400&q=80',
      'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400&q=80',
      'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=400&q=80',
    ];
    const realestate = [
      'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=400&q=80',
      'https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=400&q=80',
      'https://images.unsplash.com/photo-1449844908441-8829872d2607?w=400&q=80',
    ];
    const tech = [
      'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400&q=80',
      'https://images.unsplash.com/photo-1531297484001-80022131f5a1?w=400&q=80',
      'https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=400&q=80',
    ];
    const health = [
      'https://images.unsplash.com/photo-1579684385127-1ef15d508118?w=400&q=80',
      'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=400&q=80',
    ];
    const edu = [
      'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=400&q=80',
      'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=400&q=80',
    ];
    const entertainment = [
      'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&q=80',
      'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=400&q=80',
    ];
    const generic = [
      'https://images.unsplash.com/photo-1542744173-8e7e53415bb0?w=400&q=80',
      'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=400&q=80',
    ];

    return switch (cat.wire) {
      'FOOD_BEVERAGE'             => food,
      'RETAIL'                    => retail,
      'HOSPITALITY'               => hotel,
      'LOGISTICS'                 => transit,
      'REAL_ESTATE'               => realestate,
      'TECHNOLOGY'                => tech,
      'HEALTH_WELLNESS'           => health,
      'EDUCATION'                 => edu,
      'ENTERTAINMENT'             => entertainment,
      _                           => generic,
    };
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
                  .withValues(alpha: colors.isDark ? 0.28 : 0.07),
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
                    AzamanNetworkImage(
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

                  // Top-left stack: follow button, plus distance chip below
                  // it when we have a location fix.
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FollowButton(bizId: business.bizId),
                        if (distanceKm != null) ...[
                          const SizedBox(height: 6),
                          PremiumGlassContainer(
                            blur: 8, opacity: 0.08, borderRadius: 8,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), enableShadow: false,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_rounded, size: 10, color: colors.textTertiary),
                                const SizedBox(width: 3),
                                Text('${distanceKm!.toStringAsFixed(1)} km',
                                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
                        ],
                      ],
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
                          color: Colors.black.withValues(alpha: 0.45),
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

            // ── Squircle avatar — overlaps cover/details seam ────────
            _ExpandedAvatar(business: business, cat: cat, colors: colors),

            // ── Details section ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
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
                        const Icon(Icons.star_rounded,
                            size: 13,
                            color: Color(0xFFF59E0B)),
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
                  Row(
                    children: [
                      Expanded(child: _glassActionPill(icon: Icons.storefront_outlined, label: 'Visit', colors: colors,
                        onTap: () => _openProfile(context))),
                      const SizedBox(width: 8),
                      Expanded(child: _glassActionPill(icon: Icons.reviews_outlined, label: 'Review', colors: colors,
                        onTap: () => LeaveReviewSheet.show(context, business: business))),
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

  Widget _glassActionPill({required IconData icon, required String label, required AzamanColors colors, required VoidCallback onTap, bool accent = false}) {
    return GestureDetector(
      onTap: () { AzamanHaptics.nav(); onTap(); },
      child: PremiumGlassContainer(
        blur: 8, opacity: accent ? 0.12 : 0.04, borderRadius: 12,
        padding: const EdgeInsets.symmetric(vertical: 10), enableShadow: false,
        border: Border.all(color: accent ? colors.accent.withValues(alpha: 0.4) : colors.divider, width: 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent ? colors.accent : colors.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent ? colors.accent : colors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Widget _logo(AzamanColors colors, BusinessCategory cat,
      {required double size}) {
    return Hero(
      tag: 'biz-logo-${business.id}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: business.logoUrl != null && business.logoUrl!.isNotEmpty
            ? AzamanNetworkImage(
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
      ),
    );
  }

  Widget _logoPlaceholder(AzamanColors colors, BusinessCategory cat,
      {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(cat.icon, size: size * 0.46, color: cat.color),
    );
  }

  Widget _coverPlaceholder(AzamanColors colors, BusinessCategory cat) {
    return Container(
      color: cat.color.withValues(alpha: 0.07),
      child: Center(
        child: Icon(cat.icon,
            size: 52, color: cat.color.withValues(alpha: 0.25)),
      ),
    );
  }
}


// =============================================================================
// Bookmark toggle — small icon shown right after the business name, before
// the verified badge. Backed by the real savedBusinessesProvider (persisted
// wishlist), replacing the old non-functional "Save" pill in the expanded
// card.
// =============================================================================
class _BookmarkToggle extends ConsumerWidget {
  final String bizId;
  final AzamanColors colors;

  const _BookmarkToggle({required this.bizId, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedBusinessesProvider).contains(bizId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.toggle();
        ref.read(savedBusinessesProvider.notifier).toggle(bizId);
      },
      child: Icon(
        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: 16,
        color: saved ? colors.accent : colors.textTertiary,
      ),
    );
  }
}

// =============================================================================
// Follow button — top-left of the expanded card's cover photo. Lets a user
// follow a business straight from the marketplace list. Uses the same
// /follows/* backend contract as the full business profile screen (GET
// /follows/check/:id, POST /follows, DELETE /follows/:id) via the shared
// apiClientProvider.
// =============================================================================
class _FollowButton extends ConsumerStatefulWidget {
  final String bizId;
  const _FollowButton({required this.bizId});

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _isFollowing = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/follows/check/${widget.bizId}');
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _isFollowing = data['isFollowing'] ?? false;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    AzamanHaptics.toggle();
    final was = _isFollowing;
    setState(() {
      _isFollowing = !was;
      _busy = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      if (was) {
        await client.delete('/follows/${widget.bizId}');
      } else {
        await client.post('/follows', {'businessProfileId': widget.bizId});
      }
    } catch (_) {
      if (mounted) setState(() => _isFollowing = was);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isFollowing
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: _isFollowing
              ? Border.all(color: Colors.white54, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFollowing ? Icons.check_rounded : Icons.add_rounded,
              size: 13,
              color: _isFollowing ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                _isFollowing ? 'Following' : 'Follow',
                key: ValueKey(_isFollowing),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _isFollowing ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 250.ms);
  }
}

// =============================================================================
// Expandable profile picture — bezel-less (no border/card chrome around the
// image itself, just the raw photo clipped to a circle). Tapping it opens a
// full-size lightbox view via a Hero transition.
// =============================================================================
class _ExpandableProfilePic extends StatelessWidget {
  final BusinessProfile business;
  final BusinessCategory cat;
  final double width;

  const _ExpandableProfilePic({
    required this.business,
    required this.cat,
    required this.width,
  });

  void _openLightbox(BuildContext context) {
    if (business.logoUrl == null || business.logoUrl!.isEmpty) return;
    AzamanHaptics.toggle();
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, animation, __) {
        return FadeTransition(
          opacity: animation,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Hero(
                  tag: 'biz-pic-${business.bizId}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AzamanNetworkImage(
                      imageUrl: business.logoUrl!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasPic = business.logoUrl != null && business.logoUrl!.isNotEmpty;
    // No bezel, no circle — a clean flush rectangle that fills the full
    // height of the collapsed row (via the parent's IntrinsicHeight +
    // CrossAxisAlignment.stretch). The outer PremiumGlassContainer clips
    // this to its own rounded corners, so only the left edge is rounded.
    return GestureDetector(
      onTap: hasPic ? () => _openLightbox(context) : null,
      child: Hero(
        tag: 'biz-pic-${business.bizId}',
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: hasPic
              ? AzamanNetworkImage(
                  imageUrl: business.logoUrl!,
                  width: width,
                  height: double.infinity,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: cat.color.withValues(alpha: 0.10),
                  child: Icon(cat.icon, size: width * 0.4, color: cat.color),
                ),
        ),
      ),
    );
  }
}

// =============================================================================
// _ExpandedAvatar — squircle profile picture that spans the seam between the
// cover photo and the details section in the expanded card. Mirrors the
// FeaturedBusinessCard avatar style but uses ContinuousRectangleBorder (the
// same squircle shape used by StoryRing) instead of a circle clip.
// =============================================================================
class _ExpandedAvatar extends StatelessWidget {
  final BusinessProfile business;
  final BusinessCategory cat;
  final AzamanColors colors;

  const _ExpandedAvatar({
    required this.business,
    required this.cat,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 52;
    final hasPic =
        business.logoUrl != null && business.logoUrl!.isNotEmpty;

    return Transform.translate(
      // Pull the avatar up so it overlaps the bottom of the cover photo.
      offset: const Offset(0, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(
          children: [
            // Squircle avatar
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.card, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipPath(
                clipper: ShapeBorderClipper(
                  shape: ContinuousRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: hasPic
                    ? AzamanNetworkImage(
                        imageUrl: business.logoUrl!,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        placeholder: (_, __) => _placeholder(),
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 10),
            // Business name beside the avatar
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    business.businessName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (business.description != null &&
                      business.description!.isNotEmpty)
                    Text(
                      business.description!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: cat.color.withValues(alpha: 0.12),
        child:
            Center(child: Icon(cat.icon, size: 24, color: cat.color)),
      );
}

