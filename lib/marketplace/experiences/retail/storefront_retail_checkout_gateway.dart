import 'retail_cart.dart';
import 'retail_checkout.dart';
import '../../../storefront/services/storefront_service.dart';

/// Concrete [RetailCheckoutGateway] backed by [StorefrontService].
///
/// Translates the retail-experience cart + options into the backend's
/// `POST /storefront/{businessProfileId}/checkout` contract.
///
/// The controller owns the operation identity. This gateway deliberately does
/// not generate a new key, so retries/recovery can reuse the same economic
/// operation identity.
class StorefrontRetailCheckoutGateway implements RetailCheckoutGateway {
  StorefrontRetailCheckoutGateway({
    required this.businessProfileId,
    StorefrontService? storefrontService,
  }) : _storefrontService = storefrontService ?? StorefrontService();

  final String businessProfileId;
  final StorefrontService _storefrontService;

  @override
  Future<RetailCheckoutResult> checkout(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    required String idempotencyKey,
  }) async {
    if (cart.lines.isEmpty) {
      return const RetailCheckoutFailure(
        message: 'Your bag is empty.',
        retryable: false,
      );
    }

    final items = cart.lines
        .map((line) => {
              'productId': line.product.id,
              'quantity': line.quantity,
              if (line.variants.isNotEmpty) 'variants': line.variants,
            })
        .toList();

    final paymentMode = options.paymentProtection == RetailPaymentProtection.escrow
        ? 'ESCROW'
        : 'DIRECT';

    try {
      final data = await _storefrontService.checkoutCart(
        businessProfileId: businessProfileId,
        items: items,
        paymentMode: paymentMode,
        idempotencyKey: idempotencyKey,
      );

      final order = data['order'] as Map<String, dynamic>?;
      final orderId = order?['id']?.toString() ?? data['orderId']?.toString() ?? '';
      final orderRef = order?['orderRef']?.toString();

      return RetailCheckoutSuccess(
        orderId: orderId,
        trackingStatus: order?['status']?.toString(),
        confirmationMessage: orderRef != null
            ? 'Order $orderRef created.'
            : 'Order placed successfully.',
      );
    } on FormatException catch (_) {
      return const RetailCheckoutFailure(
        message: 'Received an invalid response from the server.',
        retryable: false,
      );
    } catch (e) {
      final message = e.toString();
      return RetailCheckoutFailure(
        message: message,
        retryable: true,
      );
    }
  }
}
