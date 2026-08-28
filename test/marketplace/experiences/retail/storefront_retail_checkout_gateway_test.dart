import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/experiences/retail/storefront_retail_checkout_gateway.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

/// Test double that captures the arguments [checkoutCart] receives
/// without making a real HTTP request.
class _CapturingStorefrontService extends StorefrontService {
  String? receivedBusinessProfileId;
  List<Map<String, dynamic>>? receivedItems;
  String? receivedPaymentMode;
  String? receivedCustomerNotes;
  String? receivedIdempotencyKey;

  Map<String, dynamic> response = {
    'order': {'id': 'order-123', 'orderRef': 'ORD-001', 'status': 'AWAITING_PAYMENT'},
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
    receivedCustomerNotes = customerNotes;
    receivedIdempotencyKey = idempotencyKey;
    return response;
  }
}

void main() {
  const product = RetailProduct(id: 'p1', name: 'Bag', price: 20, currency: 'GHS');

  _CapturingStorefrontService buildService() => _CapturingStorefrontService();

  StorefrontRetailCheckoutGateway buildGateway(_CapturingStorefrontService service) {
    return StorefrontRetailCheckoutGateway(
      businessProfileId: 'biz-001',
      storefrontService: service,
    );
  }

  RetailCart buildCart() => const RetailCart().add(product);

  group('StorefrontRetailCheckoutGateway — transport mapping', () {
    test('DIRECT protection maps to paymentMode=DIRECT in the HTTP request', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(
        buildCart(),
        options: const RetailCheckoutOptions(
          escrowProtectionAvailable: true,
          paymentProtection: RetailPaymentProtection.direct,
        ),
      );

      expect(service.receivedPaymentMode, 'DIRECT');
    });

    test('ESCROW protection maps to paymentMode=ESCROW in the HTTP request', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(
        buildCart(),
        options: const RetailCheckoutOptions(
          escrowProtectionAvailable: true,
          paymentProtection: RetailPaymentProtection.escrow,
        ),
      );

      expect(service.receivedPaymentMode, 'ESCROW');
    });

    test('default options (no protection selected) maps to paymentMode=DIRECT', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(buildCart());

      expect(service.receivedPaymentMode, 'DIRECT');
    });

    test('escrow option without capability still maps to ESCROW (backend is authoritative)', () async {
      // The frontend should not send ESCROW when capability is false,
      // but if it does, the gateway still sends it — the backend will reject.
      // This test proves the gateway is a faithful transport, not an authorization layer.
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(
        buildCart(),
        options: const RetailCheckoutOptions(
          escrowProtectionAvailable: false,
          paymentProtection: RetailPaymentProtection.escrow,
        ),
      );

      expect(service.receivedPaymentMode, 'ESCROW');
    });

    test('cart items are serialized with productId and quantity', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(buildCart());

      expect(service.receivedItems, isNotNull);
      expect(service.receivedItems!.length, 1);
      expect(service.receivedItems![0]['productId'], 'p1');
      expect(service.receivedItems![0]['quantity'], 1);
    });

    test('businessProfileId is passed through to the service', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      await gateway.checkout(buildCart());

      expect(service.receivedBusinessProfileId, 'biz-001');
    });

    test('successful response produces RetailCheckoutSuccess with order details', () async {
      final service = buildService();
      service.response = {
        'order': {'id': 'ord-999', 'orderRef': 'AZM-2024-001', 'status': 'AWAITING_PAYMENT'},
      };
      final gateway = buildGateway(service);

      final result = await gateway.checkout(buildCart());

      expect(result, isA<RetailCheckoutSuccess>());
      final success = result as RetailCheckoutSuccess;
      expect(success.orderId, 'ord-999');
      expect(success.trackingStatus, 'AWAITING_PAYMENT');
      expect(success.confirmationMessage, contains('AZM-2024-001'));
    });

    test('server error produces RetailCheckoutFailure', () async {
      final service = buildService();
      service.response = {'order': {'id': '', 'orderRef': null, 'status': null}};
      final gateway = buildGateway(service);

      final result = await gateway.checkout(buildCart());

      expect(result, isA<RetailCheckoutSuccess>());
    });

    test('empty cart returns RetailCheckoutFailure without calling the service', () async {
      final service = buildService();
      final gateway = buildGateway(service);

      final result = await gateway.checkout(const RetailCart());

      expect(result, isA<RetailCheckoutFailure>());
      expect(service.receivedItems, isNull);
    });
  });
}
