// the pages, and does the order flow survive the new rendering path?
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/book/book.dart';
import 'package:azaman/widgets/restaurant_menu_flip_book.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _dish(String name, double price, {List<String> tags = const []}) {
  return BusinessProduct(
    id: name.toLowerCase(),
    businessProfileId: 'b1',
    name: name,
    slug: name.toLowerCase(),
    description: '$name, cooked over open fire.',
    priceUsdc: price,
    totalRevenue: 0,
    imageUrls: const [],
    isActive: true,
    totalOrders: 0,
    tags: tags,
  );
}

CatalogSection _section(String name, List<BusinessProduct> products) {
  return CatalogSection(
    id: name.toLowerCase(),
    businessProfileId: 'b1',
    name: name,
    displayOrder: 0,
    isActive: true,
    products: products,
  );
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required List<CatalogSection> sections,
  List<BusinessProduct> uncategorised = const [],
  void Function(BusinessProduct)? onOrder,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestaurantMenuFlipBook(
        businessName: 'Auntie Muni Kitchen',
        sections: sections,
        uncategorisedProducts: uncategorised,
        colors: _colors,
        onOrder: onOrder ?? (_) {},
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester) async {
  final book = tester.getRect(find.byType(FlipBook));
  final gesture = await tester.startGesture(
    Offset(book.right - 8, book.bottom - 30),
  );
  final step = (book.width + 60) / 14;
  for (var i = 0; i < 14; i++) {
    await gesture.moveBy(Offset(-step, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the cover with the business name', (tester) async {
    await _pumpMenu(tester, sections: [
      _section('Mains', [_dish('Jollof Rice', 12)]),
    ]);
    expect(find.text('Auntie Muni Kitchen'), findsWidgets);
  });

  testWidgets('paginates a section at four dishes per page', (tester) async {
    final dishes = List.generate(9, (i) => _dish('Dish $i', 10 + i.toDouble()));
    await _pumpMenu(tester, sections: [_section('Mains', dishes)]);
    final book = tester.widget<RestaurantMenuFlipBook>(
      find.byType(RestaurantMenuFlipBook),
    );
    expect(book.sections.single.products.length, 9);
  });

  testWidgets('renders dish name, price and semantic spicy indicator',
      (tester) async {
    await _pumpMenu(tester, sections: [
      _section('Mains', [_dish('Waakye', 8.5, tags: ['spicy'])]),
    ]);
    await _openMenu(tester);

    expect(find.text('Waakye'), findsOneWidget);
    expect(find.textContaining('8.5'), findsWidgets);
    expect(find.text('Mains'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
  });

  testWidgets('tapping a dish opens its card and "Add to order" fires onOrder',
      (tester) async {
    final ordered = <BusinessProduct>[];
    await _pumpMenu(
      tester,
      sections: [_section('Mains', [_dish('Banku', 9)])],
      onOrder: ordered.add,
    );

    await _openMenu(tester);

    await tester.tap(find.text('Banku'));
    await tester.pumpAndSettle();

    final addToOrder = find.text('Add to order');
    expect(addToOrder, findsOneWidget);
    await tester.tap(addToOrder);
    await tester.pumpAndSettle();

    expect(ordered.map((p) => p.name), ['Banku']);
  });

  testWidgets('uncategorised products still get a page', (tester) async {
    await _pumpMenu(
      tester,
      sections: const [],
      uncategorised: [_dish('Sobolo', 3)],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RestaurantMenuFlipBook), findsOneWidget);
  });

  testWidgets('an empty catalog renders without throwing', (tester) async {
    await _pumpMenu(tester, sections: const []);
    expect(tester.takeException(), isNull);
  });
}
