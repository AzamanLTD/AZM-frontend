import 'retail_cart.dart';
import 'retail_checkout.dart';
import '../../../storefront/services/storefront_service.dart';
import '../../../storefront/services/storefront_conflict_exception.dart';

/// Concrete [RetailCheckoutGateway] backed by [StorefrontService].
///
/// NOT PRODUCTION-REACHABLE (retail checkout recovery audit, 2026-10-01):
/// no live code constructs this gateway — checkout runs through the shared
/// tray (cartProvider → CartScreen → StorefrontService.checkoutCart with a
/// durable FinancialOperationRef). Retained only as the Planning deep-dive's
/// gateway contract surface.
///
/// The controller owns the operation identity. This gateway deliberately does
/// not generate a new key, so retries can reuse the same economic operation
/// identity. Note this pre-armed transport has no durable journal, recovery
/// or disposition — those semantics live exclusively in the durable registry
/// path the CartScreen uses.
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
        .map(
          (line) => {
            'productId': line.product.id,
            'quantity': line.quantity,
            if (line.variants.isNotEmpty) 'variants': line.variants,
          },
        )
        .toList();

    final paymentMode =
        options.paymentProtection == RetailPaymentProtection.escrow
        ? 'ESCROW'
        : 'DIRECT';

    try {
      final data = await _storefrontService.checkoutCart(
        businessProfileId: businessProfileId,
        items: items,
        paymentMode: paymentMode,
        // The CALLER-OWNED pre-armed key (the operation object holds it).
        // The gateway transports identity; it never generates one. There is
        // no registry journal on this legacy path — recovery semantics are
        // exclusive to the durable checkoutCart(operationType, ref) path.
        idempotencyKey: idempotencyKey,
      );

      final order = data['order'] as Map<String, dynamic>?;
      final orderId =
          order?['id']?.toString() ?? data['orderId']?.toString() ?? '';
      if (orderId.isEmpty) {
        throw const FormatException(
          'Checkout response did not contain an order id.',
        );
      }
      final orderRef = order?['orderRef']?.toString();
      final escrow = order?['escrow'];
      final escrowId = escrow is Map<String, dynamic>
          ? escrow['id']?.toString()
          : null;

      if (paymentMode == 'ESCROW' && (escrowId == null || escrowId.isEmpty)) {
        throw const FormatException(
          'Escrow checkout response did not contain an escrow id.',
        );
      }

      return RetailCheckoutSuccess(
        orderId: orderId,
        trackingStatus: order?['status']?.toString(),
        confirmationMessage: orderRef != null
            ? 'Order $orderRef created.'
            : 'Order placed successfully.',
        escrowId: escrowId,
      );
    } on StorefrontConflictException {
      // Concurrency conflicts are authoritative domain failures. Do not turn
      // them into a network retry: the caller must refresh/reconcile state.
      rethrow;
    } on StorefrontApiException catch (e) {
      return RetailCheckoutFailure(
        message: e.message,
        retryable: e.isRetryable,
      );
    } on FormatException catch (_) {
      // A successful HTTP response with an invalid payload is an UNKNOWN
      // state, not a definitive failure: the backend may have committed
      // the order behind that 2xx. retryable:true keeps the caller's
      // durable instance armed, so a retry reuses the SAME key and
      // converges on the committed order instead of creating a duplicate.
      return const RetailCheckoutFailure(
        message: 'Received an invalid response from the server.',
        retryable: true,
      );
    } catch (e) {
      // Unknown transport/client failures remain retryable because the server
      // may have completed the operation; the retained idempotency key makes
      // a retry safe.
      return RetailCheckoutFailure(message: e.toString(), retryable: true);
    }
  }

  @override
  Future<void> fundEscrow(
    String escrowId, {
    String? totpToken,
    String? password,
  }) {
    return _storefrontService.fundEscrow(
      escrowId: escrowId,
      totpToken: totpToken,
      password: password,
    );
  }
}
