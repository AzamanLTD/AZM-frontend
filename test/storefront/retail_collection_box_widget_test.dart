import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/widgets/retail_collection_box_widget.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final business = StorefrontBusinessInfo(
    name: 'Demo Retail',
    category: 'RETAIL',
    averageRating: 4.8,
  );

  Widget buildWidget({required List<Map<String, dynamic>> products}) {
    // NEW-B: tapping a product opens the quick-look sheet on the AzamanSheet
    // grammar, and `AzSheetSurface` is a ConsumerWidget that reads
    // `themeProvider`. Before the migration this subtree needed no
    // ProviderScope, so the test now has to provide one — see §I.10 of the
    // brief: adopting the grammar makes a sheet require a scope.
    return ProviderScope(
      child: MaterialApp(
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
      ),
    );
  }

  Future<void> openQuickLook(WidgetTester tester) async {
    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    expect(find.text('Quick look'), findsOneWidget);
  }

  /// Scrolls the quick-look sheet until [finder] is on screen.
  ///
  /// NEW-B: the quick look is a Panel that opens at the 45% rest detent, so
  /// content below that fold is genuinely off-screen and `tester.tap` will
  /// hit the sheet surface instead of the widget. A user scrolls to reach a
  /// control; the test has to as well. This replaces the pre-migration
  /// behaviour, where the sheet sized itself to its content and every control
  /// was always visible.
  ///
  /// [finder] is expected to already be mounted — every Panel body is inside
  /// the sheet's viewport, just clipped. Scrolling is therefore only needed to
  /// move it into the *visible* band, and `scrollUntilVisible` is used rather
  /// than `dragUntilVisible` so a control that is already on screen is left
  /// exactly where it is.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final element = finder.evaluate().firstOrNull;
    if (element == null) return;
    await tester.scrollUntilVisible(
      finder,
      80.0,
      scrollable: find.descendant(
        of: find.byType(AzSheetSurface),
        matching: find.byType(Scrollable),
      ).last,
    );
    await tester.pumpAndSettle();
  }

  Finder variantField(String label) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == label,
    );
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

    await reveal(tester, variantField('Color'));
    await tester.tap(variantField('Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black').last);
    await tester.pumpAndSettle();

    await reveal(tester, variantField('Size'));
    await tester.tap(variantField('Size'));
    await tester.pumpAndSettle();
    // The Size menu opens as an overlay above the sheet. After the Color
    // round-trip the sheet has scrolled, so the overlay's own items are
    // asserted rather than assumed to share the field's position.
    expect(find.text('Large'), findsWidgets);
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('Black'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);

    // NEW-B: Add to bag is pinned below the scroll area (§I.8.3), so it needs
    // no reveal even though the variant fields above it do.
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Color: Black · Size: Large'),
      findsOneWidget,
    );
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
