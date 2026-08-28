import 'package:flutter/material.dart';

import 'retail_cart.dart';

class RetailCartSheet extends StatelessWidget {
  final RetailCart cart;
  final ValueChanged<RetailCart> onChanged;
  final VoidCallback onCheckout;

  const RetailCartSheet({
    super.key,
    required this.cart,
    required this.onChanged,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * .82;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your bag',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: cart.lines.isEmpty
                        ? Center(
                            child: Text(
                              'Your bag is empty',
                              style: theme.textTheme.bodyLarge,
                            ),
                          )
                        : ListView.separated(
                            itemCount: cart.lines.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final line = cart.lines[index];
                              final variantText = line.variants.entries
                                  .map((entry) => '${entry.key}: ${entry.value}')
                                  .join(' · ');
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  line.product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    line.product.formattedPrice,
                                    if (variantText.isNotEmpty) variantText,
                                  ].join(' · '),
                                ),
                                leading: _ProductThumbnail(product: line.product),
                                trailing: _QuantityControls(
                                  quantity: line.quantity,
                                  onDecrease: () => onChanged(
                                    cart.setQuantity(line.key, line.quantity - 1),
                                  ),
                                  onIncrease: () => onChanged(
                                    cart.setQuantity(line.key, line.quantity + 1),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: cart.lines.isEmpty ? null : onCheckout,
                      child: const Text('Continue to checkout'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final RetailProduct product;

  const _ProductThumbnail({required this.product});

  @override
  Widget build(BuildContext context) {
    final image = product.imageUrls.isEmpty ? null : product.imageUrls.first;
    return SizedBox(
      width: 52,
      height: 52,
      child: image == null
          ? const Icon(Icons.shopping_bag_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.shopping_bag_outlined),
              ),
            ),
    );
  }
}

class _QuantityControls extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _QuantityControls({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Decrease quantity',
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$quantity', style: Theme.of(context).textTheme.labelLarge),
          IconButton(
            tooltip: 'Increase quantity',
            onPressed: onIncrease,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

Future<void> showRetailCartSheet(
  BuildContext context, {
  required RetailCart cart,
  required ValueChanged<RetailCart> onChanged,
  required VoidCallback onCheckout,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RetailCartSheet(
      cart: cart,
      onChanged: onChanged,
      onCheckout: onCheckout,
    ),
  );
}
