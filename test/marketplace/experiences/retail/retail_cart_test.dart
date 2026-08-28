import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

void main() {
  const product = RetailProduct(
    id: 'p1',
    name: 'T-shirt',
    price: 50,
    currency: 'GHS',
  );

  test('adding the same product increments quantity', () {
    final cart = const RetailCart().add(product).add(product);

    expect(cart.itemCount, 2);
    expect(cart.lines, hasLength(1));
    expect(cart.lines.single.quantity, 2);
  });

  test('variants remain separate cart lines', () {
    final cart = const RetailCart()
        .add(product, variantKey: 'size', variantValue: 'M')
        .add(product, variantKey: 'size', variantValue: 'L');

    expect(cart.itemCount, 2);
    expect(cart.lines, hasLength(2));
  });

  test('zero quantity removes a line', () {
    final cart = const RetailCart().add(product);
    final key = cart.lines.single.key;

    expect(cart.setQuantity(key, 0).lines, isEmpty);
  });
}
