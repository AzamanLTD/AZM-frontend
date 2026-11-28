// Store checkout paid from the wallet (app side).
//   1. A store product goes into the cart (never the friend-chat deal form);
//      a priceless product is refused; another store's cart asks first.
//   2. The cart creates a held-payment order, shows the server's own total
//      and fee, asks for the second factor, then pays (fund).
//   3. A store that switched held payment off gets an honest direct order.
//   4. A short balance keeps the order and offers Add money.
//   5. My orders: Pay a saved order; "Got it" behind the second factor;
//      "Report a problem" with a reason.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/screens/storefront_order_history_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/widgets/marketplace/store_cart_actions.dart';
import 'package:azaman/widgets/marketplace/store_order_pay.dart';
import 'package:azaman/widgets/security/second_factor.dart';

import 'support/money_access_test_support.dart';

Map<String, dynamic> _order({
  String status = 'AWAITING_PAYMENT',
  String escrowStatus = 'DRAFT',
  bool payerSatisfied = false,
  DateTime? expiresAt,
  DateTime? deliveredAt,
}) => {
  'id': 'ord-1',
  'orderRef': 'ORD-1A2B',
  'status': status,
  'amountUsdc': '12.5',
  'deliveredAt': deliveredAt?.toIso8601String(),
  'items': [
    {'id': 'i-1'},
    {'id': 'i-2'},
  ],
  'businessProfile': {'id': 'bp-1', 'businessName': 'Kofi Bakery'},
  'escrow': {
    'id': 'esc-1',
    'status': escrowStatus,
    'amountUsdc': '12.5',
    'feeUsdc': '0.125',
    'payerSatisfied': payerSatisfied,
    'expiresAt': (expiresAt ?? DateTime.now().add(const Duration(hours: 20)))
        .toIso8601String(),
  },
};

