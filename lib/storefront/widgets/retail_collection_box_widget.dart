import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marketplace/experiences/retail/retail_checkout.dart';
import '../../marketplace/experiences/retail/retail_experience.dart';
import '../../widgets/marketplace/retail_tray_commit.dart';
import '../models/storefront_models.dart';

/// The storefront's retail collection shelf (SDUI `retail_collection_box`).
///
/// Since TASK-012 every add — quick look or lift gesture — commits to the
/// SHARED tray (cartProvider), so FloatingCartBar and CartScreen own the bag.
/// The previous local `RetailCart` copy (with its own sheet and checkout
/// flow) is retired from this widget; those files remain as public API.
class RetailCollectionBoxWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  /// The storefront's business profile id — the registry holds it;
  /// [StorefrontBusinessInfo] does not carry it (F-034).
  final String? businessProfileId;

  /// Kept for constructor compatibility. Since TASK-012, checkout runs
  /// through the shared tray (cartProvider → CartScreen); this widget no
  /// longer reads the gateway.
  final RetailCheckoutGateway? checkoutGateway;

  const RetailCollectionBoxWidget({
    super.key,
    required this.props,
    required this.business,
    this.businessProfileId,
    this.checkoutGateway,
  });

  @override
  ConsumerState<RetailCollectionBoxWidget> createState() =>
      _RetailCollectionBoxWidgetState();
}

class _RetailCollectionBoxWidgetState
    extends ConsumerState<RetailCollectionBoxWidget> {
  @override
  Widget build(BuildContext context) {
    final collection = RetailCollection(
      id: (widget.props['id'] ??
              widget.props['collectionId'] ??
              'retail-collection')
          .toString(),
      title: (widget.props['title'] ?? 'Collection').toString(),
      subtitle: widget.props['subtitle']?.toString(),
      products: _parseProducts(widget.props['products']),
    );

    if (collection.products.isEmpty) {
      return _EmptyCollection(title: collection.title);
    }

    return RetailCollectionBox(
      collection: collection,
      onProductTap: (product) => showRetailQuickLook(
        context,
        product: product,
        onAddToCart: (selection) => _commitToTray(
          selection.product,
          variants: selection.variants,
          quantity: selection.quantity,
        ),
      ),
      liftCommit: widget.businessProfileId == null
          ? null
          : (product) => _commitOrQuickLook(product),
    );
  }

  /// Variant products cannot commit blind — a lift on them opens the quick
  /// look instead, so the user picks sizes/colours first.
  Future<void> _commitOrQuickLook(RetailProduct product) async {
    if (product.variants.isEmpty) {
      await _commitToTray(product);
      return;
    }
    showRetailQuickLook(
      context,
      product: product,
      onAddToCart: (selection) => _commitToTray(
        selection.product,
        variants: selection.variants,
        quantity: selection.quantity,
      ),
    );
  }

  Future<void> _commitToTray(
    RetailProduct product, {
    Map<String, String> variants = const {},
    int quantity = 1,
  }) async {
    final businessProfileId = widget.businessProfileId;
    if (businessProfileId == null || businessProfileId.isEmpty) return;
    final added = await retailCommitToTray(
      context,
      ref,
      businessProfileId: businessProfileId,
      businessName: widget.business.name,
      product: product,
      variants: variants,
      quantity: quantity,
    );
    if (!mounted || !added) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to cart'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<RetailProduct> _parseProducts(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => RetailProduct.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((product) => product.id.isNotEmpty)
        .toList(growable: false);
  }
}

class _EmptyCollection extends StatelessWidget {
  final String title;

  const _EmptyCollection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '$title is empty',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
