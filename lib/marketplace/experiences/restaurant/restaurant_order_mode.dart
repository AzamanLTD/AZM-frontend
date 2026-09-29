// =============================================================================
// RESTAURANT ORDER MODE — the three ways an order leaves a restaurant journey.
// =============================================================================

import 'package:flutter/material.dart';

/// How the customer takes their order.
///
/// [cartNote] is written to the cart line when the order lands in the tray,
/// so the checkout can show how it will be fulfilled.
enum RestaurantOrderMode {
  dineIn('Dine-in', Icons.table_restaurant_rounded, null),
  takeaway('Takeaway', Icons.takeout_dining_rounded, null),
  delivery('Delivery', Icons.delivery_dining_rounded, 'Delivery');

  const RestaurantOrderMode(this.label, this.icon, this.cartNote);

  /// Customer-facing segment label.
  final String label;

  /// Segment glyph. Stock Material icons — no Hugeicons restaurant glyph is
  /// verified in-repo (F-035).
  final IconData icon;

  /// Written to the cart line's `notes` when committed in this mode.
  final String? cartNote;
}

/// Build-progress fraction for a dish's required choices.
///
/// `hasVariants` counts as one required step (choose a size). Every entry of
/// [requiredGroupsSatisfied] is one required option group. A dish with no
/// required choices is complete by definition.
double restaurantBuildProgress({
  required bool hasVariants,
  required bool sizeChosen,
  required List<bool> requiredGroupsSatisfied,
}) {
  final total = (hasVariants ? 1 : 0) + requiredGroupsSatisfied.length;
  if (total == 0) return 1;
  final done = (hasVariants && sizeChosen ? 1 : 0) +
      requiredGroupsSatisfied.where((satisfied) => satisfied).length;
  return done / total;
}
