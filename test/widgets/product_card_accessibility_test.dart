import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/product_card.dart';

void main() {
  testWidgets('product image exposes a semantic label', (tester) async {
    final product = BusinessProduct(
      id: 'product-1',
      name: 'Handmade Bowl',
      priceUsdc: 12.5,
      imageUrls: const [],
      estimatedDelivery: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: product,
              onOrder: (_) {},
            ),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('product-image-product-1')),
    );
    expect(semantics.label, contains('Handmade Bowl'));
  });
}
