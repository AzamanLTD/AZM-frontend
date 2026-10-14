// =============================================================================
// MARKETPLACE MIX — offer card widget tests.
//
// Pins the rendering contract of MixOfferCard against the canonical
// discovery DTO model (backend PR #349):
//   • item identity AND offering store shown together (the Mix invariant)
//   • price states: a verified GHS price renders via AzMoney.ghsExact — the
//     EXACT 2dp string, never floated; absent/malformed/non-GHS payload
//     prices render "Price unavailable", never zero, never a USDC figure,
//     never "price on request"
//   • payment rail: capabilities.payableIn renders honestly (USDC chip);
//     a GHS listing price NEVER renders a GHS payment claim
//   • availability: rendered only when the payload said so (isAvailable /
//     sectionWindowOpen); never inferred from a price
//   • a tap fires the item+store navigation callback with the OFFERING
//     store's identity preserved
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_offer_card.dart';

const _absent = '__absent__';

MixOffer _offer({
  String productId = 'prod-1',
  String businessId = 'bp-1',
  String bizId = 'BIZ-1',
  String store = 'Auntie Adjoa\'s Kitchen',
  String name = 'Jollof Rice',
  MixOfferPrice price = const MixOfferPrice.fixedGhs('12.50'),
  dynamic isAvailable = _absent,
  dynamic sectionWindowOpen = _absent,
  List<String> payableIn = const ['USDC'],
}) =>
    MixOffer(
      productId: productId,
      businessId: businessId,
      bizId: bizId,
      businessName: store,
      businessCategory: 'FOOD_BEVERAGE',
      name: name,
      price: price,
      isAvailable: isAvailable == _absent ? null : isAvailable,
      sectionWindowOpen: sectionWindowOpen == _absent ? null : sectionWindowOpen,
      capabilities: MixOfferCapabilities(payableIn: payableIn),
    );

Future<void> _pumpCard(
  WidgetTester tester,
  MixOffer offer, {
  void Function(MixOffer)? onOpenStore,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [themeProvider.overrideWith((ref) => ThemeProvider())],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
                disableAnimations: disableAnimations,
                size: const Size(390, 844)),
            child: ListView(
              children: [
                MixOfferCard(
                  offer: offer,
                  onOpenStore:
                      onOpenStore ?? (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('item and offering store render together', (tester) async {
    await _pumpCard(
        tester, _offer(store: 'Auntie Adjoa\'s Kitchen', name: 'Jollof Rice'));
    expect(find.text('Jollof Rice'), findsOneWidget);
    expect(find.text("Auntie Adjoa's Kitchen"), findsOneWidget);
  });

  testWidgets('a verified GHS price renders EXACTLY, symbol + grouped amount',
      (tester) async {
    await _pumpCard(tester, _offer(price: const MixOfferPrice.fixedGhs('1240.42')));
    expect(find.text('GH₵\u00A01,240.42'), findsOneWidget);
  });

  testWidgets('the exact string survives to the pixel — "25.00" not "25.0"',
      (tester) async {
    await _pumpCard(tester, _offer(price: const MixOfferPrice.fixedGhs('25.00')));
    expect(find.text('GH₵\u00A025.00'), findsOneWidget);
  });

  testWidgets(
      'a MISSING price renders "Price unavailable" — never zero, never USDC',
      (tester) async {
    await _pumpCard(
        tester,
        _offer(
            price: const MixOfferPrice.unknown(),
            // hasUsdcListPrice may be true — never a price source.
            payableIn: const []));
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.textContaining('USDC'), findsNothing,
        reason: 'no amount may be invented from another currency');
    expect(find.textContaining('0.00'), findsNothing);
    expect(find.textContaining('request'), findsNothing,
        reason: '"price on request" is not a real state');
  });

  testWidgets(
      'the payment rail renders ONLY what the server reported (USDC chip)',
      (tester) async {
    await _pumpCard(tester, _offer());
    expect(find.byKey(const ValueKey('mix_chip_USDC')), findsOneWidget);
    expect(find.textContaining('GHS'), findsNothing,
        reason: 'a GHS listing price never claims GHS payment');
  });

  testWidgets('no payment-rail chip when the payload reports no rails',
      (tester) async {
    await _pumpCard(tester, _offer(payableIn: const []));
    expect(find.byKey(const ValueKey('mix_chip_USDC')), findsNothing);
  });

  testWidgets('unavailable renders a quiet badge only when the payload said so',
      (tester) async {
    await _pumpCard(tester, _offer(isAvailable: false));
    expect(find.byKey(const ValueKey('mix_chip_Unavailable')), findsOneWidget);
  });

  testWidgets('an absent availability field renders NO availability signal',
      (tester) async {
    await _pumpCard(tester, _offer());
    expect(find.byKey(const ValueKey('mix_chip_Unavailable')), findsNothing);
    expect(find.byKey(const ValueKey('mix_chip_Opens later')), findsNothing);
    expect(find.text('Available'), findsNothing);
  });

  testWidgets('a closed section window renders "Opens later"', (tester) async {
    await _pumpCard(tester, _offer(sectionWindowOpen: false));
    expect(find.byKey(const ValueKey('mix_chip_Opens later')), findsOneWidget);
  });

  testWidgets('a tap opens the OFFERING store with identity preserved',
      (tester) async {
    final opened = <MixOffer>[];
    await _pumpCard(
      tester,
      _offer(bizId: 'BIZ-7', businessId: 'bp-7'),
      onOpenStore: opened.add,
    );
    await tester.tap(find.byType(MixOfferCard));
    await tester.pumpAndSettle();
    expect(opened.single.bizId, 'BIZ-7');
    expect(opened.single.businessId, 'bp-7');
    expect(opened.single.productId, 'prod-1');
  });

  testWidgets("the card's hit area is a full-width row (>=48px touch target)",
      (tester) async {
    await _pumpCard(tester, _offer());
    final rect = tester.getRect(find.byType(MixOfferCard));
    expect(rect.height, greaterThanOrEqualTo(88));
    final hit = find.descendant(
        of: find.byType(MixOfferCard),
        matching: find.byType(GestureDetector));
    expect(hit, findsAtLeast(1));
  });

  testWidgets('a card with a missing image falls back gracefully',
      (tester) async {
    await _pumpCard(tester, _offer());
    expect(tester.takeException(), isNull);
  });
}
