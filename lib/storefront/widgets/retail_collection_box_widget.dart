import 'package:flutter/material.dart';

import '../../marketplace/experiences/retail/retail_cart.dart';
import '../../marketplace/experiences/retail/retail_cart_sheet.dart';
import '../../marketplace/experiences/retail/retail_experience.dart';
import '../models/storefront_models.dart';

/// SDUI adapter for RetailCollectionBox. Portal-authored props remain data;
/// this adapter owns safe parsing and category-specific presentation.
///
/// Cart state is intentionally local to the rendered retail experience. It is
/// not treated as an order or source of truth for price/inventory.
class RetailCollectionBoxWidget extends StatefulWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const RetailCollectionBoxWidget({
    super.key,
    required this.props,
    required this.business,
  });

  @override
  State<RetailCollectionBoxWidget> createState() => _RetailCollectionBoxWidgetState();
}

class _RetailCollectionBoxWidgetState extends State<RetailCollectionBoxWidget> {
  RetailCart _cart = const RetailCart();

  @override
  Widget build(BuildContext context) {
    final collection = RetailCollection(
      id: (widget.props['id'] ?? widget.props['collectionId'] ?? 'retail-collection').toString(),
      title: (widget.props['title'] ?? 'Collection').toString(),
      subtitle: widget.props['subtitle']?.toString(),
      products: _parseProducts(widget.props['products']),
    );

    if (collection.products.isEmpty) {
      return _EmptyCollection(title: collection.title);
    }

    return Stack(
      children: [
        RetailCollectionBox(
          collection: collection,
          onProductTap: (product) => showRetailQuickLook(
            context,
            product: product,
            onAddToCart: (item) {
              setState(() => _cart = _cart.add(item));
              _showAddedMessage(context, item);
            },
          ),
        ),
        if (_cart.itemCount > 0)
          Positioned(
            right: 8,
            top: 0,
            child: _BagButton(
              itemCount: _cart.itemCount,
              onPressed: () => showRetailCartSheet(
                context,
                cart: _cart,
                onChanged: (next) => setState(() => _cart = next),
                onCheckout: () => _showCheckoutBoundary(context),
              ),
            ),
          ),
      ],
    );
  }

  void _showAddedMessage(BuildContext context, RetailProduct product) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} added to bag')),
    );
  }

  void _showCheckoutBoundary(BuildContext context) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checkout is ready for the order service.')),
    );
  }

  List<RetailProduct> _parseProducts(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => RetailProduct.fromJson(Map<String, dynamic>.from(item)))
        .where((product) => product.id.isNotEmpty)
        .toList(growable: false);
  }
}

class _BagButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback onPressed;

  const _BagButton({required this.itemCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 18),
              const SizedBox(width: 6),
              Text('$itemCount', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final String title;

  const _EmptyCollection({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '$title is empty',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
