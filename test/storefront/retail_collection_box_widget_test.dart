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

  Widget buildWidget({required List<Map<String, dynamic>> products}) {
    return MaterialApp(
      home: Scaffold(
        body: RetailCollectionBoxWidget(
          business: business,
          props: {
            'id': 'collection-1',
            'title': 'Staff Picks',
            'products': products,
          },
        ),
      ),
    );
  }

  Future<void> openQuickLook(WidgetTester tester) async {
    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    expect(find.text('Quick look'), findsOneWidget);
  }

  testWidgets('retail collection opens quick look and adds to bag',
      (tester) async {
    await tester.pumpWidget(buildWidget(products: [
      {
        'id': 'p1',
        'name': 'Everyday Bag',
        'price': 25,
        'currency': 'GHS',
      },
    ]));

    await openQuickLook(tester);
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Everyday Bag added to bag'), findsOneWidget);
  });

  testWidgets('quick look preserves multiple variant selections',
      (tester) async {
    await tester.pumpWidget(buildWidget(products: [
      {
        'id': 'p1',
        'name': 'Everyday Bag',
        'price': 25,
        'currency': 'GHS',
        'variants': {
          'Color': ['Black', 'Brown'],
          'Size': ['Small', 'Large'],
        },
      },
    ]));

    await openQuickLook(tester);
    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.text('Color: Black · Size: Large'), findsOneWidget);
  });

  testWidgets('bag opens and quantity can be changed', (tester) async {
    await tester.pumpWidget(buildWidget(products: [
      {
        'id': 'p1',
        'name': 'Everyday Bag',
        'price': 25,
        'currency': 'GHS',
      },
    ]));

    await openQuickLook(tester);
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
