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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/server_bookmarks_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/business_hours.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

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
            AzamanNetworkImage(
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
              _BookmarkButton(business: business),
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
                if (_cheapestGhs() != null)
                  TextSpan(
                    text: 'from ',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                TextSpan(
                  // GHS availability truth (final acceptance follow-up
                  // 2026-10-19): the legacy priceUsdc figure is never a
                  // substitute browse listing price — without a
                  // server-confirmed GHS price the anchor says so,
                  // single-line and muted, WITHOUT the 'from' prefix (an
                  // unavailable state is not a price range).
                  text: _cheapestGhs() != null
                      ? 'GH₵${_cheapestGhs()}'
                      : 'Price unavailable',
                  style: _cheapestGhs() != null
                      ? TextStyle(
                          color: colors.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        )
                      : TextStyle(
                          color: colors.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
            _BookmarkButton(business: business, size: 18),
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
      // §9: showcase media is NOT story data — the old ring faked an
      // "unseen story" signal (and a fake count) from showcaseUrls. The
      // ring speaks story language only, so it stays plain here.
      counts: const StoryRingCounts.empty(),
      isBoosted: false,
      size: 52,
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

  /// Cheapest authoritative merchant GHS price across active products
  /// (server-confirmed BusinessPrice rows only — never a converted USDC
  /// figure). Returns the exact 2dp string the server sent.
  String? _cheapestGhs() {
    final priced = business.products
        .where((p) => p.isActive && p.priceGhs != null)
        .toList();
    if (priced.isEmpty) return null;
    // Numeric comparison (final acceptance pass 2026-10-19): exact 2dp
    // strings must never be ordered lexicographically ('100.00' < '49.50'
    // < '9.00' as text). The DISPLAYED value stays the server's exact 2dp
    // string; only the ordering parses it. A malformed value fails closed
    // to worst (never the cheapest slot).
    priced.sort((a, b) => _ghsOrderKey(a.priceGhs)
        .compareTo(_ghsOrderKey(b.priceGhs)));
    return priced.first.priceGhs;
  }

  /// Ordering key for a canonical GHS string: numeric value, with malformed
  /// input (never expected — the model strictly parses exact 2dp strings)
  /// demoted to the end of the ordering.
  double _ghsOrderKey(String? ghs) => double.tryParse(ghs ?? '') ?? double.infinity;

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
  /// local time. Delegates to the shared [BusinessHours] parser so every
  /// surface agrees on "open now".
  bool _isOpenNow() =>
      business.openStateAt(DateTime.now()) == OpenState.open;
}

// ── Bookmark button (durable server bookmarks; demo keeps the local wishlist) ─
class _BookmarkButton extends ConsumerWidget {
  final BusinessProfile business;
  final double size;
  const _BookmarkButton({required this.business, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = isBusinessSaved(ref, business);
    final colors = ref.watch(themeProvider).colors;
    return GestureDetector(
      onTap: () {
        AzamanHaptics.toggle();
        toggleBusinessSaved(context, ref, business);
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

