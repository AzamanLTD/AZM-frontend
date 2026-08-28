import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/widgets/retail_collection_box_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final business = StorefrontBusinessInfo(
    name: 'Demo Retail',
    category: 'RETAIL',
    averageRating: 4.8,
  );

  testWidgets('retail collection opens quick look and adds to bag',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetailCollectionBoxWidget(
            business: business,
            props: const {
              'id': 'collection-1',
              'title': 'Staff Picks',
              'products': [
                {
                  'id': 'p1',
                  'name': 'Everyday Bag',
                  'price': 25,
                  'currency': 'GHS',
                },
              ],
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    expect(find.text('Quick look'), findsOneWidget);

    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Everyday Bag added to bag'), findsOneWidget);
  });

  testWidgets('bag opens and quantity can be changed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetailCollectionBoxWidget(
            business: business,
            props: const {
              'title': 'Staff Picks',
              'products': [
                {
                  'id': 'p1',
                  'name': 'Everyday Bag',
                  'price': 25,
                  'currency': 'GHS',
                },
              ],
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.text('Your bag'), findsOneWidget);
    expect(find.byTooltip('Increase quantity'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
  });
}
