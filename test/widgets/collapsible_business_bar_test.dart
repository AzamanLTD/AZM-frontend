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

BusinessProfile _business(String category) => BusinessProfile(
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
}
