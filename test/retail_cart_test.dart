import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

void main() {
  const product = RetailProduct(id: 'p1', name: 'T-shirt', price: 100, currency: 'GHS');
  const other = RetailProduct(id: 'p2', name: 'Cap', price: 50, currency: 'GHS');

  test('add combines identical product lines and preserves quantity', () {
    final cart = const RetailCart().add(product).add(product, quantity: 2);
    expect(cart.lines, hasLength(1));
    expect(cart.lines.single.quantity, 3);
    expect(cart.itemCount, 3);
  });

  test('different variants remain separate lines', () {
    final cart = const RetailCart()
        .add(product, variantKey: 'size', variantValue: 'M', quantity: 2)
        .add(product, variantKey: 'size', variantValue: 'L');

    expect(cart.lines, hasLength(2));
    expect(cart.lines[0].quantity, 2);
    expect(cart.lines[0].variantValue, 'M');
    expect(cart.lines[1].variantValue, 'L');
  });

  test('setQuantity removes a line at zero', () {
    final cart = const RetailCart().add(product).add(other);
    final updated = cart.setQuantity(cart.lines.first.key, 0);
    expect(updated.lines, hasLength(1));
    expect(updated.lines.single.product.id, 'p2');
  });

  test('unavailable products and invalid quantities are not added', () {
    const unavailable = RetailProduct(id: 'p3', name: 'Sold out', available: false);
    final cart = const RetailCart()
        .add(unavailable)
        .add(product, quantity: 0)
        .add(product, quantity: -1);
    expect(cart.lines, isEmpty);
  });
}
