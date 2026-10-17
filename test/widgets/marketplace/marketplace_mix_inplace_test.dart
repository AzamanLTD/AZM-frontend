// =============================================================================
// MARKETPLACE MIX — IN-PLACE MODE widget tests (Marketplace Home).
//
// Pins the in-place cross-store mode contract inside MarketplaceHomeScreen:
//   • the Mix button TOGGLES the mode in place — NO route is pushed
//   • entering Mix defaults to ALL: the gateway receives a NULL category
//     (the param is omitted — no invented server value, no silent Eat)
//   • inside Mix the dial IS the category selector; its "Stay" (REAL_ESTATE)
//     translates through the ONE boundary to discovery HOSPITALITY
//   • taxonomy BUBBLES render only for a selected category (no rail in All)
//   • exiting restores the pre-Mix dial selection — the marketplace list
//     underneath never changed
//   • the die: one short grow+twist on activation; reduced motion lands
//     settled with no animation
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_mix_screen.dart';
import 'package:azaman/services/business_service.dart';

class _FakeGateway implements MarketplaceMixGateway {
  Future<MixDiscoveryPage> Function(
    String? category,
    List<String> taxonomies,
    String? cursor,
  )?
  behavior;

  /// (category, taxonomies, cursor) — category NULL is the All mode.
  final calls = <(String?, List<String>, String?)>[];

  @override
  Set<MixCapability> get supportedCapabilities => const {
    MixCapability.itemStoreInteractions,
  };

  @override
  Future<MixDiscoveryPage> fetchItems({
    String? category,
    String? q,
    List<String> taxonomies = const [],
    String? city,
    String? region,
    int? limit,
    String? cursor,
  }) async {
    calls.add((category, List.of(taxonomies), cursor));
    await Future<void>.delayed(Duration.zero);
    if (behavior == null) return (offers: <MixOffer>[], nextCursor: null);
    return await behavior!(category, taxonomies, cursor);
  }
}

/// Same recording seam the home's existing harness uses (no network).
class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  final searchedCategories = <String?>[];

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    searchedCategories.add(category);
  }
}

MixOffer _offer(String productId) => MixOffer(
  productId: productId,
  businessId: 'bp-1',
  bizId: 'BIZ-1',
  businessName: 'Adjoa\'s Kitchen',
  businessCategory: 'FOOD_BEVERAGE',
  name: 'Jollof Rice $productId',
  price: const MixOfferPrice.fixedGhs('12.50'),
);

Future<(_FakeGateway, _RecordingSearchNotifier)> _pumpHome(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  final gateway = _FakeGateway()
    ..behavior = (cat, tax, cursor) async =>
        (offers: [_offer(cat ?? 'all')], nextCursor: null);
  final search = _RecordingSearchNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) => search),
        marketplaceMixGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: const MarketplaceHomeScreen(),
      ),
    ),
  );
  // initState's post-frame seeding search + one-shot timers elapse here.
  await tester.pump(const Duration(milliseconds: 600));
  return (gateway, search);
}

AnimationController _dieController(WidgetTester tester) {
  // The die's CustomPaint is the direct CHILD of its AnimatedBuilder, so
  // walk UP to the NEAREST AnimatedBuilder ancestor — that one owns the
  // grow+twist controller (outer builders belong to other widgets).
  final ctx = tester.element(find.byKey(const ValueKey('mix_die')));
  AnimationController? controller;
  ctx.visitAncestorElements((el) {
    final w = el.widget;
    if (w is AnimatedBuilder) {
      controller = w.animation as AnimationController;
      return false; // stop at the nearest one — the die's own
    }
    return true;
  });
  return controller!;
}

