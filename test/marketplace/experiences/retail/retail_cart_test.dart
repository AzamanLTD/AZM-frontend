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

  test('different single variants remain separate cart lines', () {
    final cart = const RetailCart()
        .add(product, variants: {'size': 'M'})
        .add(product, variants: {'size': 'L'});

    expect(cart.lines, hasLength(2));
    expect(cart.lines[0].variants, {'size': 'M'});
    expect(cart.lines[1].variants, {'size': 'L'});
  });

  test('multiple variant dimensions remain one deterministic line identity', () {
    final first = const RetailCart().add(
      product,
      variants: {'color': 'Black', 'size': 'M'},
    );
    final sameSelectionDifferentOrder = first.add(
      product,
      variants: {'size': 'M', 'color': 'Black'},
    );
    final differentSelection = sameSelectionDifferentOrder.add(
      product,
      variants: {'color': 'Black', 'size': 'L'},
    );

    expect(sameSelectionDifferentOrder.lines, hasLength(1));
    expect(sameSelectionDifferentOrder.itemCount, 2);
    expect(differentSelection.lines, hasLength(2));
  });

  test('variant values containing delimiters cannot collide', () {
    final first = const RetailCart().add(
      product,
      variants: {'finish': 'matte|blue'},
    );
    final second = first.add(
      product,
      variants: {'finish': 'matte', 'blue': ''},
    );

    expect(second.lines, hasLength(2));
  });

  test('zero quantity removes a line', () {
    final cart = const RetailCart().add(product);
    final key = cart.lines.single.key;

    expect(cart.setQuantity(key, 0).lines, isEmpty);
  });
}