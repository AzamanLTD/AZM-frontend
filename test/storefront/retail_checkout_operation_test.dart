import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';

class _RecordingGateway implements RetailCheckoutGateway {
  final List<String> keys = [];
  final List<RetailCart> carts = [];
  final List<String> fundedEscrowIds = [];

  @override
  Future<RetailCheckoutResult> checkout(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    carts.add(cart);
    return const RetailCheckoutSuccess(orderId: 'order-1');
  }

  @override
  Future<void> fundEscrow(
    String escrowId, {
    String? totpToken,
    String? password,
  }) async {
    fundedEscrowIds.add(escrowId);
  }
}

RetailCart _cart() {
  return RetailCart(
    lines: [
      RetailCartLine(
        product: const RetailProduct(
          id: 'product-1',
          name: 'Test product',
          price: 10,
          currency: 'GHS',
        ),
        quantity: 2,
      ),
    ],
  );
}

void main() {
  test('checkout operation keeps one idempotency key across retries', () async {
    final gateway = _RecordingGateway();
    final controller = RetailCheckoutController(gateway);
    final operation = controller.begin(_cart());

    await operation.submit();
    await operation.submit();

    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[0], operation.idempotencyKey);
    expect(gateway.keys[1], operation.idempotencyKey);
  });

  test('operation freezes the cart intent at creation', () {
    final gateway = _RecordingGateway();
    final controller = RetailCheckoutController(gateway);
    final variants = <String, String>{'size': 'M'};
    final sourceLines = <RetailCartLine>[
      RetailCartLine(
        product: const RetailProduct(
          id: 'product-1',
          name: 'Test product',
        ),
        quantity: 2,
        variants: variants,
      ),
    ];
    final sourceCart = RetailCart(lines: sourceLines);
    final operation = controller.begin(sourceCart);

    sourceLines.clear();
    variants['size'] = 'XL';

    expect(operation.cart.itemCount, 2);
    expect(operation.cart.lines.single.variants['size'], 'M');
  });

  test('a new cart requires a new operation identity', () {
    final controller = RetailCheckoutController(_RecordingGateway());

    final first = controller.begin(_cart());
    final changedCart = _cart().setQuantity(first.cart.lines.single.key, 1);
    final second = controller.begin(changedCart);

    expect(second.idempotencyKey, isNot(first.idempotencyKey));
    expect(first.cart.itemCount, 2);
    expect(second.cart.itemCount, 1);
  });

  test('explicit idempotency key is preserved', () {
    final controller = RetailCheckoutController(_RecordingGateway());
    final operation = controller.begin(_cart(), idempotencyKey: 'checkout-123');

    expect(operation.idempotencyKey, 'checkout-123');
  });

  test('empty cart cannot begin an operation', () {
    final controller = RetailCheckoutController(_RecordingGateway());

    expect(
      () => controller.begin(const RetailCart()),
      throwsStateError,
    );
  });
}
