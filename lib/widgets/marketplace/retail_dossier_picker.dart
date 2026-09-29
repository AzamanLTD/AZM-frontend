import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/experiences/retail/retail_variant_swatches.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/marketplace/retail_tray_commit.dart';

/// Interactive controls for a product dossier. The source stage remains the
/// presentation owner; cart mutation stays behind retailCommitToTray.
class RetailDossierPicker extends ConsumerStatefulWidget {
  final RetailProduct product;
  final String businessProfileId;
  final String businessName;

  const RetailDossierPicker({
    super.key,
    required this.product,
    required this.businessProfileId,
    required this.businessName,
  });

  @override
  ConsumerState<RetailDossierPicker> createState() =>
      _RetailDossierPickerState();
}

class _RetailDossierPickerState extends ConsumerState<RetailDossierPicker> {
  final Map<String, String> _selections = {};
  int _quantity = 1;

  bool get _allVariantsSelected =>
      widget.product.variants.keys.every(_selections.containsKey);

  List<String> _variantValues(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    final value = raw?.toString() ?? '';
    return value.isEmpty ? const <String>[] : <String>[value];
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((theme) => theme.colors));
    final hasVariants = widget.product.variants.isNotEmpty;
    final canAdd =
        widget.product.available &&
        (!hasVariants || _allVariantsSelected) &&
        _quantity > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in widget.product.variants.entries)
          RetailVariantSwatches(
            keyName: entry.key,
            values: _variantValues(entry.value),
            selected: _selections[entry.key],
            colors: colors,
            onSelected: (value) =>
                setState(() => _selections[entry.key] = value),
          ),
        if (hasVariants) const SizedBox(height: AzSpace.sm),
        Row(
          children: [
            Text(
              'Quantity',
              style: AzText.label.copyWith(color: colors.textSecondary),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Decrease quantity',
              onPressed: _quantity > 1
                  ? () => setState(() => _quantity--)
                  : null,
              icon: Icon(
                HugeIconsStroke.minusSign,
                size: 18,
                color: _quantity > 1 ? colors.textSecondary : colors.divider,
              ),
            ),
            AnimatedSwitcher(
              duration: MotionTokens.microInteraction,
              child: Text(
                '$_quantity',
                key: ValueKey<int>(_quantity),
                style: AzText.title.copyWith(color: colors.textPrimary),
              ),
            ),
            IconButton(
              tooltip: 'Increase quantity',
              onPressed: () => setState(() => _quantity++),
              icon: Icon(
                HugeIconsStroke.plusSign,
                size: 18,
                color: colors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AzSpace.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canAdd
                ? () async {
                    final added = await retailCommitToTray(
                      context,
                      ref,
                      businessProfileId: widget.businessProfileId,
                      businessName: widget.businessName,
                      product: widget.product,
                      variants: Map<String, String>.unmodifiable(_selections),
                      quantity: _quantity,
                    );
                    if (added && context.mounted) Navigator.of(context).pop();
                  }
                : null,
            icon: const Icon(HugeIconsStroke.shoppingBag01, size: 18),
            label: Text(
              widget.product.available ? 'Add to bag' : 'Unavailable',
            ),
          ),
        ),
      ],
    );
  }
}
