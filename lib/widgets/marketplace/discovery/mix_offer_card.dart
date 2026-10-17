// =============================================================================
// AZAMAN — MIX OFFER CARD (product-gallery tile)
//
// One item offered by ONE business in the selected category: a near-square
// product tile — a large square product image over a DISTINCT lower
// information panel — item identity and offering store rendered TOGETHER
// (the Mix invariant), plus honest price, payment-rail and availability
// states. The gallery format is deliberately unlike the horizontal
// store/list cards used elsewhere in the app: image-forward, half-feed
// width, with an inset panel that carries its own surface color.
//
// PRICE GRAMMAR (pinned in test/widgets/mix_offer_card_test.dart):
//   • Known price  → `AzMoney.ghsExact(pricing.amount)` — the EXACT
//     two-decimal GHS string from the server's verified BusinessPrice row.
//     String in, string out: the amount is NEVER parsed into a double, so
//     no float can ever round a pesewa.
//   • Unknown price (absent/malformed/non-GHS payload) → "Price
//     unavailable" — never `priceUsdc`, never a converted USDC figure, never
//     "GH₵ 0.00", never "Price on request".
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
const double kMixStoreLogoSize = 20;

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

    return Padding(
      // Row gutter between paired tiles comes from the feed's pair row;
      // the bottom inset keeps vertical breathing room stable in the grid.
      padding: const EdgeInsets.only(bottom: AzSpace.sm),
      child: ScaleTap(
        onTap: () => onOpenStore(offer),
        child: Container(
          key: ValueKey('mix_offer_${offer.offerKey}'),
          clipBehavior: Clip.antiAlias,
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
              // fallback, never a stretched placeholder.
              AspectRatio(
                aspectRatio: 1,
                child: AzamanNetworkImage(
                  imageUrl: offer.primaryImage,
                  cacheManager: cacheManager,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _imageFallback(colors),
                  errorWidget: (_, __, ___) => _imageFallback(colors),
                ),
              ),
              // ── The DISTINCT lower information panel: its own inset
              // surface, visually separated from the image and from the
              // store/list cards used elsewhere in the app.
              Padding(
                padding: const EdgeInsets.all(AzSpace.xs),
                child: Container(
                  key: const ValueKey('mix_offer_panel'),
                  padding: const EdgeInsets.all(AzSpace.sm),
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    borderRadius: BorderRadius.circular(AzRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item identity.
                      Text(
                        offer.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.title.copyWith(
                            color: colors.textPrimary, fontSize: 13.5, height: 1.2),
                      ),
                      const SizedBox(height: AzSpace.xs),
                      // Price — see the grammar in the file header. The
                      // exact string never touches a double.
                      if (priceText != null)
                        Text(
                          priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AzText.money(colors.textPrimary, size: 14),
                        )
                      else
                        Text(
                          'Price unavailable',
                          key: const ValueKey('mix_price_unavailable'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AzText.bodyS.copyWith(color: colors.textTertiary),
                        ),
                      const SizedBox(height: AzSpace.xs),
                      // Offering business — never omitted: the Mix
                      // invariant. The GENUINE logo when the payload has
                      // one; the storefront glyph otherwise.
                      _storeRow(colors),
                      // Payment rail + availability — only what the SERVER
                      // reported. Never GHS payment. Never inferred.
                      if (offer.capabilities.payableIn.isNotEmpty ||
                          offer.isAvailable == false ||
                          offer.sectionWindowOpen == false) ...[
                        const SizedBox(height: AzSpace.xs),
                        Wrap(
                          spacing: AzSpace.xs,
                          runSpacing: AzSpace.xxs,
                          children: [
                            if (offer.capabilities.payableIn.isNotEmpty)
                              _chip(colors, offer.capabilities.payableIn.join('/')),
                            if (offer.isAvailable == false)
                              _chip(colors, 'Unavailable'),
                            if (offer.sectionWindowOpen == false)
                              _chip(colors, 'Opens later'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              style: AzText.bodyS.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      );

  Widget _chip(AzamanColors colors, String label) => Container(
        key: ValueKey('mix_chip_$label'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.xs),
        ),
        child: Text(
          label,
          style: AzText.caption.copyWith(color: colors.textTertiary, fontSize: 10),
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
            size: 13, color: colors.textTertiary),
      );
}
