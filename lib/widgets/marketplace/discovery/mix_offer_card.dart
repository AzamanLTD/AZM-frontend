// =============================================================================
// AZAMAN — MIX OFFER CARD (product-gallery tile)
//
// One item offered by ONE business in the selected category: a product
// tile — a full-width SQUARE product image over a compact, DISTINCT lower
// information panel — item identity and offering store rendered TOGETHER
// (the Mix invariant), plus honest price, payment-rail and availability
// states. The gallery format is deliberately unlike the horizontal
// store/list cards used elsewhere in the app: image-forward, half-feed
// width, with an inset panel that carries its own surface color.
//
// GEOMETRY CONTRACT (pinned in test/widgets/mix_offer_card_test.dart):
//   • The product image is a 1:1 SQUARE filling the tile width.
//   • The WHOLE tile is near-square: height ≤ 1.5 × width (a 2:3
//     product-tile ratio at the WORST case, the 320dp feed cell) and
//     ≥ 1.0 × width (the square image anchors the floor). The panel is
//     the only addition and it is capped with it: one-line name, one
//     price line, one store row — nothing else. Chips are NOT panel
//     content; they overlay the image so they can never grow the tile.
// PRICE GRAMMAR (pinned in test/widgets/mix_offer_card_test.dart):
//   • Known price  → `AzMoney.ghsExact(pricing.amount)` — the EXACT
//     two-decimal GHS string from the server's verified BusinessPrice row.
//     String in, string out: the amount is NEVER parsed into a double, so
//     no float can ever round a pesewa.
//   • Unknown price (absent/malformed/non-GHS payload) → "Price
//     unavailable" — never `priceUsdc`, never a converted USDC figure,
//     never "GH₵ 0.00", never "Price on request".
// PAYMENT-RAIL GRAMMAR (honest capability, §5.3):
//   • `capabilities.payableIn` renders as a quiet "USDC" rail chip when
//     non-empty (today the merged endpoint reports `['USDC']`).
//   • A GHS LISTING price never implies GHS payment: no GHS payment chip
//     exists in this build because the server does not report one.
// AVAILABILITY GRAMMAR:
//   • `isAvailable == false` → a quiet "Unavailable" chip.
//   • `sectionWindowOpen == false` → a quiet "Opens later" chip (the
//     item's serving window is closed right now).
//   • `isAvailable == null` / `sectionWindowOpen == null` (absent fields)
//     → NO availability signal. Availability is never inferred from a
//     price or a missing field.
// STORE LOGO GRAMMAR:
//   • The panel's store row shows the store's GENUINE logo
//     (`offer.businessLogoUrl`) when the payload carries one. Absent or
//     failed to load → the storefront glyph + name, never an inferred or
//     substituted image (never the ITEM image).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// The diameter of the store row's logo chip.
const double kMixStoreLogoSize = 16;

/// The whole-tile ratio ceiling: height ≤ 1.5 × width (2:3). Enforced at
/// the worst case — the 320dp feed cell.
const double kMixTileMaxHeightRatio = 1.5;

class MixOfferCard extends ConsumerWidget {
  final MixOffer offer;

  /// Opens the OFFERING store — the tap preserves the selected item's store
  /// identity (`bizId`).
  final void Function(MixOffer offer) onOpenStore;

  /// Optional cache manager for the tile's network images. Null (production)
  /// uses CachedNetworkImage's own default. The evidence suite injects a
  /// local-file manager so REAL bytes render through the exact production
  /// path (the sandbox blocks the sqlite-backed default).
  final BaseCacheManager? cacheManager;