class _FakeStorefront extends StorefrontService {
  _FakeStorefront({
    this.escrowRefused = false,
    this.shortBalance = false,
    this.orders = const [],
  });
  final bool escrowRefused;
  final bool shortBalance;
  final List<Map<String, dynamic>> orders;
  final modes = <String>[];
  final funded = <Map<String, String?>>[];
  final confirmed = <Map<String, String?>>[];
  final reported = <List<String>>[];

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
    modes.add(paymentMode);
    if (paymentMode == 'ESCROW' && escrowRefused) {
      throw ApiException(
        message:
            'This store does not offer escrow protection. Choose direct payment instead.',
        statusCode: 403,
      );
    }
    if (paymentMode == 'DIRECT') {
      return {
        'order': {..._order(), 'escrow': null},
      };
    }
    return {'order': _order()};
  }

  @override
  Future<void> fundEscrow({
    required String escrowId,
    String? totpToken,
    String? password,
  }) async {
    funded.add({
      'escrowId': escrowId,
      'totpToken': totpToken,
      'password': password,
    });
    if (shortBalance) {
      throw ApiException(
        message: 'Insufficient balance. Required: 12.625000 USDC',
        statusCode: 400,
        code: 'INSUFFICIENT_BALANCE',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getMyOrders({
    String? status,
    int limit = 20,
    String? cursor,
  }) async => {'orders': orders, 'nextCursor': null};

  @override
  Future<bool> confirmOrderReceived({
    required String escrowId,
    String? totpToken,
    String? password,
  }) async {
    confirmed.add({
      'escrowId': escrowId,
      'totpToken': totpToken,
      'password': password,
    });
    return true;
  }

  @override
  Future<void> reportOrderProblem({
    required String escrowId,
    required String reason,
  }) async {
    reported.add([escrowId, reason]);
  }
}

Future<SecondFactor?> _askCode({
  required SecondFactorKind kind,
  String? errorText,
}) async => const SecondFactor.authenticator('123456');

BusinessProfile _biz(String id, String name) => BusinessProfile.fromJson({
  'id': id,
  'bizId': 'BIZ-$id',
  'businessName': name,
  'category': 'RETAIL',
});

BusinessProduct _product({String id = 'p-1', double price = 6.25}) =>
    BusinessProduct.fromJson({
      'id': id,
      'businessProfileId': 'bp-1',
      'name': 'Sourdough',
      'slug': 'sourdough',
      'priceUsdc': price,
      'imageUrls': const [],
      'isActive': true,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
    SharedPreferences.setMockInitialValues({});
    ApiClient.operationAccountOverride = () async => 'acct-test';
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    ApiClient.operationAccountOverride = null;
  });

  group('models', () {
    test('a saved order is payable with the server\'s numbers', () {
      final p = StoreOrderPayment.fromOrder(_order())!;
      expect(p.escrowId, 'esc-1');
      expect(p.amountUsdc, 12.5);
      expect(p.feeUsdc, 0.125);
      expect(p.totalUsdc, 12.625);
      expect(p.itemCount, 2);
      expect(storeUsdcLabel(p.totalUsdc), r'$12.625');
      // Paid, lapsed, or direct: nothing to pay here.
      expect(
        StoreOrderPayment.fromOrder(
          _order(status: 'PAID', escrowStatus: 'FUNDED'),
        ),
        isNull,
      );
      expect(
        StoreOrderPayment.fromOrder(
          _order(
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ),
        isNull,
      );
      expect(
        StoreOrderPayment.fromOrder({..._order(), 'escrow': null}),
        isNull,
      );
    });

    test('each order says what the buyer can do', () {
      expect(storeOrderStage(_order()), StoreOrderStage.pay);
      expect(
        storeOrderStage(_order(status: 'PAID', escrowStatus: 'FUNDED')),
        StoreOrderStage.heldUntilHandover,
      );
      expect(
        storeOrderStage(
          _order(status: 'DELIVERED', escrowStatus: 'PENDING_SETTLEMENT'),
        ),
        StoreOrderStage.confirm,
      );
      expect(
        storeOrderStage(
          _order(
            status: 'DELIVERED',
            escrowStatus: 'PENDING_SETTLEMENT',
            payerSatisfied: true,
          ),
        ),
        StoreOrderStage.none,
      );
      expect(
        storeOrderStage(_order(status: 'DISPUTED', escrowStatus: 'DISPUTED')),
        StoreOrderStage.reported,
      );
      expect(
        storeOrderStage(_order(status: 'COMPLETED', escrowStatus: 'SETTLED')),
        StoreOrderStage.none,
      );
    });
  });

  group('adding from a store page', () {
    Future<(WidgetRef, BuildContext)> host(WidgetTester tester) async {
      late WidgetRef r;
      late BuildContext c;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  r = ref;
                  c = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return (r, c);
    }

    testWidgets('goes into the cart', (tester) async {
      final (ref, context) = await host(tester);
      final added = await addStoreProductToCart(
        context,
        ref,
        business: _biz('bp-1', 'Kofi Bakery'),
        product: _product(),
      );
      await tester.pump();
      expect(added, isTrue);
      final cart = ref.read(cartProvider);
      expect(cart.businessProfileId, 'bp-1');
      expect(cart.items.single.unitPrice, 6.25);
      expect(find.text('Sourdough added to your cart'), findsOneWidget);
    });

    testWidgets('a product with no price is refused', (tester) async {
      final (ref, context) = await host(tester);
      final added = await addStoreProductToCart(
        context,
        ref,
        business: _biz('bp-1', 'Kofi Bakery'),
        product: _product(price: 0),
      );
      expect(added, isFalse);
      expect(ref.read(cartProvider).items, isEmpty);
    });

    testWidgets('another store\'s cart asks before starting a new one', (
      tester,
    ) async {
      final (ref, context) = await host(tester);
      await addStoreProductToCart(
        context,
        ref,
        business: _biz('bp-1', 'Kofi Bakery'),
        product: _product(),
      );
      final pending = addStoreProductToCart(
        context,
        ref,
        business: _biz('bp-2', 'Ama Shoes'),
        product: _product(id: 'p-2'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start a new cart?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cart-start-new')));
      await tester.pumpAndSettle();
      expect(await pending, isTrue);
      expect(ref.read(cartProvider).businessProfileId, 'bp-2');
      expect(ref.read(cartProvider).items.single.productId, 'p-2');
    });
  });

  group('cart checkout', () {
    Future<_FakeStorefront> pumpCart(
      WidgetTester tester,
      _FakeStorefront svc,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storefrontServiceProvider.overrideWithValue(svc),
            unlockedMoneyAccess(),
          ],
          child: const MaterialApp(
            home: CartScreen(secondFactorPrompt: _askCode),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CartScreen)),
      );
      container
          .read(cartProvider.notifier)
          .addItem(
            businessProfileId: 'bp-1',
            businessName: 'Kofi Bakery',
            productId: 'p-1',
            name: 'Sourdough',
            unitPrice: 6.25,
            quantity: 2,
          );
      await tester.pumpAndSettle();
      return svc;
    }

    Future<void> checkout(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('cart-checkout'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      // The checkout button spins while a dialog or sheet is up, so the
      // tree never settles: step through the frames instead.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets(
      'creates a held-payment order, shows its numbers, pays with the second factor',
      (tester) async {
        final svc = await pumpCart(tester, _FakeStorefront());
        await checkout(tester);
        expect(svc.modes, ['ESCROW']);
        expect(find.text('Pay Kofi Bakery'), findsOneWidget);
        expect(find.text(r'$12.50'), findsOneWidget);
        expect(find.text(r'$0.125'), findsOneWidget);
        expect(find.text(r'$12.625 USDC'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('store-pay-held-note')),
          findsOneWidget,
        );
        expect(svc.funded, isEmpty);

        await tester.tap(find.byKey(const ValueKey('store-pay-confirm')));
        await tester.pumpAndSettle();
        expect(svc.funded, [
          {'escrowId': 'esc-1', 'totpToken': '123456', 'password': null},
        ]);
        expect(
          find.byKey(const ValueKey('order-outcome-paid')),
          findsOneWidget,
        );
        expect(find.text('Paid · held for you'), findsOneWidget);
      },
    );

    testWidgets('"Not now" keeps the order saved, not paid', (tester) async {
      final svc = await pumpCart(tester, _FakeStorefront());
      await checkout(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(svc.funded, isEmpty);
      expect(find.byKey(const ValueKey('order-outcome-saved')), findsOneWidget);
      expect(find.text('Pay from My orders'), findsOneWidget);
    });

    testWidgets('a short balance keeps the order and offers Add money', (
      tester,
    ) async {
      await pumpCart(tester, _FakeStorefront(shortBalance: true));
      await checkout(tester);
      await tester.tap(find.byKey(const ValueKey('store-pay-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('order-outcome-shortBalance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('order-outcome-add-money')),
        findsOneWidget,
      );
    });

    testWidgets('a store without held payment gets an honest direct order', (
      tester,
    ) async {
      final svc = await pumpCart(tester, _FakeStorefront(escrowRefused: true));
      await checkout(tester);
      expect(find.text('Pay the store directly?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cart-send-direct')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(svc.modes, ['ESCROW', 'DIRECT']);
      expect(svc.funded, isEmpty);
      expect(
        find.byKey(const ValueKey('order-outcome-direct')),
        findsOneWidget,
      );
    });
  });

  group('My orders', () {
    Future<_FakeStorefront> pumpOrders(
      WidgetTester tester,
      List<Map<String, dynamic>> orders,
    ) async {
      final svc = _FakeStorefront(orders: orders);
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storefrontServiceProvider.overrideWithValue(svc),
            unlockedMoneyAccess(),
          ],
          child: const MaterialApp(
            home: StorefrontOrderHistoryScreen(secondFactorPrompt: _askCode),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return svc;
    }

    testWidgets('a saved order can be paid', (tester) async {
      final svc = await pumpOrders(tester, [_order()]);
      expect(find.text('Not paid'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-pay-ord-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('store-pay-confirm')));
      await tester.pumpAndSettle();
      expect(svc.funded.single['escrowId'], 'esc-1');
    });

    testWidgets('"Got it" pays the store behind the second factor', (
      tester,
    ) async {
      final svc = await pumpOrders(tester, [
        _order(
          status: 'DELIVERED',
          escrowStatus: 'PENDING_SETTLEMENT',
          deliveredAt: DateTime.now(),
        ),
      ]);
      expect(find.text('Handed over'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-got-it-ord-1')));
      await tester.pumpAndSettle();
      expect(find.text('Got your order?'), findsOneWidget);
      expect(svc.confirmed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('order-got-it-confirm')));
      await tester.pumpAndSettle();
      expect(svc.confirmed, [
        {'escrowId': 'esc-1', 'totpToken': '123456', 'password': null},
      ]);
      expect(find.text('Thanks. Kofi Bakery has been paid.'), findsOneWidget);
    });

    testWidgets('"Report a problem" needs a reason, then holds the payment', (
      tester,
    ) async {
      final svc = await pumpOrders(tester, [
        _order(
          status: 'DELIVERED',
          escrowStatus: 'PENDING_SETTLEMENT',
          deliveredAt: DateTime.now(),
        ),
      ]);
      await tester.tap(find.byKey(const ValueKey('order-report-ord-1')));
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('order-report-send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('order-report-reason')),
        'Two loaves missing',
      );
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(svc.reported, [
        ['esc-1', 'Two loaves missing'],
      ]);
    });

    testWidgets('a reported order says the payment is held', (tester) async {
      await pumpOrders(tester, [
        _order(status: 'DISPUTED', escrowStatus: 'DISPUTED'),
      ]);
      expect(
        find.text('Problem reported · payment held while Azaman reviews it.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('order-got-it-ord-1')), findsNothing);
    });
  });
}
