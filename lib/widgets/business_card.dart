// lib/widgets/business_card.dart
// =============================================================================
// BUSINESS CARD — Marketplace Premium Upgrade (2026-06-21)
//
// Two layouts controlled by [tall] (default true for search results, false
// for compact strips):
//
//   tall=true  (Booking.com hotel tile):
//     ┌──────────────────────────────────┐
//     │  cover photo (16:9, cached)      │  ← logoUrl or first product image
//     │  [Open Now] [Verified ✓]         │  ← overlaid chips
//     ├──────────────────────────────────┤
//     │  Business Name         [♡ save]  │
//     │  Category  ·  BIZ-XXXX           │
//     │  ★★★★☆ 4.2  ·  38 deals          │
//     │  from 12.00 USDC                 │  ← cheapest product anchor
//     └──────────────────────────────────┘
//
//   tall=false (compact horizontal):
//     [logo 52px] | Name / Category / ★ / from X | [♡] [→]
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/story_ring.dart';

class BusinessCard extends ConsumerWidget {
  final BusinessProfile business;
  final VoidCallback onTap;
  final bool tall; // true = Booking.com tile, false = compact row

  const BusinessCard({
    super.key,
    required this.business,
    required this.onTap,
    this.tall = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return tall ? _tallCard(context, ref, colors) : _compactCard(ref, colors);
  }

  Color? get _categoryColor {
    final cat = BusinessCategories.fromWire(business.category);
    return cat.color;
  }

  // ── Tall photo-first card ─────────────────────────────────────────────────
  Widget _tallCard(BuildContext context, WidgetRef ref, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.divider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.isDark ? 0.25 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _coverPhoto(colors),
            _infoSection(ref, colors),
          ],
        ),
      ),
    );
  }

  Widget _coverPhoto(AzamanColors colors) {
    final coverUrl = _resolveCoverUrl();
    return SizedBox(
      height: 130,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null)
            CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => _coverPlaceholder(colors),
              errorWidget: (_, __, ___) => _coverPlaceholder(colors),
            )
          else
            _coverPlaceholder(colors),
          // Bottom scrim
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black38],
                stops: [0.5, 1.0],
              ),
            ),
          ),
          // Status chips (bottom-left)
          Positioned(
            left: 10,
            bottom: 10,
            child: Row(
              children: [
                if (_isOpenNow()) _chip('Open Now', const Color(0xFF1e8449)),
                if (business.isVerified) ...[
                  if (_isOpenNow()) const SizedBox(width: 6),
                  _chip('Verified', const Color(0xFF1a6b8a)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoSection(WidgetRef ref, AzamanColors colors) {
    final fromPrice = _cheapestPrice();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  business.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _BookmarkButton(bizId: business.bizId),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            business.categoryLabel,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              RatingStars(rating: business.averageRating, size: 14),
              const SizedBox(width: 6),
              Text(
                business.averageRating.toStringAsFixed(1),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.shopping_bag_outlined, size: 12, color: colors.textTertiary),
              const SizedBox(width: 3),
              Text(
                '${business.completedEscrows} orders',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ],
          ),
          if (fromPrice != null) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'from ',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
                TextSpan(
                  text: '${fromPrice.toStringAsFixed(2)} USDC',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          _escrowBadge(colors),
        ],
      ),
    );
  }

  Widget _escrowBadge(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.success.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_outlined, size: 10, color: colors.success),
        const SizedBox(width: 3),
        Text("Escrow Protected", style: TextStyle(
          color: colors.success, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── Compact horizontal card ────────────────────────────────────────────────
  Widget _compactCard(WidgetRef ref, AzamanColors colors) {
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _smallLogo(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        business.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (business.isVerified) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.check_circle_outline, size: 13, color: colors.success),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    business.categoryLabel,
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(children: [
                    RatingStars(rating: business.averageRating, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      business.averageRating.toStringAsFixed(1),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _BookmarkButton(bizId: business.bizId, size: 18),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 14, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _coverPlaceholder(AzamanColors colors) {
    return Container(
      color: colors.accentSurface,
      alignment: Alignment.center,
      child: Text(
        business.businessName.isNotEmpty
            ? business.businessName.substring(0, 1).toUpperCase()
            : 'B',
        style: TextStyle(
          color: colors.accent,
          fontSize: 48,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _smallLogo(AzamanColors colors) {
    return StoryRing(
      avatarUrl: business.logoUrl,
      hasUnseenStory: business.showcaseUrls.isNotEmpty,
      isBoosted: false,
      size: 52,
      storyCount: business.showcaseUrls.isNotEmpty ? business.showcaseUrls.length : 1,
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Cheapest active product price — used for the "from X USDC" anchor.
  double? _cheapestPrice() {
    final active = business.products.where((p) => p.isActive).toList();
    if (active.isEmpty) return null;
    active.sort((a, b) => a.priceUsdc.compareTo(b.priceUsdc));
    return active.first.priceUsdc;
  }

  /// Resolve the best cover image: first product imageUrl → logoUrl → null.
  String? _resolveCoverUrl() {
    for (final prod in business.products) {
      if (prod.imageUrls.isNotEmpty) return prod.imageUrls.first;
    }
    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return business.logoUrl;
    }
    return null;
  }

  /// Returns true if the business has any location marked open at the current
  /// local time. Reads BusinessLocation.operatingHours: {"mon": "08:00-22:00"}.
  bool _isOpenNow() {
    final now = DateTime.now();
    const days = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    final dayKey = days[now.weekday % 7];
    for (final loc in business.locations) {
      final hours = loc.operatingHours;
      if (hours == null) continue;
      final range = hours[dayKey]?.toString();
      if (range == null) continue;
      final parts = range.split('-');
      if (parts.length != 2) continue;
      final open = _parseTime(parts[0].trim());
      final close = _parseTime(parts[1].trim());
      if (open == null || close == null) continue;
      final nowMins = now.hour * 60 + now.minute;
      if (nowMins >= open && nowMins < close) return true;
    }
    return false;
  }

  int? _parseTime(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

// ── Bookmark button (wired to savedBusinessesProvider) ────────────────────────
class _BookmarkButton extends ConsumerWidget {
  final String bizId;
  final double size;
  const _BookmarkButton({required this.bizId, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedBusinessesProvider);
    final isSaved = saved.contains(bizId);
    final colors = ref.watch(themeProvider).colors;
    return GestureDetector(
      onTap: () {
        AzamanHaptics.toggle();
        ref.read(savedBusinessesProvider.notifier).toggle(bizId);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isSaved ? Icons.bookmark_outline : Icons.bookmark_outline,
          key: ValueKey(isSaved),
          size: size,
          color: isSaved ? colors.accent : colors.textTertiary,
        ),
      ),
    );
  }
}