  const MixOfferCard({
    super.key,
    required this.offer,
    required this.onOpenStore,
    this.cacheManager,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final price = offer.price;
    final priceText = price.isKnown ? AzMoney.ghsExact(price.amountExact) : null;

    return ScaleTap(
      onTap: () => onOpenStore(offer),
      child: Container(
        key: ValueKey('mix_offer_${offer.offerKey}'),
        clipBehavior: Clip.antiAlias,
        // No vertical padding on the tile itself — the feed's pair row
        // owns the grid gutter, so the tile rect IS the visual tile the
        // geometry contract measures.
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.lg),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Product image: a full-width SQUARE — the gallery format's
            // near-square anchor. Absent/failed image → the glyph
            // fallback, never a stretched placeholder. Server-reported
            // chips (payment rail / availability) OVERLAY the image so
            // they can never grow the tile's height.
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  AzamanNetworkImage(
                    imageUrl: offer.primaryImage,
                    cacheManager: cacheManager,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _imageFallback(colors),
                    errorWidget: (_, __, ___) => _imageFallback(colors),
                  ),
                  if (_hasChips)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (offer.capabilities.payableIn.isNotEmpty)
                            _chip(colors, offer.capabilities.payableIn.join('/')),
                          if (offer.isAvailable == false)
                            _chip(colors, 'Unavailable'),
                          if (offer.sectionWindowOpen == false)
                            _chip(colors, 'Opens later'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // ── The compact, DISTINCT lower information panel: its own
            // inset surface. Exactly three fixed rows — name, price,
            // store — so the whole-tile ratio ceiling holds at every
            // width.
            Padding(
              padding: const EdgeInsets.fromLTRB(AzSpace.xs, 2, AzSpace.xs, 3),
              child: Container(
                key: const ValueKey('mix_offer_panel'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(AzRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item identity — one line; the tile's height budget
                    // never depends on the name's length.
                    Text(
                      offer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AzText.title.copyWith(
                          color: colors.textPrimary, fontSize: 12.5, height: 1.25),
                    ),
                    const SizedBox(height: 2),
                    // Price — see the grammar in the file header. The
                    // exact string never touches a double.
                    if (priceText != null)
                      Text(
                        priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.money(colors.textPrimary, size: 13.5),
                      )
                    else
                      Text(
                        'Price unavailable',
                        key: const ValueKey('mix_price_unavailable'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.bodyS.copyWith(color: colors.textTertiary),
                      ),
                    const SizedBox(height: 2),
                    // Offering business — never omitted: the Mix
                    // invariant. The GENUINE logo when the payload has
                    // one; the storefront glyph otherwise.
                    _storeRow(colors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasChips =>
      offer.capabilities.payableIn.isNotEmpty ||
      offer.isAvailable == false ||
      offer.sectionWindowOpen == false;

  /// The compact store identity row: genuine logo (or glyph) + name.
  Widget _storeRow(AzamanColors colors) => Row(
        key: const ValueKey('mix_offer_store_row'),
        children: [
          SizedBox(
            width: kMixStoreLogoSize,
            height: kMixStoreLogoSize,
            child: ClipOval(
              // No logo URL → the glyph directly (AzamanNetworkImage's
              // null-URL path would render its generic image glyph, not
              // the storefront identity). A URL that FAILS to load falls
              // back to the same glyph via errorWidget.
              child: offer.businessLogoUrl == null
                  ? _logoFallback(colors)
                  : AzamanNetworkImage(
                      key: const ValueKey('mix_store_logo'),
                      imageUrl: offer.businessLogoUrl,
                      cacheManager: cacheManager,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _logoFallback(colors),
                      errorWidget: (_, __, ___) => _logoFallback(colors),
                    ),
            ),
          ),
          const SizedBox(width: AzSpace.xs),
          Expanded(
            child: Text(
              offer.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AzText.bodyS.copyWith(color: colors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      );

  /// A quiet server-reported chip. Overlaid on the product image, so it
  /// needs its own solid surface in both themes.
  Widget _chip(AzamanColors colors, String label) => Container(
        key: ValueKey('mix_chip_$label'),
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.xs),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Text(
          label,
          style:
              AzText.caption.copyWith(color: colors.textTertiary, fontSize: 9),
        ),
      );

  Widget _imageFallback(colors) => Container(
        color: colors.softSurface,
        child: Icon(Icons.inventory_2_outlined,
            size: 26, color: colors.textTertiary),
      );

  Widget _logoFallback(AzamanColors colors) => Container(
        key: const ValueKey('mix_store_logo_fallback'),
        color: colors.card,
        child: Icon(Icons.storefront_outlined,
            size: 10, color: colors.textTertiary),
      );
}
