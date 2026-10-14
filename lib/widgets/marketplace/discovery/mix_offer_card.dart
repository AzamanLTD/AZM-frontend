// =============================================================================
// AZAMAN — MIX OFFER CARD
//
// One item offered by ONE business in the selected category: item identity
// and offering store rendered TOGETHER (the Mix invariant), plus honest
// price, payment-rail and availability states.
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
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/scale_tap.dart';

class MixOfferCard extends ConsumerWidget {
  final MixOffer offer;

  /// Opens the OFFERING store — the tap preserves the selected item's store
  /// identity (`bizId`).
  final void Function(MixOffer offer) onOpenStore;

  const MixOfferCard({
    super.key,
    required this.offer,
    required this.onOpenStore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final price = offer.price;
    final priceText = price.isKnown ? AzMoney.ghsExact(price.amountExact) : null;

    return Padding(
      // Screen-level list insets own the horizontal gutter; the card itself
      // stays full-bleed so it can also be embedded in a sheet.
      padding: const EdgeInsets.only(bottom: AzSpace.sm),
      child: ScaleTap(
        onTap: () => onOpenStore(offer),
        child: Container(
          key: ValueKey('mix_offer_${offer.offerKey}'),
          constraints: const BoxConstraints(minHeight: 88),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AzRadius.lg),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AzRadius.lg)),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: AzamanNetworkImage(
                    imageUrl: offer.primaryImage,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _imageFallback(colors),
                    errorWidget: (_, __, ___) => _imageFallback(colors),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AzSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item identity.
                      Text(
                        offer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.title.copyWith(color: colors.textPrimary, fontSize: 15),
                      ),
                      const SizedBox(height: AzSpace.xs),
                      // Offering business — never omitted: the Mix invariant.
                      Row(
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 13, color: colors.textTertiary),
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
                      ),
                      const SizedBox(height: AzSpace.sm),
                      Row(
                        children: [
                          // Price — see the grammar in the file header. The
                          // exact string never touches a double.
                          if (priceText != null) ...[
                            Flexible(
                              child: Text(
                                priceText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    AzText.money(colors.textPrimary, size: 14),
                              ),
                            ),
                          ] else
                            Text(
                              'Price unavailable',
                              key: const ValueKey('mix_price_unavailable'),
                              style: AzText.bodyS.copyWith(color: colors.textTertiary),
                            ),
                          // Payment rail — only what the SERVER reported as
                          // supported (today USDC). Never GHS payment.
                          if (offer.capabilities.payableIn.isNotEmpty) ...[
                            const SizedBox(width: AzSpace.sm),
                            _chip(colors, offer.capabilities.payableIn.join('/')),
                          ],
                          // Availability — only when the payload said so.
                          if (offer.isAvailable == false) ...[
                            const SizedBox(width: AzSpace.sm),
                            _chip(colors, 'Unavailable'),
                          ],
                          if (offer.sectionWindowOpen == false) ...[
                            const SizedBox(width: AzSpace.sm),
                            _chip(colors, 'Opens later'),
                          ],
                        ],
                      ),
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

  Widget _chip(AzamanColors colors, String label) => Container(
        key: ValueKey('mix_chip_$label'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.softSurface,
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
}
