// =============================================================================
// RETAIL CHECKOUT RECOVERY — deep-dive step 2: UI failure presentation.
//
// The classification contract is only real if the UI honors it. This suite
// pumps the REAL CartScreen with a scripted StorefrontService failure and
// pins that:
//
//   * each economic class surfaces distinct, class-appropriate copy —
//     the generic 'Order failed: $e' collapse is gone;
//   * an AMBIGUOUS outcome is never worded as "the order definitely
//     failed" (the first request may already have committed — wording it
//     as failure invites a duplicate order);
//   * a DEFINITIVE validation failure stays actionable, carrying the
//     backend's own message;
//   * the cart survives every failure (only a confirmed success clears).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

/// A StorefrontService whose live checkout path throws exactly [error] —
/// the rest of the object stays the REAL production service.
class _FailingCheckoutService extends StorefrontService {
  _FailingCheckoutService(this.error);

  final Object error;

  @override
  Future<Map<String, dynamic>> checkoutCart({
    required String businessProfileId,
    required List<Map<String, dynamic>> items,
    String? customerNotes,
    String? deliveryNotes,
    String? operationType,
    FinancialOperationRef? ref,
    String? idempotencyKey,
    String paymentMode = 'DIRECT',
  }) async {
    throw error;
  }
}

Future<void> _pumpWithFailure(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ),
  );
}

ProviderContainer _containerFor(Object error) {
  final container = ProviderContainer(overrides: [
    storefrontServiceProvider.overrideWithValue(_FailingCheckoutService(error)),
  ]);
  addTearDown(container.dispose);
  // Seed a live production-shaped cart: one item, one business.
  final cart = container.read(cartProvider.notifier);
  cart.startNewCart(businessProfileId: 'biz-001', businessName: 'Test Store');
  cart.addItem(
      businessProfileId: 'biz-001',
      businessName: 'Test Store',
      productId: 'p1',
      name: 'Test Product',
      unitPrice: 9.99);
  _lastContainer = container;
  return container;
}

Finder _checkoutButton(WidgetTester tester) {
  expect(find.byType(FilledButton), findsOneWidget,
      reason: 'the checkout bar owns the screen\'s single filled button');
  return find.byType(FilledButton);
}

Future<void> _placeOrderExpectingFailure(WidgetTester tester,
    {required ProviderContainer container, required String expected}) async {
  await _pumpWithFailure(tester, container);

  await tester.tap(_checkoutButton(tester));
  await tester.pump(); // SnackBar begins appearing
  await tester.pumpAndSettle();

  expect(find.textContaining(expected), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('definitive 4xx is actionable, carries the backend message, and never claims uncertainty',
      (tester) async {
    await _placeOrderExpectingFailure(
      tester,
      container: _containerFor(ApiException(
          message: 'This business is currently not accepting orders.',
          statusCode: 400)),
      expected:
          'Order not placed: This business is currently not accepting orders.',
    );
    expect(find.textContaining('may have gone through'), findsNothing);
    // The definitive failure did NOT clear the cart — the user corrects and retries.
    expect(_lastContainer!.read(cartProvider).items, hasLength(1));
  });

  testWidgets('unconfirmed outcome is never worded as a definite failure', (tester) async {
    await _placeOrderExpectingFailure(
      tester,
      container: _containerFor(http.ClientException('connection lost mid-flight')),
      expected: 'We could not confirm your order.',
    );
    expect(find.textContaining('may have gone through'), findsOneWidget);
    // The old generic collapse is gone — and no copy claims a definite failure.
    expect(find.textContaining('Order failed'), findsNothing);
    expect(find.textContaining('Order not placed'), findsNothing);
    // The cart (and the armed retry instance) survives the ambiguous outcome.
    expect(_lastContainer!.read(cartProvider).items, hasLength(1));
  });

  testWidgets('rate limiting gets its own message, not the generic failure', (tester) async {
    await _placeOrderExpectingFailure(
      tester,
      container: _containerFor(ApiException(message: 'Too many requests', statusCode: 429)),
      expected: 'Too many attempts.',
    );
    expect(find.textContaining('Order failed'), findsNothing);
  });

  testWidgets('authentication failure asks for sign-in, not a blind retry', (tester) async {
    await _placeOrderExpectingFailure(
      tester,
      container: _containerFor(
          ApiException(message: 'Not authorized', statusCode: 401, code: 'TOKEN_EXPIRED')),
      expected: 'Please sign in again to place your order.',
    );
    expect(find.textContaining('Order failed'), findsNothing);
  });
}

/// The last container — written by [_containerFor] so the cart-survival
/// assertions can read the post-failure state.
ProviderContainer? _lastContainer;
