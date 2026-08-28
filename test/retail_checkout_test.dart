import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

class _Gateway implements RetailCheckoutGateway {
  RetailCart? received;

  @override
  Future<RetailCheckoutResult> checkout(RetailCart cart) async {
    received = cart;
    return const RetailCheckoutSuccess(orderId: 'order-1');
  }
}

void main() {
  const product = RetailProduct(id: 'p1', name: 'T-shirt');

  test('empty carts are rejected before reaching gateway', () async {
    final gateway = _Gateway();
    final result = await RetailCheckoutController(gateway).submit(const RetailCart());

    expect(result, isA<RetailCheckoutFailure>());
    expect(gateway.received, isNull);
  });

  test('non-empty cart is delegated unchanged to gateway', () async {
    final gateway = _Gateway();
    final cart = const RetailCart().add(product, variantKey: 'size', variantValue: 'M', quantity: 2);

    final result = await RetailCheckoutController(gateway).submit(cart);

    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.received, same(cart));
  });
}
