import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

class _Gateway implements RetailCheckoutGateway {
  RetailCart? received;
  RetailCheckoutOptions? receivedOptions;
  final RetailCheckoutResult result;

  _Gateway(this.result);

  @override
  Future<RetailCheckoutResult> checkout(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
  }) async {
    received = cart;
    receivedOptions = options;
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
    expect(gateway.receivedOptions?.paymentProtection,
        RetailPaymentProtection.direct);
  });

  test('checkout preserves an idempotency key for the gateway', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));
    const key = 'retail-test-attempt-1';

    final result = await RetailCheckoutController(gateway).submit(
      cart,
      options: const RetailCheckoutOptions(idempotencyKey: key),
    );

    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.receivedOptions?.idempotencyKey, key);
  });

  test('escrow selection is rejected when the store does not offer it', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));
    final result = await RetailCheckoutController(gateway).submit(
      cart,
      options: const RetailCheckoutOptions(
        paymentProtection: RetailPaymentProtection.escrow,
      ),
    );

    expect(result, isA<RetailCheckoutFailure>());
    expect(gateway.received, isNull);
  });

  test('escrow selection is delegated when the store offers it', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));
    final result = await RetailCheckoutController(gateway).submit(
      cart,
      options: const RetailCheckoutOptions(
        escrowProtectionAvailable: true,
        paymentProtection: RetailPaymentProtection.escrow,
      ),
    );

    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.received, cart);
    expect(gateway.receivedOptions?.usesEscrow, isTrue);
  });
}