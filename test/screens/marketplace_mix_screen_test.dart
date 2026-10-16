// =============================================================================
// MARKETPLACE MIX — screen widget tests (canonical discovery endpoint).
//
// Pins the full screen experience against `GET /api/discovery/items`:
//   • category rail + canonical taxonomy chip rail (wire-exact chips only)
//   • the feed renders item + offering store together, in SERVER order
//   • loading skeletons; failed + retry; legitimate empty feed; DISABLED
//     (404 — distinct from empty); INVALID REQUEST (422) with clear-filters
//   • switching categories/toggling chips reloads the feed; paging appends
//   • navigation: tapping an offer records the interaction and pushes the
//     OFFERING store route with the store identity preserved
//   • bottom clearance: feed insets clear the system bottom safe area
//     (pushed route sits above the nav band)
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_mix_screen.dart';
import 'package:azaman/theme/az_space.dart';

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway();

  Future<MixDiscoveryPage> Function(
    String category,
    List<String> taxonomies,
    String? cursor,
  )?
  behavior;
  final calls = <(String, List<String>, String?)>[];

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
    calls.add((category ?? '', List.of(taxonomies), cursor));
    await Future<void>.delayed(Duration.zero);
    if (behavior == null) return (offers: <MixOffer>[], nextCursor: null);
    return await behavior!(category ?? '', taxonomies, cursor);
  }
}

MixOffer _offer(
  String productId,
  String bizId, {
  String name = 'Jollof Rice',
  String businessId = 'bp-1',
  String store = 'Adjoa\'s Kitchen',
  MixOfferPrice price = const MixOfferPrice.fixedGhs('12.50'),
}) => MixOffer(
  productId: productId,
  businessId: businessId,
  bizId: bizId,
  businessName: store,
  businessCategory: 'FOOD_BEVERAGE',
  name: name,
  price: price,
);

class _RecordingTapRecorder implements MixTapRecorder {
  final taps =
      <({String businessProfileId, String productId, String? mixCategory})>[];

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    String? mixCategory,
  }) {
    taps.add((
      businessProfileId: businessProfileId,
      productId: productId,
      mixCategory: mixCategory,
    ));
  }
}

