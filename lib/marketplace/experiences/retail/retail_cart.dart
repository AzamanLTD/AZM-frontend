import 'retail_experience.dart';

class RetailCartLine {
  final RetailProduct product;
  final int quantity;
  final String? variantKey;
  final String? variantValue;

  const RetailCartLine({
    required this.product,
    this.quantity = 1,
    this.variantKey,
    this.variantValue,
  });

  RetailCartLine copyWith({int? quantity, String? variantKey, String? variantValue}) => RetailCartLine(
        product: product,
        quantity: quantity ?? this.quantity,
        variantKey: variantKey ?? this.variantKey,
        variantValue: variantValue ?? this.variantValue,
      );

  String get key => '${product.id}:${variantKey ?? ''}:${variantValue ?? ''}';
}

/// UI cart state only. Server-authoritative totals, inventory and payment
/// authorization must be resolved by the checkout/order API.
class RetailCart {
  final List<RetailCartLine> lines;

  const RetailCart({this.lines = const []});

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  RetailCart add(
    RetailProduct product, {
    String? variantKey,
    String? variantValue,
    int quantity = 1,
  }) {
    if (!product.available || quantity <= 0) return this;
    final key = '${product.id}:${variantKey ?? ''}:${variantValue ?? ''}';
    final existing = lines.indexWhere((line) => line.key == key);
    if (existing < 0) {
      return RetailCart(
        lines: [
          ...lines,
          RetailCartLine(
            product: product,
            quantity: quantity,
            variantKey: variantKey,
            variantValue: variantValue,
          ),
        ],
      );
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
          .map((line) => line.key == key ? line.copyWith(quantity: quantity) : line)
          .toList(growable: false),
    );
  }

  RetailCart remove(String key) => RetailCart(
        lines: lines.where((line) => line.key != key).toList(growable: false),
      );

  RetailCart clear() => const RetailCart();
}
