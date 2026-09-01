import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/featured_products_section.dart';

BusinessProduct _fakeProduct(String id, String name, int orders) => BusinessProduct(
      id: id,
      businessProfileId: 'biz-1',
      name: name,
      slug: id,
      priceUsdc: 10,
      totalRevenue: orders * 10,
      imageUrls: const [],
      isActive: true,
      totalOrders: orders,
    );

void main() {
  testWidgets('orders preview by popular demand and exposes peek carousel',
      (tester) async {
    final products = <BusinessProduct>[
      _fakeProduct('p1', 'Quiet seller', 2),
      _fakeProduct('p2', 'Popular dish', 20),
      _fakeProduct('p3', 'Most popular dish', 35),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FeaturedProductsSection(
              bizId: 'biz-1',
              productLoader: (_) async => (
                products: products,
                hasMore: false,
                nextCursor: null,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Popular picks'), findsOneWidget);
    expect(find.text('Most popular dish'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Popular dish'), findsOneWidget);
  });
}
