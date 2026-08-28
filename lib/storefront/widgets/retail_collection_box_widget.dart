import 'package:flutter/material.dart';

import '../../marketplace/experiences/retail/retail_experience.dart';
import '../models/storefront_models.dart';

/// SDUI adapter for RetailCollectionBox. Portal-authored props remain data;
/// this adapter owns only safe parsing and category-specific presentation.
class RetailCollectionBoxWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const RetailCollectionBoxWidget({
    super.key,
    required this.props,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final collection = RetailCollection(
      id: (props['id'] ?? props['collectionId'] ?? 'retail-collection').toString(),
      title: (props['title'] ?? 'Collection').toString(),
      subtitle: props['subtitle']?.toString(),
      products: _parseProducts(props['products']),
    );

    if (collection.products.isEmpty) {
      return _EmptyCollection(title: collection.title);
    }

    return RetailCollectionBox(
      collection: collection,
      onProductTap: (product) => showRetailQuickLook(
        context,
        product: product,
        onAddToCart: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product.name} added to bag')),
          );
        },
      ),
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
