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

  /// Funds an escrow created by an escrow-protected checkout.
  ///
  /// The backend performs step-up verification. Callers provide either a
  /// TOTP token (for 2FA-enabled accounts) or the account password.
  Future<void> fundEscrow(
    String escrowId, {
    String? totpToken,
    String? password,
  }) async {
    throw UnimplementedError('This checkout gateway does not support escrow funding.');
  }
}

sealed class RetailCheckoutResult {
  const RetailCheckoutResult();
}

class RetailCheckoutSuccess extends RetailCheckoutResult {
  final String orderId;
  final String? trackingStatus;
  final String? confirmationMessage;
  final String? escrowId;

  const RetailCheckoutSuccess({
    required this.orderId,
    this.trackingStatus,
    this.confirmationMessage,
    this.escrowId,
  });

  bool get isEscrowCheckout => escrowId != null && escrowId!.isNotEmpty;
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

/// Immutable identity for one economic checkout intent.
///
/// A checkout operation owns the idempotency key for its immutable cart
/// snapshot. Retrying an operation therefore reuses the same backend identity;
/// starting a new operation requires a new snapshot and a new key.
class RetailCheckoutOperation {
  final RetailCart cart;
  final RetailCheckoutOptions options;
  final String idempotencyKey;
  final RetailCheckoutGateway _gateway;

  RetailCheckoutOperation({
    required RetailCart cart,
    required this.options,
    required this.idempotencyKey,
    required RetailCheckoutGateway gateway,
  })  : cart = RetailCart(
          lines: List.unmodifiable(
            cart.lines
                .map(
                  (line) => line.copyWith(
                    variants: Map.unmodifiable(line.variants),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        _gateway = gateway;

  Future<RetailCheckoutResult> submit() {
    return _gateway.checkout(
      cart,
      options: options,
      idempotencyKey: idempotencyKey,
    );
  }
}

/// Coordinates cart checkout without embedding transport or payment logic in
/// the widget layer.
class RetailCheckoutController {
  final RetailCheckoutGateway gateway;

  const RetailCheckoutController(this.gateway);

  /// Creates a stable operation from the current cart snapshot.
  ///
  /// Callers should retain the returned operation while recovering from a
  /// timeout, connection loss or other retryable failure. Mutating the cart
  /// creates a new cart value and must be represented by a new operation.
  RetailCheckoutOperation begin(
    RetailCart cart, {
    RetailCheckoutOptions options = const RetailCheckoutOptions(),
    String? idempotencyKey,
  }) {
    if (cart.lines.isEmpty) {
      throw StateError('Cannot begin checkout with an empty cart.');
    }

    if (options.paymentProtection == RetailPaymentProtection.escrow &&
        !options.escrowProtectionAvailable) {
      throw StateError('Escrow protection is not available for this store.');
    }

    return RetailCheckoutOperation(
      cart: cart,
      options: options,
      idempotencyKey: idempotencyKey ?? IdempotencyKey.generate(),
      gateway: gateway,
    );
  }

  /// Performs a one-shot checkout.
  ///
  /// For retry/recovery, prefer [begin] and retain the returned operation so
  /// that every subsequent attempt uses the same idempotency identity.
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

    final operation = RetailCheckoutOperation(
      cart: cart,
      options: options,
      idempotencyKey: idempotencyKey ?? IdempotencyKey.generate(),
      gateway: gateway,
    );
    return operation.submit();
  }
}
