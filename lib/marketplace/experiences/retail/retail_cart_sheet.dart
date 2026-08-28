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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('Your bag', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    Text('${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}', style: theme.textTheme.labelMedium),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: cart.lines.isEmpty
                        ? Center(child: Text('Your bag is empty', style: theme.textTheme.bodyLarge))
                        : ListView.separated(
                            itemCount: cart.lines.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final line = cart.lines[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(line.product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text([
                                  line.product.formattedPrice,
                                  if (line.variantValue?.isNotEmpty == true) '${line.variantKey}: ${line.variantValue}',
                                ].join(' · ')),
                                leading: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: line.product.imageUrls.isEmpty
                                      ? const Icon(Icons.shopping_bag_outlined)
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(
                                            line.product.imageUrls.first,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_outlined),
                                          ),
                                        ),
                                ),
                                trailing: SizedBox(
                                  width: 112,
                                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                    IconButton(
                                      tooltip: 'Decrease quantity',
                                      onPressed: () => onChanged(cart.setQuantity(line.key, line.quantity - 1)),
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                    Text('${line.quantity}', style: theme.textTheme.labelLarge),
                                    IconButton(
                                      tooltip: 'Increase quantity',
                                      onPressed: () => onChanged(cart.setQuantity(line.key, line.quantity + 1)),
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ]),
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
