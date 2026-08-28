import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetailProduct', () {
    test('parses flexible product payloads safely', () {
      final product = RetailProduct.fromJson({
        'productId': 'p1',
        'title': 'Weekend Essentials',
        'priceUsdc': '125.5',
        'currency': 'GHS',
        'images': ['https://example.com/a.jpg'],
        'tags': ['popular', 'bundle'],
        'variants': {'size': ['M', 'L']},
      });

      expect(product.id, 'p1');
      expect(product.name, 'Weekend Essentials');
      expect(product.price, 125.5);
      expect(product.formattedPrice, 'GH₵125.50');
      expect(product.imageUrls, ['https://example.com/a.jpg']);
      expect(product.tags, ['popular', 'bundle']);
      expect(product.variants['size'], ['M', 'L']);
    });

    test('does not claim availability when server marks item inactive', () {
      final product = RetailProduct.fromJson({
        'id': 'p2',
        'name': 'Sold out',
        'price': 20,
        'isActive': false,
      });

      expect(product.available, isFalse);
      expect(product.formattedPrice, contains('20.00'));
    });
  });

  testWidgets('collection box renders products and opens quick look', (tester) async {
    RetailProduct? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetailCollectionBox(
            collection: const RetailCollection(
              id: 'c1',
              title: 'Staff Picks',
              products: [
                RetailProduct(id: 'p1', name: 'Bag', price: 20, currency: 'GHS'),
              ],
            ),
            onProductTap: (product) => selected = product,
          ),
        ),
      ),
    );

    expect(find.text('Staff Picks'), findsOneWidget);
    expect(find.text('Bag'), findsOneWidget);
    await tester.tap(find.text('Bag'));
    expect(selected?.id, 'p1');
  });

  testWidgets('quick look uses accessible close control', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetailQuickLookSheet(
            product: const RetailProduct(
              id: 'p1',
              name: 'Bag',
              price: 20,
              currency: 'GHS',
            ),
            onAddToCart: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Quick look'), findsOneWidget);
    expect(find.text('GH₵20.00'), findsOneWidget);
  });
}
