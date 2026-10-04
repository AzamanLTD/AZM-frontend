import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/menu/menu_document.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product(String name, {List<String> tags = const []}) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'bp-1',
      name: name,
      slug: name.toLowerCase(),
      priceUsdc: 10,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: true,
      totalOrders: 0,
      tags: tags,
    );

BusinessProfile _business(String category, {List<BusinessProduct> products = const []}) => BusinessProfile(
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

Future<void> _pump(WidgetTester tester, MarketplaceVerticalExperienceStage stage) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [transitTripsProvider('bp-1').overrideWith((ref) async => const [])],
    child: MaterialApp(home: Scaffold(body: stage)),
  ));
  await tester.pump();
}

void main() {
  test('menuDocument is built from sections and filtered by the store query', () {
    final stage = MarketplaceVerticalExperienceStage(
      business: _business('FOOD_BEVERAGE'),
      colors: _colors,
      menuSections: [
        CatalogSection(
          id: 'mains',
          businessProfileId: 'bp-1',
          name: 'Mains',
          displayOrder: 0,
          isActive: true,
          products: [_product('Jollof Rice'), _product('Banku')],
        ),
      ],
      uncategorisedProducts: [_product('Water')],
      storeQuery: 'jol',
      now: DateTime(2026, 10, 5, 12),
    );
    final MenuDocument doc = stage.menuDocument;
    expect(doc.items.map((i) => i.product.name), ['Jollof Rice']);
  });

  testWidgets('retail shelf shows only products matching the store query', (tester) async {
    await _pump(
      tester,
      MarketplaceVerticalExperienceStage(
        business: _business('RETAIL', products: [_product('Sneakers'), _product('Backpack', tags: ['bag'])]),
        colors: _colors,
        onOpenCatalogView: () {},
        storeQuery: 'bag',
      ),
    );
    expect(find.byType(RetailCollectionBox), findsOneWidget);
    expect(find.text('Backpack'), findsOneWidget);
    expect(find.text('Sneakers'), findsNothing);
  });

  testWidgets('transit stage carries the journey thread at the search stage', (tester) async {
    await _pump(tester, MarketplaceVerticalExperienceStage(business: _business('LOGISTICS'), colors: _colors));
    expect(find.byKey(const ValueKey('journey_thread_search')), findsOneWidget);
    expect(find.text('Test Business'), findsWidgets);
  });
}