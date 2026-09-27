import 'package:azaman/marketplace/experiences/retail/retail_cart.dart';
import 'package:azaman/marketplace/experiences/retail/retail_checkout.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/widgets/retail_collection_box_widget.dart';
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake gateway for the r42 disposition tests: records every
/// idempotency key the widget arms and replays a scripted result per call.
class _ScriptedGateway implements RetailCheckoutGateway {
  final keys = <String>[];
  final results = <RetailCheckoutResult>[];

  @override
  Future<RetailCheckoutResult> checkout(RetailCart cart,
      {RetailCheckoutOptions options = const RetailCheckoutOptions(),
      required String idempotencyKey}) async {
    keys.add(idempotencyKey);
    if (results.isEmpty) {
      throw StateError('no scripted result');
    }
    return results.removeAt(0);
  }

  @override
  Future<void> fundEscrow(String escrowId,
      {String? totpToken, String? password}) async {}
}

// =============================================================================
// r42 DISPOSITION (independent audit pass 3) — the durable checkout
// instance must survive a retryable failure (network loss / 5xx / an
// unparseable 2xx): the server state is UNKNOWN, so the instance stays
// pending and the user's re-tap reuses the SAME key and converges on the
// committed order instead of placing a duplicate.
// =============================================================================

void main() {
  final business = StorefrontBusinessInfo(
    name: 'Demo Retail',
    category: 'RETAIL',
    averageRating: 4.8,
  );

  setUp(() {
    ApiClient.operationAccountOverride = () async => 'user-1';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  /// The bag badge's '1' (white, w800) — distinct from a quantity '1'
  /// inside the still-open quick look sheet.
  final bagBadge = find.byWidgetPredicate((w) =>
      w is Text && w.data == '1' && w.style?.fontWeight == FontWeight.w800);

  Future<void> addToBag(WidgetTester tester) async {
    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();
    // Close the quick look sheet (tap the modal barrier) so its quantity
    // '1' can't shadow the badge.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(bagBadge);
    await tester.pumpAndSettle();
  }

  testWidgets('a retryable checkout failure RETAINS the durable instance — '
      'the re-tap reuses the SAME key (never a duplicate order)',
      (tester) async {
    final gateway = _ScriptedGateway();
    gateway.results.add(const RetailCheckoutFailure(
        message: 'Connection lost — your order is still pending.',
        retryable: true));
    gateway.results.add(const RetailCheckoutSuccess(
        orderId: 'order-1',
        confirmationMessage: 'Order placed successfully.'));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RetailCollectionBoxWidget(
          business: business,
          checkoutGateway: gateway,
          props: {
            'id': 'collection-1',
            'title': 'Staff Picks',
            'products': [
              {'id': 'p1', 'name': 'Everyday Bag', 'price': 25, 'currency': 'GHS'},
            ],
          },
        ),
      ),
    ));

    // First checkout attempt: transport failure.
    await addToBag(tester);
    await tester.tap(find.text('Continue to checkout'));
    await tester.pumpAndSettle();
    // The 'added to bag' snackbar is still showing its 4s duration; the
    // messenger queues the failure snackbar behind it — advance the clock.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(1));
    expect(find.text('Connection lost — your order is still pending.'),
        findsOneWidget);

    // The instance must STILL be pending — retiring it would arm a fresh
    // key on the re-tap and duplicate the order.
    var ops = await DurableOperationRegistry.pending(
        account: 'user-1', type: 'storefront.retail.checkout');
    expect(ops, hasLength(1));
    final originalKey = ops.single.key;

    // The user's re-tap of the SAME unfinished cart.
    await tester.tap(bagBadge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to checkout'));
    await tester.pumpAndSettle();

    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[1], gateway.keys[0],
        reason: 'the re-tap must reuse the SAME durable key');
    expect(gateway.keys[0], originalKey);

    // The answered success retires the instance.
    ops = await DurableOperationRegistry.pending(
        account: 'user-1', type: 'storefront.retail.checkout');
    expect(ops, isEmpty);
  });

  testWidgets('a definitive (non-retryable) checkout failure RETIRES the '
      'durable instance — the next checkout mints a fresh key',
      (tester) async {
    final gateway = _ScriptedGateway();
    gateway.results.add(
        const RetailCheckoutFailure(message: 'Your bag is empty.', retryable: false));
    gateway.results.add(const RetailCheckoutSuccess(
        orderId: 'order-2',
        confirmationMessage: 'Order placed successfully.'));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RetailCollectionBoxWidget(
          business: business,
          checkoutGateway: gateway,
          props: {
            'id': 'collection-1',
            'title': 'Staff Picks',
            'products': [
              {'id': 'p1', 'name': 'Everyday Bag', 'price': 25, 'currency': 'GHS'},
            ],
          },
        ),
      ),
    ));

    await addToBag(tester);
    await tester.tap(find.text('Continue to checkout'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(1));

    final ops = await DurableOperationRegistry.pending(
        account: 'user-1', type: 'storefront.retail.checkout');
    expect(ops, isEmpty,
        reason: 'a definitive failure never committed — retire it');

    // The next checkout is a genuinely new action: a fresh key.
    await tester.tap(bagBadge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to checkout'));
    await tester.pumpAndSettle();

    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[1], isNot(gateway.keys[0]));
  });
}
