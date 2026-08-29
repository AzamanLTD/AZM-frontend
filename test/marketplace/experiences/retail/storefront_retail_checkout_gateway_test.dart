import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/experiences/retail/storefront_retail_checkout_gateway.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

class _CapturingStorefrontService extends StorefrontService {
  String? receivedBusinessProfileId;
  List<Map<String, dynamic>>? receivedItems;
  String? receivedPaymentMode;
  String? receivedIdempotencyKey;

  Map<String, dynamic> response = {
    'order': {
      'id': 'order-123',
      'orderRef': 'ORD-001',
      'status': 'AWAITING_PAYMENT',
    },
  };

  @override
  Future<Map<String, dynamic>> checkoutCart({
    required String businessProfileId,
    required List<Map<String, dynamic>> items,
    String? customerNotes,
    String? deliveryNotes,
    String? idempotencyKey,
    String paymentMode = 'DIRECT',
  }) async {
    receivedBusinessProfileId = businessProfileId;
    receivedItems = items;
    receivedPaymentMode = paymentMode;
    receivedIdempotencyKey = idempotencyKey;
    return response;
  }
}

void main() {
  const product = RetailProduct(
    id: 'p1',
    name: 'Bag',
    price: 20,
    currency: 'GHS',
  );

  _CapturingStorefrontService buildService() => _CapturingStorefrontService();

  StorefrontRetailCheckoutGateway buildGateway(
    _CapturingStorefrontService service,
  ) {
    return StorefrontRetailCheckoutGateway(
      businessProfileId: 'biz-001',
      storefrontService: service,
    );
  }

  test('maps direct protection and idempotency key', () async {
    final service = buildService();
    final gateway = buildGateway(service);

    await gateway.checkout(
      const RetailCart().add(product),
      options: const RetailCheckoutOptions(
        idempotencyKey: 'attempt-1',
        paymentProtection: RetailPaymentProtection.direct,
      ),
    );

    expect(service.receivedPaymentMode, 'DIRECT');
    expect(service.receivedIdempotencyKey, 'attempt-1');
  });

  test('maps escrow protection to the backend payment mode', () async {
    final service = buildService();
    final gateway = buildGateway(service);

    await gateway.checkout(
      const RetailCart().add(product),
      options: const RetailCheckoutOptions(
        escrowProtectionAvailable: true,
        paymentProtection: RetailPaymentProtection.escrow,
      ),
    );

    expect(service.receivedPaymentMode, 'ESCROW');
  });

  test('serializes selected variants alongside product and quantity', () async {
    final service = buildService();
    final gateway = buildGateway(service);

    await gateway.checkout(
      const RetailCart().add(
        product,
        quantity: 2,
        variants: {'Size': 'Large', 'Color': 'Black'},
      ),
    );

    expect(service.receivedItems, hasLength(1));
    expect(service.receivedItems!.single['productId'], 'p1');
    expect(service.receivedItems!.single['quantity'], 2);
    expect(service.receivedItems!.single['variants'], {
      'Size': 'Large',
      'Color': 'Black',
    });
  });

  test('successful response produces RetailCheckoutSuccess', () async {
    final service = buildService();
    final gateway = buildGateway(service);

    final result = await gateway.checkout(const RetailCart().add(product));

    expect(result, isA<RetailCheckoutSuccess>());
    final success = result as RetailCheckoutSuccess;
    expect(success.orderId, 'order-123');
    expect(success.trackingStatus, 'AWAITING_PAYMENT');
    expect(success.confirmationMessage, contains('ORD-001'));
  });

  test('missing order id is treated as a failed confirmation', () async {
    final service = buildService();
    service.response = {
      'order': {
        'id': '',
        'orderRef': null,
        'status': 'AWAITING_PAYMENT',
      },
    };
    final gateway = buildGateway(service);

    final result = await gateway.checkout(const RetailCart().add(product));

    expect(result, isA<RetailCheckoutFailure>());
    expect((result as RetailCheckoutFailure).retryable, isTrue);
  });

  test('empty cart does not call the service', () async {
    final service = buildService();
    final gateway = buildGateway(service);

    final result = await gateway.checkout(const RetailCart());

    expect(result, isA<RetailCheckoutFailure>());
    expect(service.receivedItems, isNull);
  });
}