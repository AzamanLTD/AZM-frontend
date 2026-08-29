import 'dart:convert';

import 'retail_experience.dart';

class RetailCartLine {
  final RetailProduct product;
  final int quantity;
  final Map<String, String> variants;

  const RetailCartLine({
    required this.product,
    this.quantity = 1,
    this.variants = const {},
  });

  RetailCartLine copyWith({
    int? quantity,
    Map<String, String>? variants,
  }) {
    return RetailCartLine(
      product: product,
      quantity: quantity ?? this.quantity,
      variants: variants ?? this.variants,
    );
  }

  /// Stable line identity independent of variant insertion order.
  ///
  /// JSON encoding avoids delimiter collisions when merchants use option names
  /// or values containing `:` or `|` (the old hand-built key could merge two
  /// distinct selections into the same cart line).
  String get key {
    final sorted = variants.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonicalVariants = <String, String>{
      for (final entry in sorted) entry.key: entry.value,
    };
    return '${product.id}:${jsonEncode(canonicalVariants)}';
  }
}

/// UI cart state only. Server-authoritative totals, inventory and payment
/// authorization must be resolved by the checkout/order API.
class RetailCart {
  final List<RetailCartLine> lines;

  const RetailCart({this.lines = const []});

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  RetailCart add(
    RetailProduct product, {
    Map<String, String> variants = const {},
    int quantity = 1,
  }) {
    if (!product.available || quantity <= 0) return this;

    final candidate = RetailCartLine(
      product: product,
      quantity: quantity,
      variants: Map.unmodifiable(variants),
    );
    final existing = lines.indexWhere((line) => line.key == candidate.key);

    if (existing < 0) {
      return RetailCart(lines: [...lines, candidate]);
    }

    final updated = [...lines];
    updated[existing] = updated[existing].copyWith(
      quantity: updated[existing].quantity + quantity,
    );
    return RetailCart(lines: updated);
  }

  RetailCart setQuantity(String key, int quantity) {
    if (quantity <= 0) return remove(key);
    return RetailCart(
      lines: lines
          .map(
            (line) => line.key == key
                ? line.copyWith(quantity: quantity)
                : line,
          )
          .toList(growable: false),
    );
  }

  RetailCart remove(String key) {
    return RetailCart(
      lines: lines.where((line) => line.key != key).toList(growable: false),
    );
  }

  RetailCart clear() => const RetailCart();
}