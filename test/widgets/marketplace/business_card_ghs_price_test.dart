// =============================================================================
// BUSINESS CARD — GHS price anchor contract (final acceptance pass 2026-10-19).
//
// Pins the browse-price presentation contract on the marketplace business
// card's "from …" anchor:
//   • the cheapest authoritative GHS price is chosen NUMERICALLY — exact
//     2dp strings are display values, never lexicographic ordering keys
//     ('100.00' < '49.50' < '9.00' as text would pick the wrong anchor);
//   • a confirmed GHS price is displayed exactly, server string verbatim;
//   • without a server-confirmed GHS price the anchor says
//     "Price unavailable" — the legacy priceUsdc figure is NEVER rendered
//     as a substitute listing price on a browse surface (USDC stays the
//     payment/wallet rail truth, never a browse listing price).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/business_card.dart';

BusinessProduct _product(
  String id,
  String? priceGhs, {
  double priceUsdc = 4.2,
  bool isActive = true,
}) {
  return BusinessProduct(
    id: id,
    businessProfileId: 'bp-1',
    name: 'Item $id',
    slug: 'slug-$id',
    priceUsdc: priceUsdc,
    priceGhs: priceGhs,
    totalRevenue: 0,
    imageUrls: const [],
    isActive: isActive,
    totalOrders: 0,
  );
}

BusinessProfile _profile(List<BusinessProduct> products) {
  return BusinessProfile(
    id: 'bp-1',
    bizId: 'BIZ-TEST-1',
    businessName: 'Test Kitchen',
    category: 'FOOD_BEVERAGE',
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 0,
    completedEscrows: 0,
    userId: 1,
    totalVolume: 0,
    averageRating: 4.5,
    username: 'testkitchen',
    products: products,
  );
}

Future<void> _pumpCard(WidgetTester tester, BusinessProfile profile) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: BusinessCard(business: profile, onTap: () {}))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cheapest GHS price is chosen NUMERICALLY, never lexicographically '
    '(9.00 beats 49.50 and 100.00 even when text order says otherwise)',
    (tester) async {
      // Deliberately adversarial ordering: as TEXT, '100.00' < '49.50' < '9.00',
      // so a lexicographic sort would surface '100.00'. Only numeric
      // comparison yields the true cheapest: 9.00.
      await _pumpCard(tester, _profile([
        _product('p100', '100.00'),
        _product('p49', '49.50'),
        _product('p9', '9.00'),
      ]));

      expect(
        find.text('from GH₵9.00', findRichText: true),
        findsOneWidget,
        reason: 'the anchor must display the NUMERIC cheapest exact 2dp string',
      );
      expect(find.text('from GH₵100.00', findRichText: true), findsNothing);
      expect(find.text('from GH₵49.50', findRichText: true), findsNothing);
    },
  );

  testWidgets('a confirmed GHS price is displayed exactly, server string verbatim', (tester) async {
    await _pumpCard(tester, _profile([_product('p1', '49.50', priceUsdc: 123.45)]));

    expect(find.text('from GH₵49.50', findRichText: true), findsOneWidget);
    // The legacy USDC figure never appears anywhere on the browse card.
    expect(find.byType(RichText), findsWidgets);
    final allText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join(' ');
    expect(allText.contains('123.45'), isFalse);
    expect(allText.contains('USDC'), isFalse);
  });

  testWidgets(
    'no confirmed GHS price renders "Price unavailable" — never the priceUsdc fallback',
    (tester) async {
      await _pumpCard(tester, _profile([
        _product('p1', null, priceUsdc: 7.77),
        _product('p2', null, priceUsdc: 12.34),
      ]));

      expect(
        find.text('from Price unavailable', findRichText: true),
        findsOneWidget,
        reason: 'the anchor reports the missing GHS truth instead of a USDC substitute',
      );
      final allText = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .join(' ');
      expect(allText.contains('7.77'), isFalse);
      expect(allText.contains('12.34'), isFalse);
      expect(allText.contains('USDC'), isFalse);
    },
  );

  testWidgets(
    'a mixed catalogue anchors at the cheapest GHS-priced product; unpriced products never contribute',
    (tester) async {
      await _pumpCard(tester, _profile([
        _product('unpriced', null, priceUsdc: 0.01),
        _product('mid', '49.50'),
        _product('cheap', '9.00'),
        _product('inactive', '1.00', isActive: false),
      ]));

      expect(find.text('from GH₵9.00', findRichText: true), findsOneWidget);
      // The inactive product's cheaper GHS figure must not win the anchor.
      expect(find.text('from GH₵1.00', findRichText: true), findsNothing);
    },
  );
}
