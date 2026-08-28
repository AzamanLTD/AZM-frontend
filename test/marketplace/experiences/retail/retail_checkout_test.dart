import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

class _Gateway implements RetailCheckoutGateway {
  RetailCart? received;
  final RetailCheckoutResult result;

  _Gateway(this.result);

  @override
  Future<RetailCheckoutResult> checkout(RetailCart cart) async {
    received = cart;
    return result;
  }
}

void main() {
  const product = RetailProduct(id: 'p1', name: 'Bag', price: 20, currency: 'GHS');

  test('empty cart does not call gateway', () async {
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));
    final result = await RetailCheckoutController(gateway).submit(const RetailCart());

    expect(result, isA<RetailCheckoutFailure>());
    expect(gateway.received, isNull);
  });

  test('checkout delegates cart to authoritative gateway', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));

    final result = await RetailCheckoutController(gateway).submit(cart);

    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.received?.itemCount, 1);
  });
}
