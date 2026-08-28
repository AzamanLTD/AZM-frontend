import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';

/// Normalized retail product used by the category-specific retail experience.
///
/// This deliberately remains UI-facing: authoritative price, inventory and
/// order state still come from the backend. The experience never calculates
/// checkout totals locally.
class RetailProduct {
  final String id;
  final String name;
  final String? description;
  final double? price;
  final String? currency;
  final List<String> imageUrls;
  final List<String> tags;
  final Map<String, dynamic> variants;
  final bool available;

  const RetailProduct({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.currency,
    this.imageUrls = const [],
    this.tags = const [],
    this.variants = const {},
    this.available = true,
  });

  factory RetailProduct.fromJson(Map<String, dynamic> json) {
    final rawImages = json['imageUrls'] ?? json['images'];
    final rawTags = json['tags'];
    final rawVariants = json['variants'];
    return RetailProduct(
      id: (json['id'] ?? json['productId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Product').toString(),
      description: json['description']?.toString(),
      price: _toDoubleOrNull(json['price'] ?? json['priceUsdc']),
      currency: json['currency']?.toString(),
      imageUrls: rawImages is List
          ? rawImages.map((value) => value.toString()).where((value) => value.isNotEmpty).toList()
          : const [],
      tags: rawTags is List
          ? rawTags.map((value) => value.toString()).where((value) => value.isNotEmpty).toList()
          : const [],
      variants: rawVariants is Map
          ? Map<String, dynamic>.from(rawVariants)
          : const {},
      available: json['available'] != false && json['isActive'] != false,
    );
  }

  String get formattedPrice {
    if (price == null) return 'Price unavailable';
    final symbol = switch (currency?.toUpperCase()) {
      'GHS' => 'GH₵',
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currency?.isNotEmpty == true ? '${currency!} ' : '',
    };
    return '$symbol${price!.toStringAsFixed(2)}';
  }

  static double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// A merchandising collection such as "New Arrivals", "Staff Picks" or
/// "Weekend Essentials". Collections are presentation rules, not inventory.
class RetailCollection {
  final String id;
  final String title;
  final String? subtitle;
  final List<RetailProduct> products;

  const RetailCollection({
    required this.id,
    required this.title,
    this.subtitle,
    this.products = const [],
  });
}

/// Retail's signature merchandising primitive: a physical-feeling collection
/// box rather than another generic storefront section.
class RetailCollectionBox extends StatelessWidget {
  final RetailCollection collection;
  final ValueChanged<RetailProduct> onProductTap;

  const RetailCollectionBox({
    super.key,
    required this.collection,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = collection.products.take(6).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (collection.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      collection.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (products.length > 1)
              Text(
                '${products.length} items',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return SizedBox(
                width: 168,
                child: RetailProductCard(
                  product: product,
                  onTap: () => onProductTap(product),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RetailProductCard extends StatelessWidget {
  final RetailProduct product;
  final VoidCallback onTap;

  const RetailProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product.imageUrls.isEmpty ? null : product.imageUrls.first;

    return Semantics(
      button: true,
      label: '${product.name}, ${product.formattedPrice}',
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: InkWell(
          onTap: product.available ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: MotionTokens.fast,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          key: ValueKey(imageUrl),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _RetailImageFallback(),
                        )
                      : const _RetailImageFallback(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.available ? product.formattedPrice : 'Currently unavailable',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: product.available
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet quick look. It deliberately receives an add-to-cart callback
/// from the host experience so cart ownership stays with the host/controller,
/// not inside a storefront widget or a second state-management system.
Future<void> showRetailQuickLook(
  BuildContext context, {
  required RetailProduct product,
  required ValueChanged<RetailProduct> onAddToCart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return RetailQuickLookSheet(
        product: product,
        onAddToCart: (item) {
          Navigator.of(sheetContext).pop();
          onAddToCart(item);
        },
      );
    },
  );
}

class RetailQuickLookSheet extends StatelessWidget {
  final RetailProduct product;
  final ValueChanged<RetailProduct> onAddToCart;

  const RetailQuickLookSheet({
    super.key,
    required this.product,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product.imageUrls.isEmpty ? null : product.imageUrls.first;

    return SafeArea(
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quick look',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1.2,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _RetailImageFallback(),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                product.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                product.formattedPrice,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (product.description?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text(
                  product.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (product.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: product.tags.take(6).map((tag) {
                    return Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: product.available ? () => onAddToCart(product) : null,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(product.available ? 'Add to bag' : 'Unavailable'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetailImageFallback extends StatelessWidget {
  const _RetailImageFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 34,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
