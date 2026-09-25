import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

class _Gateway implements RetailCheckoutGateway {
  RetailCart? received;
  RetailCheckoutOptions? receivedOptions;
  String? receivedIdempotencyKey;
  String? fundedEscrowId;
  String? fundedTotpToken;
  String? fundedPassword;
  final RetailCheckoutResult result;

  _Gateway(this.result);

  @override
  Future<RetailCheckoutResult> checkout(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    required String idempotencyKey,
  }) async {
    received = cart;
    receivedOptions = options;
    receivedIdempotencyKey = idempotencyKey;
    return result;
  }

  @override
  Future<void> fundEscrow(
    String escrowId, {
    String? totpToken,
    String? password,
  }) async {
    fundedEscrowId = escrowId;
    fundedTotpToken = totpToken;
    fundedPassword = password;
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

  test('checkout delegates cart and operation identity to authoritative gateway', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));

    final result = await RetailCheckoutController(gateway).submit(cart, idempotencyKey: 'checkout-1');

    expect(result, isA<RetailCheckoutSuccess>());
    expect(gateway.received?.itemCount, 1);
    expect(gateway.receivedOptions?.paymentProtection, RetailPaymentProtection.direct);
    expect(gateway.receivedIdempotencyKey, 'checkout-1');
  });

  test('escrow selection is rejected when the store does not offer it', () async {
    final cart = const RetailCart().add(product);
    final gateway = _Gateway(const RetailCheckoutSuccess(orderId: 'o1'));
    final result = await RetailCheckoutController(gateway).submit(
      cart,
      options: const RetailCheckoutOptions(paymentProtection: RetailPaymentProtection.escrow),
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
    final received = gateway.received;
    expect(received, isNotNull);
    expect(received!.itemCount, cart.itemCount);
    expect(received!.lines.single.key, cart.lines.single.key);
    expect(received!.lines.single.quantity, cart.lines.single.quantity);
    expect(received!.lines.single.product.id, cart.lines.single.product.id);
    expect(gateway.receivedOptions?.usesEscrow, isTrue);
  });
}
