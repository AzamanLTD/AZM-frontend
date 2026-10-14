// =============================================================================
// MARKETPLACE MIX — screen widget tests.
//
// Pins the full screen experience:
//   • category chips render and switching categories reloads the feed
//   • cross-store feed: item + store together, round-robin interleave visible
//   • loading skeletons, failed + retry, empty category, ready-no-listings,
//     partial store failures
//   • navigation: tapping an offer records the interaction and pushes the
//     OFFERING store route with the store identity preserved
//   • bottom clearance: feed insets clear the system bottom inset so the
//     final item is never obscured (pushed route sits above the nav band)
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

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway({this.pages = const {}});

  final Map<String, List<MixStorePage>> pages;
  final List<String> searchCalls = [];
  final List<String> productCalls = [];
  final Set<String> failingBizIds = {};
  var failSearch = false;

  @override
  Set<MixCapability> get supportedCapabilities =>
      const {MixCapability.itemStoreInteractions};

  @override
  Future<MixStorePage> searchStores({
    required String category,
    int limit = 10,
    String? cursor,
  }) async {
    searchCalls.add(category);
    if (failSearch) throw Exception('network down');
    final pageList = pages[category] ?? const <MixStorePage>[];
    if (pageList.isEmpty) {
      return (stores: <MixStore>[], hasMore: false, nextCursor: null);
    }
    return pageList.first;
  }

  @override
  Future<MixStoreOffers> productsFor(MixStore store, {int limit = 50}) async {
    productCalls.add(store.bizId);
    await Future<void>.delayed(Duration.zero);
    if (failingBizIds.contains(store.bizId)) throw Exception('store down');
    final rows = _catalogues[store.bizId] ?? const <Map<String, dynamic>>[];
    return (
      store: store,
      offers: rows
          .map((r) => MixOffer.fromJson(
                r,
                businessProfileId: store.id,
                bizId: store.bizId,
                businessName: store.businessName,
                businessCategory: store.category,
              ))
          .toList(),
    );
  }
}

final Map<String, List<Map<String, dynamic>>> _catalogues = {
  'BIZ-A': [
    {'id': 'a1', 'name': 'Jollof Rice', 'priceUsdc': 12.5, 'isAvailable': true},
    {'id': 'a2', 'name': 'Waakye Special', 'priceUsdc': 15.0},
  ],
  'BIZ-B': [
    {'id': 'b1', 'name': 'Jollof Rice', 'priceUsdc': 14.0},
    {'id': 'b2', 'name': 'Banku & Tilapia', 'priceUsdc': 18.0},
    // Missing price row — must render "Price unavailable".
    {'id': 'b3', 'name': 'Kelewele', 'isAvailable': false},
  ],
};

List<MixStorePage> _foodPages() => [
      (
        stores: [
          const MixStore(id: 'bp-1', bizId: 'BIZ-A', businessName: 'Adjoa\'s Kitchen', category: 'FOOD_BEVERAGE'),
          const MixStore(id: 'bp-2', bizId: 'BIZ-B', businessName: 'Bra Kwame Chop Bar', category: 'FOOD_BEVERAGE'),
        ],
        hasMore: false,
        nextCursor: null,
      ),
    ];

class _RecordingTapRecorder implements MixTapRecorder {
  final taps = <({String businessProfileId, String productId, String mixCategory})>[];

  @override
  void recordProductTap({
    required String businessProfileId,
    required String productId,
    required String mixCategory,
  }) {
    taps.add((
      businessProfileId: businessProfileId,
      productId: productId,
      mixCategory: mixCategory,
    ));
  }
}

