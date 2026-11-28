// lib/widgets/marketplace/store_cart_actions.dart
// =============================================================================
// Adding a store's product to the cart, from the store page, its catalog and
// its menu. Every order button on a store page used to open the friend-chat
// deal form, which fails without a chat ("No chat context found"). A store
// purchase goes into the cart and is paid from there (store_order_pay.dart).
//
// One cart holds one store's items; adding from another store asks first.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Adds one [product] of [business] to the cart. Returns true when added.
Future<bool> addStoreProductToCart(
  BuildContext context,
  WidgetRef ref, {
  required BusinessProfile business,
  required BusinessProduct product,
  int quantity = 1,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!(product.priceUsdc > 0)) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '${product.name} has no price yet, so it cannot be ordered.',
        ),
      ),
    );
    return false;
  }
  final cart = ref.read(cartProvider.notifier);
  bool add() => cart.addItem(
    businessProfileId: business.id,
    businessName: business.businessName,
    productId: product.id,
    name: product.name,
    unitPrice: product.priceUsdc,
    imageUrl: product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
    category: product.category,
    quantity: quantity,
  );

  var added = add();
  if (!added) {
    final other = ref.read(cartProvider).businessName ?? 'another store';
    final fresh = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
          'Your cart has items from $other. A cart holds one store\'s items at a time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep my cart'),
          ),
          FilledButton(
            key: const ValueKey('cart-start-new'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Start new cart'),
          ),
        ],
      ),
    );
    if (fresh != true) return false;
    cart.startNewCart(
      businessProfileId: business.id,
      businessName: business.businessName,
    );
    added = add();
  }
  if (added && context.mounted) {
    AzamanHaptics.confirm();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.name} added to your cart'),
          action: SnackBarAction(
            label: 'View cart',
            onPressed: () => context.push(AzRoutes.cart),
          ),
        ),
      );
  }
  return added;
}
