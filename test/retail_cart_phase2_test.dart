import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

void main() {
  const product = RetailProduct(id: 'p1', name: 'Tee', price: 50, currency: 'GHS');

  test('adds requested quantity as one line', () {
    final cart = const RetailCart().add(product, quantity: 3);
    expect(cart.itemCount, 3);
    expect(cart.lines, hasLength(1));
    expect(cart.lines.single.quantity, 3);
  });

  test('keeps variants as separate cart lines', () {
    final cart = const RetailCart()
        .add(product, variantKey: 'size', variantValue: 'M', quantity: 2)
        .add(product, variantKey: 'size', variantValue: 'L', quantity: 1);
    expect(cart.itemCount, 3);
    expect(cart.lines, hasLength(2));
    expect(cart.lines[0].quantity, 2);
    expect(cart.lines[1].variantValue, 'L');
  });

  test('rejects unavailable products', () {
    const unavailable = RetailProduct(id: 'p2', name: 'Sold out', available: false);
    final cart = const RetailCart().add(unavailable);
    expect(cart.lines, isEmpty);
  });

  test('zero quantity removes a line', () {
    final cart = const RetailCart().add(product, quantity: 2);
    final updated = cart.setQuantity(cart.lines.single.key, 0);
    expect(updated.lines, isEmpty);
  });
}
