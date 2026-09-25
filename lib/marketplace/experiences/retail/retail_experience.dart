import 'package:flutter/material.dart';

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
    final images = json['imageUrls'] ?? json['images'];
    final tags = json['tags'];
    final variants = json['variants'];
    return RetailProduct(
      id: (json['id'] ?? json['productId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Product').toString(),
      description: json['description']?.toString(),
      price: _toDouble(json['price'] ?? json['priceUsdc']),
      currency: json['currency']?.toString(),
      imageUrls: images is List
          ? images.map((v) => v.toString()).where((v) => v.isNotEmpty).toList()
          : const [],
      tags: tags is List
          ? tags.map((v) => v.toString()).where((v) => v.isNotEmpty).toList()
          : const [],
      variants: variants is Map
          ? Map<String, dynamic>.from(variants)
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

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

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
            itemBuilder: (context, index) => SizedBox(
              width: 168,
              child: RetailProductCard(
                product: products[index],
                onTap: () => onProductTap(products[index]),
              ),
            ),
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
    final image = product.imageUrls.isEmpty ? null : product.imageUrls.first;
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
                child: image == null
                    ? const _RetailImageFallback()
                    : Image.network(
                        image,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _RetailImageFallback(),
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
                      product.available
                          ? product.formattedPrice
                          : 'Currently unavailable',
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

Future<void> showRetailQuickLook(
  BuildContext context, {
  required RetailProduct product,
  required ValueChanged<RetailCartSelection> onAddToCart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => RetailQuickLookSheet(
      product: product,
      onAddToCart: (selection) {
        Navigator.of(sheetContext).pop();
        onAddToCart(selection);
      },
    ),
  );
}

class RetailCartSelection {
  final RetailProduct product;
  final Map<String, String> variants;
  final int quantity;

  const RetailCartSelection({
    required this.product,
    this.variants = const {},
    this.quantity = 1,
  });
}

class RetailQuickLookSheet extends StatefulWidget {
  final RetailProduct product;
  final ValueChanged<RetailCartSelection> onAddToCart;

  const RetailQuickLookSheet({
    super.key,
    required this.product,
    required this.onAddToCart,
  });

  @override
  State<RetailQuickLookSheet> createState() => _RetailQuickLookSheetState();
}

class _RetailQuickLookSheetState extends State<RetailQuickLookSheet> {
  final Map<String, String> _selections = {};
  int _quantity = 1;

  bool get _allVariantsSelected =>
      widget.product.variants.keys.every(_selections.containsKey);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = widget.product.imageUrls.isEmpty
        ? null
        : widget.product.imageUrls.first;
    final variants = widget.product.variants;

    return SafeArea(
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: SingleChildScrollView(
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
                if (image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1.2,
                      child: Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _RetailImageFallback(),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  widget.product.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.product.formattedPrice,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.product.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.product.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (variants.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...variants.entries.map(_variantField),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Quantity', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Decrease quantity',
                      onPressed: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$_quantity', style: theme.textTheme.titleMedium),
                    IconButton(
                      tooltip: 'Increase quantity',
                      onPressed: () => setState(() => _quantity++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.product.available && _allVariantsSelected
                        ? () => widget.onAddToCart(
                              RetailCartSelection(
                                product: widget.product,
                                variants: Map.unmodifiable(_selections),
                                quantity: _quantity,
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(
                      widget.product.available ? 'Add to bag' : 'Unavailable',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _variantField(MapEntry<String, dynamic> entry) {
    final values = entry.value is List
        ? (entry.value as List)
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList()
        : [entry.value.toString()];
    if (values.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: _selections[entry.key],
        decoration: InputDecoration(
          labelText: entry.key,
          border: const OutlineInputBorder(),
        ),
        items: values
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => setState(() {
          if (value == null) {
            _selections.remove(entry.key);
          } else {
            _selections[entry.key] = value;
          }
        }),
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
