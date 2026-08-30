import 'retail_cart.dart';
import 'retail_checkout.dart';
import '../../../storefront/services/storefront_service.dart';
import '../../../storefront/services/storefront_conflict_exception.dart';

/// Concrete [RetailCheckoutGateway] backed by [StorefrontService].
///
/// The controller owns the operation identity. This gateway deliberately does
/// not generate a new key, so retries/recovery can reuse the same economic
/// operation identity.
class StorefrontRetailCheckoutGateway implements RetailCheckoutGateway {
  StorefrontRetailCheckoutGateway({required this.businessProfileId, StorefrontService? storefrontService}) : _storefrontService = storefrontService ?? StorefrontService();

  final String businessProfileId;
  final StorefrontService _storefrontService;

  @override
  Future<RetailCheckoutResult> checkout(RetailCart cart, {RetailCheckoutOptions options = const RetailCheckoutOptions(), required String idempotencyKey}) async {
    if (cart.lines.isEmpty) {
      return const RetailCheckoutFailure(message: 'Your bag is empty.', retryable: false);
    }

    final items = cart.lines.map((line) => {
      'productId': line.product.id,
      'quantity': line.quantity,
      if (line.variants.isNotEmpty) 'variants': line.variants,
    }).toList();

    final paymentMode = options.paymentProtection == RetailPaymentProtection.escrow ? 'ESCROW' : 'DIRECT';

    try {
      final data = await _storefrontService.checkoutCart(
        businessProfileId: businessProfileId,
        items: items,
        paymentMode: paymentMode,
        idempotencyKey: idempotencyKey,
      );

      final order = data['order'] as Map<String, dynamic>?;
      final orderId = order?['id']?.toString() ?? data['orderId']?.toString() ?? '';
      if (orderId.isEmpty) {
        throw const FormatException('Checkout response did not contain an order id.');
      }
      final orderRef = order?['orderRef']?.toString();

      return RetailCheckoutSuccess(
        orderId: orderId,
        trackingStatus: order?['status']?.toString(),
        confirmationMessage: orderRef != null ? 'Order $orderRef created.' : 'Order placed successfully.',
      );
    } on StorefrontConflictException {
      // Concurrency conflicts are authoritative domain failures. Do not turn
      // them into a network retry: the caller must refresh/reconcile state.
      rethrow;
    } on StorefrontApiException catch (e) {
      return RetailCheckoutFailure(message: e.message, retryable: e.isRetryable);
    } on FormatException catch (_) {
      // A successful HTTP response with an invalid payload is a protocol
      // failure, not a transient transport error.
      return const RetailCheckoutFailure(message: 'Received an invalid response from the server.', retryable: false);
    } catch (e) {
      // Unknown transport/client failures remain retryable because the server
      // may have completed the operation; the retained idempotency key makes
      // a retry safe.
      return RetailCheckoutFailure(message: e.toString(), retryable: true);
    }
  }
}