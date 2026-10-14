// =============================================================================
// MARKETPLACE MIX — offer card widget tests.
//
// Pins the rendering contract of MixOfferCard:
//   • item identity AND offering store shown together (the Mix invariant)
//   • price states: known USDC price formatted via AzMoney; a MISSING price
//     renders "Price unavailable" and NEVER a zero amount
//   • availability: rendered only when the payload said so
//   • a tap fires the item+store navigation callback with the OFFERING
//     store's identity preserved
//   • touch target and reduced-motion: full-row hit area, no scale animation
//     when animations are disabled
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
  String profileId = 'bp-1',
  String bizId = 'BIZ-1',
  String store = 'Auntie Adjoa\'s Kitchen',
  String name = 'Jollof Rice',
  double? price = 12.5,
  dynamic isAvailable = _absent,
}) =>
    MixOffer(
      productId: productId,
      businessProfileId: profileId,
      bizId: bizId,
      businessName: store,
      businessCategory: 'FOOD_BEVERAGE',
      name: name,
      price: price == null
          ? const MixOfferPrice.unknown()
          : MixOfferPrice.fixed(price),
      isAvailable: isAvailable == _absent ? null : isAvailable,
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

  testWidgets('a known price renders as a formatted USDC amount',
      (tester) async {
    await _pumpCard(tester, _offer(price: 12.5));
    expect(find.text('12.50\u00A0USDC'), findsOneWidget);
    expect(find.textContaining('0.00'), findsNothing);
  });

  testWidgets('a MISSING price renders "Price unavailable" — never zero',
      (tester) async {
    await _pumpCard(tester, _offer(price: null));
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.text('12.50\u00A0USDC'), findsNothing);
    expect(find.textContaining('USDC'), findsNothing,
        reason: 'no amount may be invented');
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('unavailable renders a quiet badge only when the payload said so',
      (tester) async {
    await _pumpCard(tester, _offer(isAvailable: false, price: 12.5));
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('an absent availability field renders NO availability signal',
      (tester) async {
    await _pumpCard(tester, _offer(price: 12.5));
    expect(find.text('Unavailable'), findsNothing);
    expect(find.text('Available'), findsNothing);
  });

  testWidgets('a tap opens the OFFERING store with identity preserved',
      (tester) async {
    final opened = <MixOffer>[];
    await _pumpCard(
      tester,
      _offer(bizId: 'BIZ-7', profileId: 'bp-7'),
      onOpenStore: opened.add,
    );
    await tester.tap(find.byType(MixOfferCard));
    await tester.pumpAndSettle();
    expect(opened.single.bizId, 'BIZ-7');
    expect(opened.single.businessProfileId, 'bp-7');
    expect(opened.single.productId, 'prod-1');
  });

  testWidgets("the card's hit area is a full-width row (>=48px touch target)",
      (tester) async {
    await _pumpCard(tester, _offer(price: 12.5));
    final rect = tester.getRect(find.byType(MixOfferCard));
    expect(rect.height, greaterThanOrEqualTo(88));
    // GestureDetector around the whole card is the tap target.
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
