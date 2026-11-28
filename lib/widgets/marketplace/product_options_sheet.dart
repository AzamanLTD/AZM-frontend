// lib/widgets/marketplace/product_options_sheet.dart
// =============================================================================
// Choosing a product's options before it goes in the cart: one choice per
// variant group (Size…), up to the maximum per add-on group, with the price
// updating as you choose. Required groups must be chosen before "Add" is
// enabled — the same rule the server applies at checkout, so a configured
// product is never refused there for a missing option.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/product_options.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/marketplace/store_order_pay.dart'
    show storeUsdcLabel;

/// What the customer chose.
class ProductChoice {
  final double unitPrice;
  final Map<String, String> variants;
  final int quantity;

  const ProductChoice({
    required this.unitPrice,
    required this.variants,
    required this.quantity,
  });
}

class ProductOptionsSheet extends ConsumerStatefulWidget {
  final BusinessProduct product;

  const ProductOptionsSheet({super.key, required this.product});

  static Future<ProductChoice?> show(
    BuildContext context, {
    required BusinessProduct product,
  }) {
    return showModalBottomSheet<ProductChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductOptionsSheet(product: product),
    );
  }

  @override
  ConsumerState<ProductOptionsSheet> createState() =>
      _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends ConsumerState<ProductOptionsSheet> {
  final OptionSelection _selection = {};
  int _quantity = 1;

  List<ProductOptionGroup> get _groups => widget.product.optionGroups;

  void _toggle(ProductOptionGroup g, ProductOption o) {
    setState(() {
      final chosen = [...(_selection[g.name] ?? const <String>[])];
      if (g.single) {
        // A required single choice can be changed, not cleared.
        if (chosen.contains(o.name)) {
          if (!g.required) chosen.clear();
        } else {
          chosen
            ..clear()
            ..add(o.name);
        }
      } else if (chosen.contains(o.name)) {
        chosen.remove(o.name);
      } else if (chosen.length < g.maxSelection) {
        chosen.add(o.name);
      }
      _selection[g.name] = chosen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final unit = configuredUnitPrice(
      widget.product.priceUsdc,
      _groups,
      _selection,
    );
    final problem = optionSelectionProblem(_groups, _selection);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AzRadius.sheetTop,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.product.name,
                  style: AzText.titleL.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'From ${storeUsdcLabel(widget.product.priceUsdc)}',
                  style: AzText.bodyS.copyWith(color: colors.textSecondary),
                ),
                for (final g in _groups) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.name.toUpperCase(),
                          style: AzText.eyebrow.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        g.required
                            ? 'Required'
                            : (g.single
                                  ? 'Optional'
                                  : 'Up to ${g.maxSelection}'),
                        style: AzText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in g.options)
                        ChoiceChip(
                          key: ValueKey('option-${g.name}-${o.name}'),
                          selected: (_selection[g.name] ?? const []).contains(
                            o.name,
                          ),
                          onSelected: (_) => _toggle(g, o),
                          label: Text(
                            o.priceDelta == 0
                                ? o.name
                                : '${o.name} · ${o.priceDelta > 0 ? '+' : '−'}${storeUsdcLabel(o.priceDelta.abs())}',
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('option-qty-minus'),
                      onPressed: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Text(
                      '$_quantity',
                      style: AzText.title.copyWith(color: colors.textPrimary),
                    ),
                    IconButton(
                      key: const ValueKey('option-qty-plus'),
                      onPressed: _quantity < 99
                          ? () => setState(() => _quantity++)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('option-add'),
                        onPressed: problem == null
                            ? () => Navigator.of(context).pop(
                                ProductChoice(
                                  unitPrice: unit,
                                  variants: selectionAsVariants(_selection),
                                  quantity: _quantity,
                                ),
                              )
                            : null,
                        child: Text(
                          problem ??
                              'Add · ${storeUsdcLabel(double.parse((unit * _quantity).toStringAsFixed(6)))}',
                          style: AzText.button,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
