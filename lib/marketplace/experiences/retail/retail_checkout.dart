import 'retail_cart.dart';
import '../../../utils/idempotency_key.dart';

/// Payment protection choices presented to a retail customer.
enum RetailPaymentProtection {
  direct,
  escrow,
}

class RetailCheckoutOptions {
  final bool escrowProtectionAvailable;
  final RetailPaymentProtection paymentProtection;

  const RetailCheckoutOptions({
    this.escrowProtectionAvailable = false,
    this.paymentProtection = RetailPaymentProtection.direct,
  });

  bool get usesEscrow =>
      escrowProtectionAvailable &&
      paymentProtection == RetailPaymentProtection.escrow;
}

/// Backend integration boundary for the retail experience.
///
/// The experience collects a cart locally but delegates inventory validation,
/// pricing, payment and order creation to the host's authoritative checkout
/// implementation. This keeps retail UI independent of a specific API shape.
abstract class RetailCheckoutGateway {
  Future<RetailCheckoutResult> checkout(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    required String idempotencyKey,
  });
}

sealed class RetailCheckoutResult {
  const RetailCheckoutResult();
}

class RetailCheckoutSuccess extends RetailCheckoutResult {
  final String orderId;
  final String? trackingStatus;
  final String? confirmationMessage;

  const RetailCheckoutSuccess({
    required this.orderId,
    this.trackingStatus,
    this.confirmationMessage,
  });
}

class RetailCheckoutFailure extends RetailCheckoutResult {
  final String message;
  final bool retryable;

  const RetailCheckoutFailure({
    required this.message,
    this.retryable = true,
  });
}

class RetailCheckoutUnavailable extends RetailCheckoutResult {
  final String message;

  const RetailCheckoutUnavailable({
    this.message = 'Checkout is not available for this store yet.',
  });
}

/// Coordinates cart checkout without embedding transport or payment logic in
/// the widget layer.
class RetailCheckoutController {
  final RetailCheckoutGateway gateway;

  const RetailCheckoutController(this.gateway);

  Future<RetailCheckoutResult> submit(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    String? idempotencyKey,
  }) async {
    if (cart.lines.isEmpty) {
      return const RetailCheckoutFailure(
        message: 'Your bag is empty.',
        retryable: false,
      );
    }

    if (options.paymentProtection == RetailPaymentProtection.escrow &&
        !options.escrowProtectionAvailable) {
      return const RetailCheckoutFailure(
        message: 'Escrow protection is not available for this store.',
        retryable: false,
      );
    }

    // Generate once at the logical-operation boundary. Recovery callers pass
    // the original key back into submit() so retries remain the same backend
    // economic operation rather than creating a second checkout.
    final operationKey = idempotencyKey ?? IdempotencyKey.generate();
    return gateway.checkout(
      cart,
      options: options,
      idempotencyKey: operationKey,
    );
  }
}