import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';
import 'package:azaman/widgets/restaurant_menu_flip_book.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/widgets/marketplace/hotel_floor_plan_preview.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product(
  String name, {
  double price = 12,
  int orders = 0,
  List<String> tags = const [],
}) {
  return BusinessProduct(
    id: name.toLowerCase().replaceAll(' ', '-'),
    businessProfileId: 'bp-1',
    name: name,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    priceUsdc: price,
    totalRevenue: 0,
    imageUrls: const [],
    isActive: true,
    totalOrders: orders,
    tags: tags,
  );
}

BusinessProfile _business(
  String category, {
  List<BusinessProduct> products = const [],
}) {
  return BusinessProfile(
    id: 'bp-1',
    bizId: 'BIZ-1',
    businessName: 'Test Business',
    category: category,
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 0,
    completedEscrows: 0,
    userId: 1,
    totalVolume: 0,
    averageRating: 4.8,
    username: 'test-business',
    products: products,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required BusinessProfile business,
  VoidCallback? onOrder,
  VoidCallback? onCatalog,
  void Function(String)? onNavigate,
  List<CatalogSection> menuSections = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transitTripsProvider(business.id).overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MarketplaceVerticalExperienceStage(
            business: business,
            colors: _colors,
            onNavigate: onNavigate,
            onOpenOrderSheet: onOrder,
            onOpenCatalogView: onCatalog,
            menuSections: menuSections,
            onOrderProduct: (_) => onOrder?.call(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

CatalogSection _section(String name, List<BusinessProduct> products) {
  return CatalogSection(
    id: name.toLowerCase(),
    businessProfileId: 'bp-1',
    name: name,
    description: null,
    displayOrder: 0,
    isActive: true,
    products: products,
  );
}

void main() {
  testWidgets('retail businesses get the shelf experience', (tester) async {
    var catalogOpened = false;
    await _pump(
      tester,
      business: _business('RETAIL', products: [
        _product('Sneakers', orders: 40),
        _product('Backpack', orders: 12),
      ]),
      onCatalog: () => catalogOpened = true,
    );

    expect(find.text('Bestsellers'), findsOneWidget);
    expect(find.text('Shop the shelf'), findsOneWidget);
    expect(find.byType(RetailCollectionBox), findsOneWidget);

    await tester.tap(find.text('Open full catalog'));
    expect(catalogOpened, isTrue);
  });

  testWidgets('hotel businesses get the floor-plan experience', (tester) async {
    String? route;
    await _pump(
      tester,
      business: _business('HOSPITALITY', products: [
        _product('Room 101', price: 80, tags: ['Standard']),
        _product('Room 102', price: 120, tags: ['Deluxe']),
      ]),
      onNavigate: (value) => route = value,
    );

    expect(find.text('Explore the property'), findsOneWidget);
    expect(find.byType(HotelFloorPlanPreview), findsOneWidget);
    expect(find.text('Open rooms & availability'), findsOneWidget);

    await tester.tap(find.text('Open rooms & availability'));
    expect(route, '/business-market/bp-1/hotel-booking');
  });

  testWidgets('restaurant businesses keep the flip-book experience', (tester) async {
    await _pump(
      tester,
      business: _business('FOOD_BEVERAGE'),
      menuSections: [
        _section('Mains', [_product('Jollof Rice')]),
      ],
      onOrder: () {},
    );

    expect(find.byType(RestaurantMenuFlipBook), findsOneWidget);
  });

  testWidgets('transit businesses expose schedule fallback when no trips exist', (tester) async {
    await _pump(
      tester,
      business: _business('LOGISTICS'),
    );

    expect(find.text('No upcoming trips yet'), findsOneWidget);
  });
}
