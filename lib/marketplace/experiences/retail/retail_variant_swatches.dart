// =============================================================================
// RETAIL VARIANT SWATCHES — colour circles and size pills, never dropdowns.
//
// Shared by the quick-look sheet and the stage's productDossier (TASK-012).
// A variant group renders as colour swatches when its KEY names a colour or
// any value is a hex colour; everything else renders as pills. Detection is
// pure and unit-tested — see test/retail_shelf_test.dart.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

final RegExp kRetailHexColourPattern = RegExp(r'^#?[0-9a-fA-F]{6}$');
final RegExp kRetailHexColourShortPattern = RegExp(r'^#?[0-9a-fA-F]{3}$');

bool retailSwatchIsColourValue(String value) =>
    kRetailHexColourPattern.hasMatch(value) ||
    kRetailHexColourShortPattern.hasMatch(value);

bool retailSwatchKeyIsColour(String key) {
  final k = key.toLowerCase();
  return k.contains('colour') || k.contains('color');
}

/// A group is a colour group when its key names a colour or any value is a
/// hex colour (a backend may name the group "Finish" but send hexes).
bool retailSwatchGroupIsColour(String key, List<String> values) =>
    retailSwatchKeyIsColour(key) || values.any(retailSwatchIsColourValue);

/// Parses `#abc` → `0xFFAABBCC` and `F94144` → `0xFFF94144`; null for
/// anything that is not a colour.
Color? retailSwatchColour(String value) {
  final v = value.trim();
  if (!retailSwatchIsColourValue(v)) return null;
  final hex = v.startsWith('#') ? v.substring(1) : v;
  if (hex.length == 3) {
    return Color(
      int.parse(
        'FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}',
        radix: 16,
      ),
    );
  }
  return Color(int.parse('FF$hex', radix: 16));
}

class RetailVariantSwatches extends StatelessWidget {
  final String keyName;
  final List<String> values;
  final String? selected;
  final AzamanColors colors;
  final ValueChanged<String> onSelected;

  const RetailVariantSwatches({
    super.key,
    required this.keyName,
    required this.values,
    required this.selected,
    required this.colors,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isColour = retailSwatchGroupIsColour(keyName, values);
    return Padding(
      padding: const EdgeInsets.only(bottom: AzSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keyName,
            style: AzText.label.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AzSpace.xs),
          Wrap(
            spacing: AzSpace.xs,
            runSpacing: AzSpace.xs,
            children: [
              for (final value in values)
                isColour
                    ? _ColourSwatch(
                        value: value,
                        isSelected: value == selected,
                        colors: colors,
                        onTap: () => onSelected(value),
                      )
                    : _PillSwatch(
                        value: value,
                        isSelected: value == selected,
                        colors: colors,
                        onTap: () => onSelected(value),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The selected state is an inner contrast ring — deliberately no check
/// glyph, because no Hugeicons checkmark is verified in-repo (F-035).
class _ColourSwatch extends StatelessWidget {
  final String value;
  final bool isSelected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _ColourSwatch({
    required this.value,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = retailSwatchColour(value) ?? colors.textTertiary;
    final ringColour = swatch.computeLuminance() > 0.5
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.9);
    return Semantics(
      button: true,
      selected: isSelected,
      label: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AzamanHaptics.selection();
          onTap();
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: swatch,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? colors.accent : colors.divider,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: swatch.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: isSelected
              ? Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColour, width: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _PillSwatch extends StatelessWidget {
  final String value;
  final bool isSelected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _PillSwatch({
    required this.value,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AzamanHaptics.selection();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AzSpace.md,
            vertical: AzSpace.xs,
          ),
          decoration: BoxDecoration(
            color: isSelected ? colors.accentSurface : colors.softSurface,
            borderRadius: AzRadius.brPill,
            border: Border.all(
              color: isSelected ? colors.accent : colors.divider,
            ),
          ),
          child: Text(
            value,
            style: AzText.label.copyWith(
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
