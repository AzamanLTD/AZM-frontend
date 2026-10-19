// =============================================================================
// STOREFRONT — GHS listing truth + explicit USDC payable truth
// (final acceptance follow-up, 2026-10-19).
//
// The customer journey traced: Marketplace listing / business card →
// StorefrontScreen catalogue (GET /api/storefront/:bizId/products, now
// carrying the authoritative priceGhs from backend #359) → Add → CartScreen
// (order/checkout confirmation) — plus StorefrontOrderSheet, the direct-order
// confirmation surface.
//
// Pinned contract:
//   • the storefront catalogue card (a browse LISTING) renders ONLY the
//     server-confirmed exact 2dp GHS string, or 'Price unavailable' — the
//     payable priceUsdc figure is never a substitute listing price;
//   • the order/payment confirmation carries the payable amount with its
//     EXPLICIT denomination — 'X USDC', never a bare '$';
//   • where both a GHS listing price and a USDC payable amount appear, they
//     are separate labelled facts — no conversion, no equivalence, no GHS
//     settlement implication.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart' show CartScreen;
import 'package:azaman/screens/storefront_order_sheet.dart';
import 'package:azaman/screens/storefront_screen.dart';
import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

class _FakeStorefrontService extends StorefrontService {
  _FakeStorefrontService(this.productsPayload);
  final Map<String, dynamic> productsPayload;

  @override
  Future<StorefrontRenderResponse?> renderStorefront(String businessProfileId) async {
    return StorefrontRenderResponse.fromJson(<String, dynamic>{
      'business': {'name': 'Test Shop', 'category': 'RETAIL'},
      'theme': <String, dynamic>{},
      'layout': <String, dynamic>{'tiles': <dynamic>[]},
    });
  }

  @override
  Future<Map<String, dynamic>> getStorefrontProducts(String businessProfileId) async {
    return productsPayload;
  }
}

Map<String, dynamic> _product({String? priceGhs}) => {
      'id': 'p1',
      'name': 'Jollof Plate',
      'description': 'Fresh and hot',
      'priceUsdc': 4.2,
      'priceGhs': priceGhs,
      'imageUrls': <String>[],
      'tags': <String>[],
      'preparationMins': 15,
    };

Map<String, dynamic> _productsPayload(Map<String, dynamic> product) => {
      'business': {'id': 'bp-1', 'name': 'Test Shop', 'category': 'RETAIL'},
      'hasStorefront': true,
      'products': [product],
    };

Future<void> _pumpStorefront(WidgetTester tester, Map<String, dynamic> product) async {
  final fake = _FakeStorefrontService(_productsPayload(product));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [storefrontServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(
        home: StorefrontScreen(businessProfileId: 'bp-1', businessName: 'Test Shop'),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  // The products section is a lazily-built sliver below the fold — drag the
  // screen's scroll view until it is built and visible.
  for (var i = 0; i < 10; i++) {
    if (tester.any(find.text('Jollof Plate'))) break;
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'storefront catalogue card: confirmed GHS price is displayed exactly — '
    'never the priceUsdc figure, never a bare \$',
    (tester) async {
      await _pumpStorefront(tester, _product(priceGhs: '25.50'));

      expect(find.text('GH₵25.50'), findsOneWidget, reason: 'exact server 2dp string verbatim');
      expect(find.text('Price unavailable'), findsNothing);
      // The payable priceUsdc (4.2) never renders as the listing price.
      expect(find.text('\$4.20'), findsNothing);
      expect(find.text('4.20 USDC'), findsNothing, reason: 'browse listing is GHS-only');
    },
  );

  testWidgets(
    'storefront catalogue card: missing GHS renders "Price unavailable" — no USDC substitute',
    (tester) async {
      await _pumpStorefront(tester, _product(priceGhs: null));

      expect(find.text('Price unavailable'), findsOneWidget);
      expect(find.text('GH₵'), findsNothing);
      expect(find.text('\$4.20'), findsNothing);
      expect(find.text('4.20'), findsNothing);
    },
  );

  testWidgets(
    'order sheet: payable amount carries the EXPLICIT USDC denomination; the '
    'GHS listing price is a separate labelled fact',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StorefrontOrderSheet(
                businessProfileId: 'bp-1',
                businessName: 'Test Shop',
                product: _product(priceGhs: '25.50'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Payable rail truth: explicit denomination everywhere the order
      // amount appears — never a bare '$'. The exact payable string renders
      // on the header row AND the Total value.
      expect(find.text('4.20 USDC'), findsNWidgets(2), reason: 'header + total payable amounts');
      expect(find.textContaining('\$'), findsNothing);
      // The GHS listing price: a SEPARATE labelled fact, never an
      // equivalence or conversion of the payable amount.
      expect(find.text('Listed: GH₵25.50'), findsOneWidget);
      expect(find.text('Place Order · 4.20 USDC'), findsOneWidget);
      expect(find.textContaining('Total:'), findsOneWidget);
    },
  );

  testWidgets(
    'order sheet: no GHS listing price → only the explicit USDC payable '
    'truth, no invented or converted GHS figure',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StorefrontOrderSheet(
                businessProfileId: 'bp-1',
                businessName: 'Test Shop',
                product: _product(priceGhs: null),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('4.20 USDC'), findsWidgets);
      expect(find.textContaining('GH₵'), findsNothing, reason: 'absent listing price is never invented');
      expect(find.textContaining('\$'), findsNothing);
    },
  );

  testWidgets(
    'listing-to-order journey: Add puts the USDC rail amount in the cart; the '
    'cart confirmation labels every amount USDC explicitly',
    (tester) async {
      final showCart = ValueNotifier<bool>(false);
      addTearDown(showCart.dispose);
      final fake = _FakeStorefrontService(_productsPayload(_product(priceGhs: '25.50')));

      // ONE scope across the whole journey: the cart the Add button fills
      // is the same cart the checkout confirmation reads.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storefrontServiceProvider.overrideWithValue(fake)],
          child: ValueListenableBuilder<bool>(
            valueListenable: showCart,
            builder: (context, cart, _) => MaterialApp(
              home: cart
                  ? const CartScreen()
                  : const StorefrontScreen(businessProfileId: 'bp-1', businessName: 'Test Shop'),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The journey starts at the listing: authoritative GHS, not USDC.
      for (var i = 0; i < 10; i++) {
        if (tester.any(find.text('GH₵25.50'))) break;
        await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('GH₵25.50'), findsOneWidget);

      // Tap Add on the listing card (drag once more so the card's bottom
      // row — price + Add button — is fully within the viewport).
      for (var i = 0; i < 6; i++) {
        final rect = tester.getRect(find.text('Add'));
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        if (rect.bottom < size.height && rect.top > 0) break;
        await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Jollof Plate added to cart'), findsOneWidget);

      // The cart carries the payable rail amount (priceUsdc) — financial
      // semantics unchanged.
      final container = ProviderScope.containerOf(
        tester.element(find.text('Jollof Plate added to cart')),
      );
      final cartState = container.read(cartProvider);
      expect(cartState.items, hasLength(1));
      expect(cartState.items.single.unitPrice, 4.2);

      // The order/checkout confirmation (CartScreen) labels the payable
      // amounts with their explicit denomination — never a bare '$'.
      showCart.value = true;
      await tester.pumpAndSettle();
      expect(find.textContaining('4.20 USDC'), findsWidgets);
      expect(find.textContaining('\$'), findsNothing);
    },
  );
}
