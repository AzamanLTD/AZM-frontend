import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/experiences/retail/storefront_retail_checkout_gateway.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/storefront/services/storefront_conflict_exception.dart';

class _CapturingStorefrontService extends StorefrontService {
  String? receivedBusinessProfileId;
  List<Map<String, dynamic>>? receivedItems;
  String? receivedPaymentMode;
  String? receivedIdempotencyKey;

  Map<String, dynamic> response = {'order': {'id': 'order-123', 'orderRef': 'ORD-001', 'status': 'AWAITING_PAYMENT'}};
  Object? error;

  @override
  Future<Map<String, dynamic>> checkoutCart({required String businessProfileId, required List<Map<String, dynamic>> items, String? customerNotes, String? deliveryNotes, String? idempotencyKey, String paymentMode = 'DIRECT'}) async {
    receivedBusinessProfileId = businessProfileId;
    receivedItems = items;
    receivedPaymentMode = paymentMode;
    receivedIdempotencyKey = idempotencyKey;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  const product = RetailProduct(id: 'p1', name: 'Bag', price: 20, currency: 'GHS');

  StorefrontRetailCheckoutGateway buildGateway(_CapturingStorefrontService service) => StorefrontRetailCheckoutGateway(businessProfileId: 'biz-001', storefrontService: service);
  RetailCart buildCart() => const RetailCart().add(product);

  group('StorefrontRetailCheckoutGateway — transport mapping', () {
    test('DIRECT protection maps to paymentMode=DIRECT and preserves key', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      await gateway.checkout(buildCart(), options: const RetailCheckoutOptions(paymentProtection: RetailPaymentProtection.direct), idempotencyKey: 'checkout-direct-1');
      expect(service.receivedPaymentMode, 'DIRECT');
      expect(service.receivedIdempotencyKey, 'checkout-direct-1');
    });

    test('ESCROW protection maps to paymentMode=ESCROW', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      await gateway.checkout(buildCart(), options: const RetailCheckoutOptions(escrowProtectionAvailable: true, paymentProtection: RetailPaymentProtection.escrow), idempotencyKey: 'checkout-escrow-1');
      expect(service.receivedPaymentMode, 'ESCROW');
    });

    test('cart items are serialized with productId and quantity', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      await gateway.checkout(buildCart(), idempotencyKey: 'checkout-2');
      expect(service.receivedItems, isNotNull);
      expect(service.receivedItems!.length, 1);
      expect(service.receivedItems![0]['productId'], 'p1');
      expect(service.receivedItems![0]['quantity'], 1);
    });

    test('variant selections are preserved in the transport payload', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      final cart = RetailCart(lines: [RetailCartLine(product: product, quantity: 1, variants: {'Size': 'Large'})]);
      await gateway.checkout(cart, idempotencyKey: 'checkout-variant-1');
      expect(service.receivedItems!.single['variants'], {'Size': 'Large'});
    });

    test('businessProfileId is passed through to the service', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      await gateway.checkout(buildCart(), idempotencyKey: 'checkout-3');
      expect(service.receivedBusinessProfileId, 'biz-001');
    });

    test('successful response produces RetailCheckoutSuccess with order details', () async {
      final service = _CapturingStorefrontService();
      service.response = {'order': {'id': 'ord-999', 'orderRef': 'AZM-2024-001', 'status': 'AWAITING_PAYMENT'}};
      final gateway = buildGateway(service);
      final result = await gateway.checkout(buildCart(), idempotencyKey: 'checkout-4');
      expect(result, isA<RetailCheckoutSuccess>());
      final success = result as RetailCheckoutSuccess;
      expect(success.orderId, 'ord-999');
      expect(success.trackingStatus, 'AWAITING_PAYMENT');
      expect(success.confirmationMessage, contains('AZM-2024-001'));
    });

    test('malformed success response produces a non-retryable failure', () async {
      final service = _CapturingStorefrontService();
      service.response = {'order': {'id': '', 'orderRef': null, 'status': null}};
      final gateway = buildGateway(service);
      final result = await gateway.checkout(buildCart(), idempotencyKey: 'checkout-5');
      expect(result, isA<RetailCheckoutFailure>());
      expect((result as RetailCheckoutFailure).retryable, isFalse);
    });

    test('client HTTP failures are non-retryable while transient server failures are retryable', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      service.error = const StorefrontApiException(statusCode: 400, code: 'INVALID_CHECKOUT', message: 'Invalid checkout.');
      final clientFailure = await gateway.checkout(buildCart(), idempotencyKey: 'checkout-client-failure');
      expect(clientFailure, isA<RetailCheckoutFailure>());
      expect((clientFailure as RetailCheckoutFailure).retryable, isFalse);
      service.error = const StorefrontApiException(statusCode: 503, message: 'Temporarily unavailable.');
      final serverFailure = await gateway.checkout(buildCart(), idempotencyKey: 'checkout-server-failure');
      expect(serverFailure, isA<RetailCheckoutFailure>());
      expect((serverFailure as RetailCheckoutFailure).retryable, isTrue);
    });

    test('server conflict is preserved for the controller to surface explicitly', () async {
      final service = _CapturingStorefrontService();
      service.error = const StorefrontConflictException(message: 'Draft changed elsewhere.');
      final gateway = buildGateway(service);
      await expectLater(gateway.checkout(buildCart(), idempotencyKey: 'checkout-conflict-1'), throwsA(isA<StorefrontConflictException>()));
    });

    test('empty cart returns RetailCheckoutFailure without calling the service', () async {
      final service = _CapturingStorefrontService();
      final gateway = buildGateway(service);
      final result = await gateway.checkout(const RetailCart(), idempotencyKey: 'checkout-empty');
      expect(result, isA<RetailCheckoutFailure>());
      expect(service.receivedItems, isNull);
    });
  });
}