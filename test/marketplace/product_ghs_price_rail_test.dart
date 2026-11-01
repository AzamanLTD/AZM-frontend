// test/marketplace/product_ghs_price_rail_test.dart
//
// Regression proofs for the Marketplace product GHS price rail (follow-up
// review §3) — the FE side of BE PR #359's additive priceGhs contract:
//   • BusinessProduct.fromJson STRICTLY parses priceGhs: only a non-empty
//     String matching the canonical exact-2dp contract is accepted. Numbers,
//     1dp/3dp, exponents, blanks and wrong types are ABSENT (null), never
//     stringified and never derived from priceUsdc.
//   • Rendering preference: a server-confirmed GHS price renders as
//     "GH₵<exact>"; a product WITHOUT one renders "Price unavailable" —
//     browse surfaces never fall back to the legacy USDC figure
//     (review 2026-10-18: the USDC fallback enshrined here earlier was a
//     presentation lie once GHS became the authoritative merchant price).
//   • No USDC→GHS conversion ever happens on browse surfaces.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/product_card.dart';

BusinessProduct _product({dynamic priceGhs, double priceUsdc = 13.42}) {
  return BusinessProduct.fromJson(
    {
      'id': 'prod-1',
      'businessProfileId': 'biz-1',
      'name': 'Rail Product',
      'slug': 'rail-product',
      'priceUsdc': priceUsdc,
      'imageUrls': const <String>[],
      'isActive': true,
    }..['priceGhs'] = priceGhs,
  );
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BusinessProduct.priceGhs strict parse (BE #359 contract)', () {
    test('exact 2dp string accepted verbatim', () {
      expect(_product(priceGhs: '49.99').priceGhs, '49.99');
      expect(_product(priceGhs: '7.50').priceGhs, '7.50'); // trailing zero kept
      expect(_product(priceGhs: '120.00').priceGhs, '120.00');
    });

    test('missing / null → absent, never derived from priceUsdc', () {
      expect(_product().priceGhs, isNull);
      expect(_product(priceGhs: null).priceGhs, isNull);
      // Even with a USDC price present, no GHS figure is invented.
      expect(_product(priceUsdc: 99.99).priceGhs, isNull);
    });

    test('numeric JSON value → absent (string-only contract)', () {
      expect(_product(priceGhs: 49.99).priceGhs, isNull);
      expect(_product(priceGhs: 49).priceGhs, isNull);
      expect(_product(priceGhs: 49.999).priceGhs, isNull);
    });

    test(
      'malformed strings → absent (1dp, 3dp, exponent, currency symbol, blank)',
      () {
        expect(_product(priceGhs: '49.9').priceGhs, isNull);
        expect(_product(priceGhs: '49.999').priceGhs, isNull);
        expect(_product(priceGhs: '1e2').priceGhs, isNull);
        expect(_product(priceGhs: 'GH₵49.99').priceGhs, isNull);
        expect(_product(priceGhs: '  ').priceGhs, isNull);
        expect(_product(priceGhs: '-5.00').priceGhs, isNull);
      },
    );

    test('priceUsdc is untouched by the rail', () {
      expect(_product(priceGhs: '49.99').priceUsdc, 13.42);
      expect(_product().priceUsdc, 13.42);
    });
  });

  group('ProductCard GHS presentation preference', () {
    testWidgets('server-confirmed GHS renders as exact GH₵ string', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 170,
              child: ProductCard(
                product: _product(priceGhs: '49.99'),
                onOrder: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('GH₵49.99'), findsOneWidget);
      expect(find.textContaining('USDC'), findsNothing);
    });

    testWidgets(
      'no GHS price renders "Price unavailable" (no USDC fallback, no conversion)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 170,
                child: ProductCard(product: _product(), onOrder: (_) {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Price unavailable'), findsOneWidget);
        // No invented GHS figure and no legacy USDC price presentation.
        expect(find.textContaining('GH₵'), findsNothing);
        expect(find.textContaining('USDC'), findsNothing);
      },
    );
  });
}
