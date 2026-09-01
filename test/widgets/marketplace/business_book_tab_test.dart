import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_book_tab.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product({bool active = true}) {
  return BusinessProduct(
    id: 'dish-1',
    businessProfileId: 'bp-1',
    name: 'Jollof Rice',
    slug: 'jollof-rice',
    priceUsdc: 12,
    totalRevenue: 0,
    imageUrls: const [],
    isActive: active,
    totalOrders: 0,
    tags: const [],
  );
}

BusinessProfile _business() {
  return BusinessProfile(
    id: 'bp-1',
    bizId: 'BIZ-1',
    businessName: 'Test Restaurant',
    category: 'FOOD_BEVERAGE',
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 0,
    completedEscrows: 0,
    userId: 1,
    totalVolume: 0,
    averageRating: 4.8,
    username: 'test-restaurant',
    products: const [],
  );
}

CatalogSection _section(BusinessProduct product) {
  return CatalogSection(
    id: 'mains',
    businessProfileId: 'bp-1',
    name: 'Mains',
    description: null,
    displayOrder: 0,
    isActive: true,
    products: [product],
  );
}

Map<String, dynamic> _experience({bool persistentTray = true}) => {
  return {
    'preset': 'DINING_JOURNEY',
    'commit': {
      'style': 'PAPER_RIP',
      'persistentTray': persistentTray,
    },
  };
}

void main() {
  testWidgets('persistent dining tray routes dish additions into canonical cart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    cart.clearCart();
    final business = _business();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => cart),
          storefrontExperienceProvider(business.id).overrideWith(
            (ref) async => _experience(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusinessBookTab(
              business: business,
              colors: _colors,
              onOrderProduct: (_) => fail('legacy ticket path should not run'),
              menuSections: [_section(_product())],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Jollof Rice'), findsOneWidget);
    expect(cart.state.itemCount, 0);

    await tester.tap(find.text('Jollof Rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to order'));
    await tester.pump();

    expect(cart.state.itemCount, 1);
    expect(cart.state.businessProfileId, business.id);
    expect(find.text('Open order tray'), findsOneWidget);
    expect(find.text('Jollof Rice added to your order tray.'), findsOneWidget);
  });

  testWidgets('disabled dining products do not enter the tray', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    cart.clearCart();
    final business = _business();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => cart),
          storefrontExperienceProvider(business.id).overrideWith(
            (ref) async => _experience(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusinessBookTab(
              business: business,
              colors: _colors,
              onOrderProduct: (_) => fail('legacy ticket path should not run'),
              menuSections: [_section(_product(active: false))],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Jollof Rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to order'));
    await tester.pump();

    expect(cart.state.itemCount, 0);
    expect(find.text('This dish is currently unavailable.'), findsOneWidget);
    expect(find.text('Open order tray'), findsNothing);
  });

  testWidgets('non-persistent dining experience keeps the existing ticket callback', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    cart.clearCart();
    final business = _business();
    var legacyCallbackCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => cart),
          storefrontExperienceProvider(business.id).overrideWith(
            (ref) async => _experience(persistentTray: false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusinessBookTab(
              business: business,
              colors: _colors,
              onOrderProduct: (_) => legacyCallbackCount++,
              menuSections: [_section(_product())],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Jollof Rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to order'));
    await tester.pump();

    expect(legacyCallbackCount, 1);
    expect(cart.state.itemCount, 0);
    expect(find.text('Open order tray'), findsNothing);
  });
}
