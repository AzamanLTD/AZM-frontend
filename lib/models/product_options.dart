// lib/models/product_options.dart
// =============================================================================
// A store product's options: its variant groups (one choice each, e.g. Size)
// and its modifier groups (add-ons, up to a maximum each). This mirrors the
// backend exactly (services/storefrontProductConfigurationService.js), which
// validates the choice and prices it at checkout:
//   • variants: a flat list of options is one required "Size" group; a list
//     of groups is required unless `required: false`; a map {group: [options]}
//     is required groups;
//   • modifier groups: optional unless `required: true`; at most
//     maxSelection (or max, at least 1) choices;
//   • an option's name is its name, label or value; its price is priceDelta;
//   • the unit price is the base price plus the chosen options' priceDelta.
// The cart sends the choice as {group: name} (several modifier choices
// comma-joined), which the backend reads.
// =============================================================================

import 'dart:convert';

class ProductOption {
  final String name;
  final double priceDelta;

  const ProductOption({required this.name, this.priceDelta = 0});
}

class ProductOptionGroup {
  final String name;
  final bool required;

  /// 1 for a variant group (one choice); the modifier group's maximum.
  final int maxSelection;

  /// A variant group: exactly one choice when required.
  final bool isVariant;
  final List<ProductOption> options;

  const ProductOptionGroup({
    required this.name,
    required this.required,
    required this.maxSelection,
    required this.isVariant,
    required this.options,
  });

  bool get single => isVariant || maxSelection == 1;
}

double _num(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

String _optionName(Object? o) {
  if (o is Map) {
    return '${o['name'] ?? o['label'] ?? o['value'] ?? ''}'.trim();
  }
  return '${o ?? ''}'.trim();
}

List<ProductOption> _options(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map(
        (o) => ProductOption(
          name: _optionName(o),
          priceDelta: o is Map ? _num(o['priceDelta']) : 0,
        ),
      )
      .where((o) => o.name.isNotEmpty)
      .toList();
}

List<ProductOptionGroup> _variantGroups(Object? raw) {
  if (raw is List) {
    final objects = raw.whereType<Map>().toList();
    final flat =
        objects.isNotEmpty &&
        objects.every((e) => e['options'] is! List && e['values'] is! List);
    if (flat) {
      return [
        ProductOptionGroup(
          name: 'Size',
          required: true,
          maxSelection: 1,
          isVariant: true,
          options: _options(raw),
        ),
      ];
    }
    final groups = <ProductOptionGroup>[];
    for (var i = 0; i < raw.length; i++) {
      final g = raw[i];
      final name =
          '${(g is Map ? (g['name'] ?? g['id']) : null) ?? 'Variant ${i + 1}'}'
              .trim();
      if (name.isEmpty) continue;
      groups.add(
        ProductOptionGroup(
          name: name,
          required: !(g is Map && g['required'] == false),
          maxSelection: 1,
          isVariant: true,
          options: _options(g is Map ? (g['options'] ?? g['values']) : null),
        ),
      );
    }
    return groups;
  }
  if (raw is Map) {
    return raw.entries
        .map(
          (e) => ProductOptionGroup(
            name: '${e.key}'.trim(),
            required: true,
            maxSelection: 1,
            isVariant: true,
            options: _options(e.value),
          ),
        )
        .where((g) => g.name.isNotEmpty)
        .toList();
  }
  return const [];
}

List<ProductOptionGroup> _modifierGroups(Object? raw) {
  if (raw is! List) return const [];
  final groups = <ProductOptionGroup>[];
  for (var i = 0; i < raw.length; i++) {
    final g = raw[i];
    final name =
        '${(g is Map ? (g['name'] ?? g['id']) : null) ?? 'Options ${i + 1}'}'
            .trim();
    if (name.isEmpty) continue;
    final max = g is Map ? _num(g['maxSelection'] ?? g['max'] ?? 1).floor() : 1;
    groups.add(
      ProductOptionGroup(
        name: name,
        required: g is Map && g['required'] == true,
        maxSelection: max < 1 ? 1 : max,
        isVariant: false,
        options: _options(g is Map ? (g['options'] ?? g['values']) : null),
      ),
    );
  }
  return groups;
}

/// A product's option groups from its `variants` and `modifierGroups`
/// (either may arrive as JSON text). Variant groups come first.
List<ProductOptionGroup> parseProductOptions(
  Object? variants,
  Object? modifierGroups,
) {
  Object? decode(Object? v) {
    if (v is String && v.trim().isNotEmpty) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    return v;
  }

  return [
    ..._variantGroups(decode(variants)),
    ..._modifierGroups(decode(modifierGroups)),
  ].where((g) => g.options.isNotEmpty).toList();
}

/// The choice: group name → chosen option names.
typedef OptionSelection = Map<String, List<String>>;

/// Why the choice can't be added yet (the backend's own rule), or null.
String? optionSelectionProblem(
  List<ProductOptionGroup> groups,
  OptionSelection selection,
) {
  for (final g in groups) {
    final chosen = selection[g.name] ?? const [];
    if (g.required && chosen.isEmpty) return 'Choose ${g.name}.';
    if (chosen.length > (g.single ? 1 : g.maxSelection)) {
      return g.single
          ? 'Choose one ${g.name}.'
          : '${g.name}: at most ${g.maxSelection}.';
    }
  }
  return null;
}

/// Base price plus the chosen options' price, as the backend charges it.
double configuredUnitPrice(
  double base,
  List<ProductOptionGroup> groups,
  OptionSelection selection,
) {
  var total = base;
  for (final g in groups) {
    final chosen = (selection[g.name] ?? const []).toSet();
    for (final o in g.options) {
      if (chosen.contains(o.name)) {
        total += o.priceDelta;
        if (g.single) break;
      }
    }
  }
  return double.parse(total.toStringAsFixed(6));
}

/// The cart's form of the choice: {group: name}, several names comma-joined
/// (sorted, so the same choice is the same cart line).
Map<String, String> selectionAsVariants(OptionSelection selection) {
  final out = <String, String>{};
  for (final e in selection.entries) {
    if (e.value.isEmpty) continue;
    final names = [...e.value]..sort();
    out[e.key] = names.join(',');
  }
  return out;
}