Widget _app({required _FakeGateway gateway, _RecordingTapRecorder? recorder}) {
  return ProviderScope(
    overrides: [
      themeProvider.overrideWith((ref) => ThemeProvider()),
      marketplaceMixGatewayProvider.overrideWithValue(gateway),
      if (recorder != null)
        marketplaceMixProvider.overrideWith(
          (ref) => MarketplaceMixNotifier(
            gateway: ref.watch(marketplaceMixGatewayProvider),
            recorder: recorder,
          ),
        ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('shell', key: Key('shell'))),
            ),
          ),
          GoRoute(
            path: '/business-market/mix',
            builder: (_, __) => const MarketplaceMixScreen(),
          ),
          GoRoute(
            path: '/business/:bizId',
            builder: (context, state) => Scaffold(
              body: Center(
                key: const Key('store-detail'),
                child: Text('store ${state.pathParameters['bizId']}'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester, {
  _FakeGateway? gateway,
  _RecordingTapRecorder? recorder,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    _app(gateway: gateway ?? _FakeGateway(), recorder: recorder),
  );
  await tester.pump();
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push<void>(
        MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Mix screen shows a category-first header and rails', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          (offers: [_offer('a1', 'BIZ-A')], nextCursor: null);
    await _open(tester, gateway: g);

    expect(find.text('Marketplace Mix'), findsOneWidget);
    // ALL is the honest default: no invented Eat bias in the copy or the
    // request (the gateway omits the category param entirely).
    expect(find.text('Browse items across every store'), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_category_ALL')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mix_category_FOOD_BEVERAGE')),
      findsOneWidget,
    );
    // No taxonomy rail in All mode — an unfiltered feed has no relevant
    // chips (the provider returns none for a null wire).
    expect(find.byKey(const ValueKey('mix_taxonomy_MEALS')), findsNothing);

    // Selecting Eat reveals the canonical FOOD_BEVERAGE chips (+ Services).
    await tester.tap(find.byKey(const ValueKey('mix_category_FOOD_BEVERAGE')));
    await tester.pumpAndSettle();
    expect(find.text('Browse eat across every store'), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_taxonomy_MEALS')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_taxonomy_DRINKS')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_taxonomy_ROOMS')), findsNothing);
    expect(
      find.byKey(const ValueKey('mix_taxonomy_UNMAPPED')),
      findsNothing,
      reason: 'UNMAPPED is not a requestable chip',
    );
  });

  testWidgets(
    'the feed shows item + offering store together with the GHS price',
    (tester) async {
      final g = _FakeGateway()
        ..behavior = (cat, tax, cursor) async => (
          offers: [
            _offer(
              'a1',
              'BIZ-A',
              name: 'Jollof Rice',
              store: 'Adjoa\'s Kitchen',
            ),
            _offer(
              'b1',
              'BIZ-B',
              name: 'Jollof Rice',
              businessId: 'bp-2',
              store: 'Bra Kwame Chop Bar',
              price: const MixOfferPrice.fixedGhs('14.00'),
            ),
          ],
          nextCursor: null,
        );
      await _open(tester, gateway: g);

      // SERVER order, untouched: two stores' identical item names stay two rows.
      expect(find.text('Jollof Rice'), findsNWidgets(2));
      expect(find.text("Adjoa's Kitchen"), findsOneWidget);
      expect(find.text('Bra Kwame Chop Bar'), findsOneWidget);
      expect(find.text('GH₵\u00A012.50'), findsOneWidget);
      expect(find.text('GH₵\u00A014.00'), findsOneWidget);
    },
  );

  testWidgets('switching categories reloads the feed with a reset cursor', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async => (
        offers: [
          _offer(
            '$cat-1',
            'BIZ-$cat',
            name: cat == 'RETAIL' ? 'Kente Cloth' : 'Jollof Rice',
          ),
        ],
        nextCursor: cat == 'FOOD_BEVERAGE' ? 'CUR-1' : null,
      );
    await _open(tester, gateway: g);
    expect(g.calls.single.$3, isNull);
    expect(find.text('Jollof Rice'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mix_category_RETAIL')));
    await tester.pumpAndSettle();

    expect(g.calls, hasLength(2));
    expect(g.calls.last.$1, 'RETAIL');
    expect(g.calls.last.$2, isEmpty);
    expect(
      g.calls.last.$3,
      isNull,
      reason: 'the switch refetches page one of the new category',
    );
    expect(find.text('Kente Cloth'), findsOneWidget);
  });

  testWidgets('toggling a taxonomy chip refetches with the canonical filter', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async => (
        offers: [
          _offer(
            tax.isEmpty ? 'all-1' : 'meals-1',
            'BIZ-A',
            name: tax.isEmpty ? 'Everything' : 'Main dish',
          ),
        ],
        nextCursor: null,
      );
    await _open(tester, gateway: g);
    expect(find.text('Everything'), findsOneWidget);

    // Chips only exist once a category is selected (All has no rail).
    await tester.tap(find.byKey(const ValueKey('mix_category_FOOD_BEVERAGE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mix_taxonomy_MEALS')));
    await tester.pumpAndSettle();

    expect(g.calls.last.$1, 'FOOD_BEVERAGE');
    expect(g.calls.last.$2, ['MEALS']);
    expect(g.calls.last.$3, isNull);
    expect(find.text('Main dish'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mix_taxonomy_MEALS')));
    await tester.pumpAndSettle();
    expect(g.calls.last.$2, isEmpty);
  });

  testWidgets('paging appends the next cursor page without reshuffling', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async {
        if (cursor == null) {
          return (
            offers: List.generate(
              24,
              (i) => _offer('p$i', 'BIZ-A', name: 'Item $i'),
            ),
            nextCursor: 'CUR-2',
          );
        }
        return (
          offers: [_offer('p24', 'BIZ-A', name: 'Item 24')],
          nextCursor: null,
        );
      };
    await _open(tester, gateway: g);
    expect(find.text('Item 0'), findsOneWidget);
    expect(g.calls.single.$3, isNull);

    // Drag far enough to pass the near-end trigger.
    await tester.dragUntilVisible(
      find.text('Item 23'),
      find.byKey(const ValueKey('mix_feed')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(
      g.calls.last.$3,
      'CUR-2',
      reason: 'the next page request carries the server cursor',
    );
    // Lazy ListView: Item 24 sits just past the old end — scroll to it.
    await tester.dragUntilVisible(
      find.text('Item 24'),
      find.byKey(const ValueKey('mix_feed')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item 24'), findsOneWidget);
    // The append-not-replace invariant (old content survives page two) is
    // pinned at the provider level; here the wire cursor + new row are the
    // observable contract.
  });

  testWidgets('loading shows skeletons, not spinners or empty content', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) => Completer<MixDiscoveryPage>().future;
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway: g));
    await tester.pump();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    // First pump installs the pushed route; the second shows the loading feed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('mix_loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_feed')), findsNothing);
    expect(find.byKey(const ValueKey('mix_empty')), findsNothing);
  });

  testWidgets('failure shows an error surface with a working retry', (
    tester,
  ) async {
    var fail = true;
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async {
        if (fail) throw const MixRetryableException('network down');
        return (offers: [_offer('a1', 'BIZ-A')], nextCursor: null);
      };
    await _open(tester, gateway: g);
    expect(find.byKey(const ValueKey('mix_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_empty')), findsNothing);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix_error')), findsNothing);
    expect(find.text('Jollof Rice'), findsOneWidget);
  });

  testWidgets('a legitimate empty feed shows the empty state, not an error', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          (offers: <MixOffer>[], nextCursor: null);
    await _open(tester, gateway: g);

    expect(find.byKey(const ValueKey('mix_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_error')), findsNothing);
    expect(find.byKey(const ValueKey('mix_disabled')), findsNothing);
  });

  testWidgets('a filtered empty feed points at the chips, not the category', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          (offers: <MixOffer>[], nextCursor: null);
    await _open(tester, gateway: g);
    await tester.tap(find.byKey(const ValueKey('mix_category_FOOD_BEVERAGE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mix_taxonomy_MEALS')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mix_empty')), findsOneWidget);
    expect(find.textContaining('filters'), findsOneWidget);
  });

  testWidgets('404 (flag off) shows the DISABLED state — distinct from empty', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          throw const MixEndpointDisabledException();
    await _open(tester, gateway: g);

    expect(find.byKey(const ValueKey('mix_disabled')), findsOneWidget);
    expect(find.text("Marketplace Mix isn't available yet"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mix_empty')),
      findsNothing,
      reason: 'an unavailable surface is never "no items"',
    );
    expect(
      find.byKey(const ValueKey('mix_error')),
      findsNothing,
      reason: 'a deliberate flag is not a transient failure',
    );
  });

  testWidgets('422 shows the invalid-request state with Clear filters', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          throw const MixInvalidFilterException('unknown taxonomy: BLOOP');
    await _open(tester, gateway: g);

    expect(find.byKey(const ValueKey('mix_invalid_request')), findsOneWidget);
    expect(find.textContaining('unknown taxonomy'), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_error')), findsNothing);

    // The clear-filters affordance refetches the unfiltered feed.
    g.behavior = (cat, tax, cursor) async =>
        (offers: <MixOffer>[], nextCursor: null);
    await tester.tap(find.byKey(const ValueKey('mix_clear_filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix_invalid_request')), findsNothing);
  });

  testWidgets('tapping an offer records the interaction and pushes the store', (
    tester,
  ) async {
    final rec = _RecordingTapRecorder();
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async => (
        offers: [_offer('a1', 'BIZ-9', businessId: 'bp-9')],
        nextCursor: null,
      );
    await _open(tester, gateway: g, recorder: rec);
    await tester.tap(find.byKey(const ValueKey('mix_category_FOOD_BEVERAGE')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jollof Rice'));
    await tester.pumpAndSettle();

    expect(rec.taps.single, (
      businessProfileId: 'bp-9',
      productId: 'a1',
      mixCategory: 'FOOD_BEVERAGE',
    ));
    expect(find.byKey(const ValueKey('store-detail')), findsOneWidget);
    expect(
      find.text('store BIZ-9'),
      findsOneWidget,
      reason: 'the OFFERING store route, identity preserved',
    );
  });

  testWidgets('the feed bottom inset clears the system bottom safe area', (
    tester,
  ) async {
    final g = _FakeGateway()
      ..behavior = (cat, tax, cursor) async =>
          (offers: [_offer('a1', 'BIZ-A')], nextCursor: null);
    await _open(tester, gateway: g);

    final feed = tester.widget<ListView>(
      find.byKey(const ValueKey('mix_feed')),
    );
    final bottomInset = MediaQuery.paddingOf(
      tester.element(find.byKey(const ValueKey('mix_feed'))),
    ).resolve(TextDirection.ltr).bottom;
    // The ListView's bottom padding must clear the system inset + the gap.
    expect(
      feed.padding!.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(bottomInset + AzSpace.xxl - 1),
    );
  });
}
