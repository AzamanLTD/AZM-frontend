// =============================================================================
// RETAIL TRAY COMMIT — one guarded way to put a retail product in the tray.
//
// The shared tray (cartProvider) owns cross-business scoping: a cart can
// only hold one business's items. Before TASK-012 the storefront collection
// box bypassed the tray entirely (its own local RetailCart), so one
// storefront could show two different bags. This helper is the single commit
// path for retail surfaces that are NOT the storefront screen itself:
//   - RetailCollectionBoxWidget (quick look + lift gesture)
//   - the stage's productDossier "Add to bag"
//
// It reproduces the storefront screen's cross-business dialog exactly, and
// deliberately fires NO haptic — the tray's own listener plays the catch
// haptic when the item lands (FloatingCartBar).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/providers/cart_provider.dart';

/// Adds [product] to the shared tray. Shows the "Start new cart?" dialog when
/// the tray holds another business's items. Returns true when the item is in
/// the tray at the end.
///
/// A product whose price is unknown ([RetailProduct.price] == null) never
/// enters the tray: an unknown monetary value is not zero, and letting it
/// through would let the cart display a made-up subtotal. A genuine
/// zero-priced product (price == 0) is a real price and commits normally.
Future<bool> retailCommitToTray(
  BuildContext context,
  WidgetRef ref, {
  required String businessProfileId,
  required String businessName,
  required RetailProduct product,
  Map<String, String> variants = const {},
  int quantity = 1,
}) async {
  if (!product.available || product.price == null || quantity <= 0) {
    return false;
  }

  final cart = ref.read(cartProvider);
  final crossBusiness =
      cart.businessProfileId != null &&
      cart.businessProfileId != businessProfileId &&
      cart.items.isNotEmpty;

  if (crossBusiness) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start new cart?'),
        content: Text(
          'Your cart has items from ${cart.businessName ?? 'another business'}. '
          'Starting a new cart will remove those items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep current cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start new cart'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!context.mounted) return false;
    ref
        .read(cartProvider.notifier)
        .startNewCart(
          businessProfileId: businessProfileId,
          businessName: businessName,
        );
  }

  final imageUrls = product.imageUrls;
  return ref
      .read(cartProvider.notifier)
      .addItem(
        businessProfileId: businessProfileId,
        businessName: businessName,
        productId: product.id,
        name: product.name,
        // Guarded above: a null price never reaches here, so this is the
        // real price — including a genuine 0.
        unitPrice: product.price!,
        imageUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
        experiencePreset: 'SHOP_FLOOR',
        quantity: quantity,
        variants: variants,
      );
}
