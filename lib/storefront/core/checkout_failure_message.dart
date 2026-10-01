// =============================================================================
// CHECKOUT FAILURE MESSAGE — user-facing copy for classified failures.
//
// Deep-dive step 2 (frontend-operation-lifecycle.md): the live storefront
// economic callers (CartScreen.checkoutCart, StorefrontOrderSheet.
// placeStorefrontOrder) must not present every failure as one generic
// "Order failed" — the message follows the ECONOMIC class, and an
// unconfirmed outcome must never be worded as "the order definitely
// failed".
//
// This file owns only presentation copy. The classification lives in
// StorefrontService.classifyStorefrontFailure; the identity lifecycle
// lives in the durable disposition + DurableOperationRegistry.
// =============================================================================

import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

/// The SnackBar/inline copy for one classified failure of the live
/// storefront checkout/order paths. [error] is the raw exception — for
/// definitive pre-economic failures the backend's own message is the
/// actionable detail ("This business is currently not accepting orders.");
/// for every other class the raw transport detail is not user-appropriate
/// and the class copy stands alone.
String storefrontFailureMessage(StorefrontFailureClass failure, Object error) {
  switch (failure) {
    case StorefrontFailureClass.definitivePreEconomic:
      final detail = error is ApiException && error.message.trim().isNotEmpty
          ? error.message
          : 'The order was not accepted.';
      return 'Order not placed: $detail Update your cart and try again.';
    case StorefrontFailureClass.authenticationRequired:
      return 'Please sign in again to place your order.';
    case StorefrontFailureClass.rateLimited:
      return 'Too many attempts. Wait a moment before placing your order again.';
    case StorefrontFailureClass.domainConflict:
      return 'This checkout was already processed as a different cart '
          'version. Check your orders before placing again.';
    case StorefrontFailureClass.ambiguousOrUnknown:
      // The first request may already have committed. NEVER claim the
      // order definitely failed — that would invite a duplicate order.
      return 'We could not confirm your order. It may have gone through — '
          'check your orders before trying again.';
  }
}
