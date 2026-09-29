import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_order_mode.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_book_tab.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/widgets/book/flip_book.dart';
import 'package:azaman/widgets/marketplace/restaurant_order_mode_switch.dart';
import 'package:azaman/widgets/marketplace/restaurant_tray_rail.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product() => BusinessProduct(
  id: 'dish-1',
  businessProfileId: 'bp-1',
  name: 'Jollof Rice',
  slug: 'jollof-rice',
  priceUsdc: 12,
  totalRevenue: 0,
  imageUrls: const [],
  isActive: true,
  totalOrders: 0,
  tags: const [],
);

BusinessProfile _business() => BusinessProfile(
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

CatalogSection _section() => CatalogSection(
  id: 'mains',
  businessProfileId: 'bp-1',
  name: 'Mains',
  description: null,
  displayOrder: 0,
  isActive: true,
  products: [_product()],
);

Map<String, dynamic> _experience() => {
  'preset': 'DINING_JOURNEY',
  'commit': {'style': 'PAPER_RIP', 'persistentTray': true},
};

Future<void> _openDish(WidgetTester tester) async {
  final book = tester.state<FlipBookState>(find.byType(FlipBook));
  // This fixture has one menu page after the cover. Resetting to the cover
  // makes repeated calls deterministic after prior mode-routing assertions.
  book.turnBackward();
  await tester.pumpAndSettle();
  book.turnForward();
  await tester.pumpAndSettle();
  await tester.tap(find.text('Jollof Rice').first);
  await tester.pumpAndSettle();
}

void main() {
  group('RestaurantOrderMode', () {
    test('labels and cart notes are stable', () {
      expect(RestaurantOrderMode.dineIn.label, 'Dine-in');
      expect(RestaurantOrderMode.takeaway.label, 'Takeaway');
      expect(RestaurantOrderMode.delivery.label, 'Delivery');
      expect(RestaurantOrderMode.dineIn.cartNote, isNull);
      expect(RestaurantOrderMode.takeaway.cartNote, isNull);
      expect(RestaurantOrderMode.delivery.cartNote, 'Delivery');
    });

    test('icons are distinct per mode', () {
      expect(
        RestaurantOrderMode.values.map((mode) => mode.icon).toSet().length,
        3,
      );
    });
  });

  group('restaurantBuildProgress', () {
    test('no options means complete', () {
      expect(
        restaurantBuildProgress(
          hasVariants: false,
          sizeChosen: false,
          requiredGroupsSatisfied: const [],
        ),
        1.0,
      );
    });

    test('variants only', () {
      expect(
        restaurantBuildProgress(
          hasVariants: true,
          sizeChosen: false,
          requiredGroupsSatisfied: const [],
        ),
        0.0,
      );
      expect(
        restaurantBuildProgress(
          hasVariants: true,
          sizeChosen: true,
          requiredGroupsSatisfied: const [],
        ),
        1.0,
      );
    });

    test('required groups only', () {
      expect(
        restaurantBuildProgress(
          hasVariants: false,
          sizeChosen: false,
          requiredGroupsSatisfied: const [false, false],
        ),
        0.0,
      );
      expect(
        restaurantBuildProgress(
          hasVariants: false,
          sizeChosen: false,
          requiredGroupsSatisfied: const [true, false],
        ),
        0.5,
      );
      expect(
        restaurantBuildProgress(
          hasVariants: false,
          sizeChosen: false,
          requiredGroupsSatisfied: const [true, true],
        ),
        1.0,
      );
    });

    test('mixed variants and groups', () {
      expect(
        restaurantBuildProgress(
          hasVariants: true,
          sizeChosen: true,
          requiredGroupsSatisfied: const [false],
        ),
        0.5,
      );
      expect(
        restaurantBuildProgress(
          hasVariants: true,
          sizeChosen: false,
          requiredGroupsSatisfied: const [true],
        ),
        0.5,
      );
      expect(
        restaurantBuildProgress(
          hasVariants: true,
          sizeChosen: true,
          requiredGroupsSatisfied: const [true],
        ),
        1.0,
      );
    });
  });

  testWidgets(
    'order mode switch emits delivery and disables unavailable dine-in',
    (tester) async {
      RestaurantOrderMode? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestaurantOrderModeSwitch(
              selected: RestaurantOrderMode.takeaway,
              colors: _colors,
              dineInEnabled: false,
              onChanged: (mode) => changed = mode,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Dine-in'));
      await tester.pump();
      expect(changed, isNull);
      await tester.tap(find.text('Delivery'));
      await tester.pump();
      expect(changed, RestaurantOrderMode.delivery);
    },
  );

  testWidgets('dine-in host defaults to table mode and takeaway switches to shared cart',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    final business = _business();
    var dineInAdds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => cart),
          storefrontExperienceProvider(business.id).overrideWith(
            (ref) async => _experience(),
          ),
          storefrontProductsProvider(business.id).overrideWith(
            (ref) async => <String, dynamic>{'products': <dynamic>[]},
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusinessBookTab(
              business: business,
              colors: _colors,
              dineInContext: 'Table 4',
              onDineInAddToTab: (product, selections, quantity) async {
                dineInAdds++;
              },
              menuSections: [_section()],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Dine-in'), findsOneWidget);
    expect(find.text('Table 4'), findsOneWidget);

    await _openDish(tester);
    await tester.tap(find.textContaining('Add to tray').first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(dineInAdds, 1);
    expect(cart.state.itemCount, 0);

    await tester.tap(find.text('Takeaway'));
    await tester.pump();
    expect(find.text('Table 4'), findsNothing);

    await _openDish(tester);
    await tester.tap(find.textContaining('Add to tray').first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(dineInAdds, 1);
    expect(cart.state.itemCount, 1);
    expect(cart.state.items.single.notes, isNull);
  });

  testWidgets('restaurant tray rail expands and mutates canonical cart lines',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Test Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 12,
      quantity: 1,
      experiencePreset: 'DINING_JOURNEY',
    );

    var opened = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cartProvider.overrideWith((ref) => cart)],
        child: MaterialApp(
          home: Scaffold(
            body: RestaurantTrayRail(
              onOpen: () => opened = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('restaurant-tray-rail-collapsed')), findsOneWidget);

    // Touch slop consumes ~20px of the gesture before the handler sees a
    // delta, so drag well past the 44px expansion threshold.
    await tester.drag(
      find.byKey(const ValueKey('restaurant-tray-rail-collapsed')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('restaurant-tray-rail-expanded')), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(cart.state.items.single.quantity, 2);

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pump();
    expect(cart.state.items.single.quantity, 1);

    await tester.tap(find.text('Order tray'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('delivery mode reaches the shared cart with the delivery note',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartNotifier();
    final business = _business();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => cart),
          storefrontExperienceProvider(business.id).overrideWith(
            (ref) async => _experience(),
          ),
          storefrontProductsProvider(business.id).overrideWith(
            (ref) async => <String, dynamic>{'products': <dynamic>[]},
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusinessBookTab(
              business: business,
              colors: _colors,
              onOrderProduct: (_) => fail('legacy ticket path should not run'),
              menuSections: [_section()],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Delivery'));
    await tester.pump();
    await _openDish(tester);
    await tester.tap(find.textContaining('Add to tray').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(cart.state.itemCount, 1);
    expect(cart.state.businessProfileId, business.id);
    expect(cart.state.items.single.notes, 'Delivery');
  });
}