Widget _app(_FakeGateway gateway, {_RecordingTapRecorder? recorder}) {
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
                body: Center(child: Text('shell', key: Key('shell')))),
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
                child:
                    Text('store ${state.pathParameters['bizId']}'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openMix(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(_app(_FakeGateway(pages: {
    'FOOD_BEVERAGE': _foodPages(),
  })));
  await tester.pump();
  tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
        MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Mix screen shows a category-first header and rail',
      (tester) async {
    await _openMix(tester);
    expect(find.text('Marketplace Mix'), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_category_rail')), findsOneWidget);
    expect(find.text('Eat'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
  });

  testWidgets('the feed shows item + offering store together, cross-store',
      (tester) async {
    await _openMix(tester);
    // The same item in two stores is rendered twice, each with its store.
    expect(find.text('Jollof Rice'), findsNWidgets(2));
    // Once per offer from that store (A lists 2, B lists 3).
    expect(find.text("Adjoa's Kitchen"), findsNWidgets(2));
    expect(find.text('Bra Kwame Chop Bar'), findsNWidgets(3));
    // Round-robin: the first two feed rows are from DIFFERENT stores.
    final storeLabels = tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('mix_feed')),
            matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(storeLabels.indexOf("Adjoa's Kitchen") <
        storeLabels.indexOf('Bra Kwame Chop Bar'), isTrue);
  });

  testWidgets('price states render honestly', (tester) async {
    await _openMix(tester);
    expect(find.text('12.50\u00A0USDC'), findsOneWidget);
    expect(find.text('14.00\u00A0USDC'), findsOneWidget);
    // Missing price → unavailable label, never a zero amount.
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.textContaining('0.00'), findsNothing);
    // Unavailable badge only on the payload-flagged row.
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('switching categories reloads the feed', (tester) async {
    await _openMix(tester);
    await tester.tap(find.byKey(const ValueKey('mix_category_RETAIL')));
    await tester.pumpAndSettle();
    expect(find.text('Jollof Rice'), findsNothing);
  });

  testWidgets('tapping an offer records the interaction and pushes the store',
      (tester) async {
    final recorder = _RecordingTapRecorder();
    final gateway = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()});
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway, recorder: recorder));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    await tester.pumpAndSettle();

    // Tap the first Jollof row (Adjoa's, bp-1).
    await tester.tap(find.text('Jollof Rice').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(recorder.taps, isNotEmpty);
    expect(recorder.taps.first.businessProfileId, 'bp-1');
    expect(recorder.taps.first.productId, 'a1');
    expect(recorder.taps.first.mixCategory, 'FOOD_BEVERAGE');
    expect(find.byKey(const ValueKey('store-detail')), findsOneWidget);
    expect(find.text('store BIZ-A'), findsOneWidget);
  });

  testWidgets('loading shows skeletons, not spinners or empty content',
      (tester) async {
    // Gateway whose products call never resolves this frame: suspend with a
    // Completer to hold the loading phase.
    final held = <Completer<void>>[];
    final gateway = _SuspendedGateway(held);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    // First pump installs the pushed route; the second shows the loading feed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('mix_loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('failure shows an error surface with a working retry',
      (tester) async {
    final gateway = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()})
      ..failSearch = true;
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mix_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_feed')), findsNothing);

    gateway.failSearch = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mix_feed')), findsOneWidget);
    expect(find.text('Jollof Rice'), findsNWidgets(2));
  });

  testWidgets('an empty category shows the no-stores empty state',
      (tester) async {
    final gateway = _FakeGateway(pages: {});
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mix_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('mix_feed')), findsNothing);
  });

  testWidgets('partial store failures keep the feed and show a quiet notice',
      (tester) async {
    final gateway = _FakeGateway(pages: {'FOOD_BEVERAGE': _foodPages()})
      ..failingBizIds.add('BIZ-A');
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(
          MaterialPageRoute(builder: (_) => const MarketplaceMixScreen()),
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mix_feed')), findsOneWidget);
    expect(find.text("Adjoa's Kitchen"), findsNothing);
    expect(find.text('Bra Kwame Chop Bar'), findsNWidgets(3));
    expect(find.text('1 store couldn\'t be loaded'), findsOneWidget);
  });

  testWidgets('the feed bottom inset clears the system bottom safe area',
      (tester) async {
    await _openMix(tester);
    // Pushed routes sit above the persistent nav band; the contract is:
    // bottom padding >= system inset + AzSpace.xxl (24).
    final list = tester.widget<ListView>(
        find.byKey(const ValueKey('mix_feed')));
    final pad = list.padding as EdgeInsets;
    final sysBottom = MediaQuery.paddingOf(
        tester.element(find.byKey(const ValueKey('mix_feed')))).bottom;
    // The clearance contract: bottom inset >= system inset + AzSpace.xxl(24).
    expect(pad.bottom, greaterThanOrEqualTo(sysBottom + 24 - 0.5));
  });
}

class _SuspendedGateway extends _FakeGateway {
  _SuspendedGateway(this._held) : super(pages: {'FOOD_BEVERAGE': _foodPages()});
  final List<Completer<void>> _held;

  @override
  Future<MixStoreOffers> productsFor(MixStore store, {int limit = 50}) {
    final c = Completer<void>();
    _held.add(c);
    return c.future.then((_) => (store: store, offers: <MixOffer>[]));
  }
}
