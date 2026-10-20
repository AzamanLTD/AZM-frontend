import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product(String name, int orders) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'bp-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      priceUsdc: 12,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: true,
      totalOrders: orders,
    );

BusinessProfile _business(
  String category, {
  int completedEscrows = 0,
}) =>
    BusinessProfile(
      completedEscrows: completedEscrows,
      id: 'bp-1',
      bizId: 'BIZ-1',
      businessName: 'Test Business',
      category: category,
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: 4.7,
      username: 'test-business',
      products: [
        _product('Popular', 30),
        _product('Second', 10),
      ],
    );

Future<void> _pumpBar(WidgetTester tester, BusinessProfile business) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: SingleChildScrollView(
          child: CollapsibleBusinessBar(
            business: business,
            isExpanded: true,
            onToggle: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('restaurant expanded card labels the product rail as dishes',
      (tester) async {
    await _pumpBar(tester, _business('FOOD_BEVERAGE'));

    expect(find.text('Popular dishes'), findsOneWidget);
    expect(find.text('View menu'), findsWidgets);
  });

  testWidgets('retail expanded card labels the product rail as bestsellers',
      (tester) async {
    await _pumpBar(tester, _business('RETAIL'));

    expect(find.text('Bestsellers'), findsOneWidget);
    expect(find.text('View store'), findsWidgets);
  });

  // ── 2026-10-20 discovery refinement ──────────────────────────────────────
  // The listing card no longer shows prominent star ratings; the freed
  // space carries grounded facts (category, verified badge, order count).
  // Rating/review RECORDS remain — they surface on detail/review surfaces.

  testWidgets('the card shows NO star rating anywhere — collapsed or expanded',
      (tester) async {
    await _pumpBar(tester, _business('FOOD_BEVERAGE'));

    // No numeric rating text (fixture is 4.7).
    expect(find.text('4.7'), findsNothing);
    // No star icons in either the collapsed row or the expanded header.
    expect(
      find.byIcon(Icons.star_rounded, skipOffstage: false), findsNothing);
  });

  testWidgets('collapsed row surfaces the grounded category label',
      (tester) async {
    await _pumpBar(tester, _business('FOOD_BEVERAGE'));

    expect(find.text('Restaurants'), findsWidgets);
  });

  testWidgets('completed escrows surface as an honest order count, not reviews',
      (tester) async {
    await _pumpBar(tester, _business('FOOD_BEVERAGE', completedEscrows: 12));

    expect(find.text('· 12 orders'), findsOneWidget);
    // The escrow count is never mislabelled as a review count.
    expect(find.textContaining('12 reviews'), findsNothing);
    expect(find.text('4.9'), findsNothing);
  });
}
