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
  const product = RetailProduct(id: 'p1', name: 'Tee', price: 50, currency: 'GHS');

  test('does not call gateway for an empty cart', () async {
    final gateway = _Gateway();
    final result = await RetailCheckoutController(gateway).submit(const RetailCart());
    expect(result, isA<RetailCheckoutFailure>());
    expect(gateway.received, isNull);
  });

  test('passes the cart unchanged to the authoritative gateway', () async {
    final gateway = _Gateway();
    final cart = const RetailCart().add(product, variantKey: 'size', variantValue: 'M', quantity: 2);
    final result = await RetailCheckoutController(gateway).submit(cart);
    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.received?.lines.single.key, cart.lines.single.key);
    expect(gateway.received?.lines.single.quantity, 2);
  });
}