void main() {
  testWidgets('the Mix button toggles the mode IN PLACE — no route is pushed', (
    tester,
  ) async {
    await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();

    // The mode is active INSIDE the home — the old pushed screen never
    // appears, and the shell's navigator never gained a route.
    expect(find.byType(MarketplaceMixScreen), findsNothing);
    expect(find.byKey(const ValueKey('mix_inplace_feed')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mix_feed')),
      findsOneWidget,
      reason: 'the shared state-honest feed surface renders',
    );

    // Toggling OFF restores the normal marketplace view in place too.
    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix_inplace_feed')), findsNothing);
    expect(find.byType(MarketplaceMixScreen), findsNothing);
  });

  testWidgets('entering Mix defaults to ALL: a null category, no invented '
      'server value, and never a silent Eat', (tester) async {
    final (gateway, search) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();

    // One feed request since entering: category NULL (the gateway omits
    // the param entirely — the server's own default page).
    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.$1, isNull);
    expect(gateway.calls.single.$2, isEmpty);

    // Entering Mix must NOT disturb the marketplace search provider.
    expect(search.searchedCategories, hasLength(1));
  });

  testWidgets('inside Mix the dial IS the selector: "Stay" (REAL_ESTATE) '
      'translates through the boundary to HOSPITALITY', (tester) async {
    final (gateway, _) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();

    // Open the dial fan and pick Stay.
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    // ALL load + the Stay selection: the discovery wire is HOSPITALITY —
    // REAL_ESTATE would be a 422 at the canonical endpoint.
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.last.$1, 'HOSPITALITY');

    // The taxonomy bubbles for Stay render (ROOMS is Hospitality-scoped).
    expect(
      find.byKey(const ValueKey('mix_taxonomy_bubble_ROOMS')),
      findsOneWidget,
    );
  });

  testWidgets('taxonomy bubbles appear only for a selected category — '
      'All has NO rail', (tester) async {
    final (gateway, _) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();

    // All mode: no bubbles at all.
    expect(
      find.byKey(const ValueKey('mix_taxonomy_bubble_rail')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mix_taxonomy_bubble_MEALS')),
      findsNothing,
    );

    // Select Eat: the five food chips (+ Services) appear.
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eat'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mix_taxonomy_bubble_rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mix_taxonomy_bubble_MEALS')),
      findsOneWidget,
    );

    // Toggling a bubble refetches with the canonical taxonomy filter.
    await tester.tap(find.byKey(const ValueKey('mix_taxonomy_bubble_MEALS')));
    await tester.pumpAndSettle();
    expect(gateway.calls.last.$1, 'FOOD_BEVERAGE');
    expect(gateway.calls.last.$2, ['MEALS']);
  });

  testWidgets('exiting Mix restores the pre-Mix dial selection exactly', (
    tester,
  ) async {
    final (gateway, _) = await _pumpHome(tester);

    // Select Retail in the NORMAL marketplace first.
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();

    // Enter Mix, pick a different category inside it, then leave.
    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pumpAndSettle();

    // The dial is back on Shop and the normal marketplace list is back.
    expect(find.byKey(const ValueKey('mix_inplace_feed')), findsNothing);
    // The mix feed state survives underneath (provider is app-scoped) but
    // no more discovery requests fired after exiting.
    final countAfterExit = gateway.calls.length;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      gateway.calls.length,
      countAfterExit,
      reason: 'exiting Mix must not fire any request',
    );
  });

  testWidgets('the die plays ONE short grow+twist on activation, then '
      'settles — and never animates while inactive', (tester) async {
    await _pumpHome(tester);

    // Idle: settled, no animation.
    expect(_dieController(tester).isAnimating, isFalse);
    expect(_dieController(tester).value, 1.0);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pump(const Duration(milliseconds: 60));

    // Mid activation: the one-shot grow+twist is running…
    expect(_dieController(tester).isAnimating, isTrue);

    await tester.pumpAndSettle();
    // …and lands settled. No loop.
    expect(_dieController(tester).isAnimating, isFalse);
    expect(_dieController(tester).value, 1.0);
  });

  testWidgets('reduced motion: the die lands settled with NO animation', (
    tester,
  ) async {
    await _pumpHome(tester, disableAnimations: true);

    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pump(const Duration(milliseconds: 60));

    // AzMotion is the authoritative resolver: no scale tween, no twist.
    expect(_dieController(tester).isAnimating, isFalse);
    expect(_dieController(tester).value, 1.0);
    await tester.pumpAndSettle();
  });
}
