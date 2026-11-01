// =============================================================================
// MIX CUSTOMER JOURNEY — visual evidence suite (PR #156, 2026-10-19).
//
// Reviewable screenshots on the actual PR tree for the FULL journey the
// acceptance review must see, at the three reference widths (320/360/390dp)
// in BOTH themes:
//
//   • mix_entry_*      — MarketplaceHomeScreen with Mix toggled IN PLACE,
//                        inside the shell's extendBody chrome with a
//                        48dp band (PremiumBottomNav at-rest height), so
//                        the above-the-nav clearance is visible AND
//                        asserted geometrically: no covered controls.
//   • mix_searching_*  — the multi-request walk with the truthful
//                        "Still searching" feedback line (never a silent
//                        skeleton).
//   • mix_stalled_*    — the explicit stalled panel (Try again / Refresh
//                        feed), never a looping Show more.
//   • mix_more_*       — empty page WITH a cursor: the Show more
//                        continuation affordance, and the items it
//                        surfaces — never mistaken for exhaustion.
//   • storefront_*     — the storefront catalogue listing (authoritative
//                        GHS price / Price unavailable).
//   • order_sheet_*    — the direct-order confirmation: explicit
//                        "X USDC" payable labels + separate "Listed: GH₵".
//   • cart_*           — the cart/checkout confirmation after Add.
//
// Captures land in .screenshots/ (untracked, ephemeral).
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart' show CartScreen;
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/screens/storefront_screen.dart';
import 'package:azaman/screens/storefront_order_sheet.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_feed_surface.dart';

const _rootKey = Key('shot-root');

const _bandHeight = 48.0; // PremiumBottomNav.expandedHeight (at-rest pill)

const _configs = [(320.0, 569.0), (360.0, 740.0), (390.0, 844.0)];

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular = await File(
    'assets/fonts/ComicNeue-Regular.ttf',
  ).readAsBytes();
  final bold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  final comicLoader = FontLoader('ComicNeue')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(regular).buffer)),
    )
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bold).buffer)),
    );
  await comicLoader.load();
  _fontsLoaded = true;
}

Future<ThemeProvider> _seedTheme(AzamanTheme theme) async {
  SharedPreferences.setMockInitialValues({
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  final p = ThemeProvider();
  int guard = 0;
  while (!p.isLoaded && guard++ < 100) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isLoaded, isTrue);
  return p;
}

/// toImage/file IO need REAL async — capture inside `tester.runAsync`.
Future<void> _capture(WidgetTester tester, String name) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_rootKey),
    );
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    Directory('.screenshots').createSync(recursive: true);
    File('.screenshots/$name.png').writeAsBytesSync(data.buffer.asUint8List());
    ok = true;
  });
  expect(ok, isTrue, reason: 'capture $name wrote a PNG');
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// ── Mix gateway fake (same seam the contract suites use) ─────────────────────

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway(this.behavior);

  final Future<MixDiscoveryPage> Function(String? cursor, int call) behavior;
  int calls = 0;

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
    calls += 1;
    await Future<void>.delayed(Duration.zero);
    return behavior(cursor, calls);
  }
}

MixDiscoveryPage _page(List<MixOffer> offers, String? next) =>
    (offers: offers, nextCursor: next);

/// The review feed: two exact GHS prices, one unpriced offer, two stores.
List<MixOffer> _reviewOffers() => [
  MixOffer(
    productId: 'p-1',
    businessId: 'bp-1',
    bizId: 'BIZ-1',
    businessName: "Auntie Adjoa's Kitchen",
    businessCategory: 'FOOD_BEVERAGE',
    name: 'Jollof Rice',
    price: const MixOfferPrice.fixedGhs('25.00'),
    isAvailable: true,
  ),
  MixOffer(
    productId: 'p-2',
    businessId: 'bp-2',
    bizId: 'BIZ-2',
    businessName: 'Osu Kenkey Bar',
    businessCategory: 'FOOD_BEVERAGE',
    name: 'Banku & Tilapia',
    price: const MixOfferPrice.fixedGhs('48.50'),
    isAvailable: true,
  ),
  MixOffer(
    productId: 'p-3',
    businessId: 'bp-3',
    bizId: 'BIZ-3',
    businessName: 'Makola Fabrics',
    businessCategory: 'RETAIL_GOODS',
    name: 'Kente Cloth (2 yards)',
    price: const MixOfferPrice.unknown(),
    isAvailable: false,
  ),
];

// ── Home harness (MarketplaceHomeScreen, from the in-place contract suite) ──

/// The home screen's following/ads rails fire real API loads on build;
/// their futures complete after the harness tears the tree down, which
/// poisons the test with a post-dispose StateError. Both rails are inert
/// in these captures (they are not under review here).
class _NoopFollowingNotifier extends FollowingListNotifier {
  _NoopFollowingNotifier(super.api);
  @override
  Future<void> load() async {}
}

class _NoopAdFeedNotifier extends AdFeedNotifier {
  _NoopAdFeedNotifier(super.api);
  @override
  Future<void> load() async {}
}

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

Widget _bandedHome(ThemeProvider themeProv) => Scaffold(
  // The shell contract: extendBody + a 48dp persistent band, so the
  // tab content's MediaQuery carries the REAL band clearance the feed
  // pads against (nav_band_clearance.dart).
  extendBody: true,
  bottomNavigationBar: Container(
    height: _bandHeight,
    decoration: BoxDecoration(
      color: themeProv.colors.surface,
      border: Border(top: BorderSide(color: themeProv.colors.divider)),
    ),
    alignment: Alignment.center,
    child: Text(
      '◂  Home   +   Market   ▸   (48dp nav band)',
      style: TextStyle(color: themeProv.colors.textTertiary, fontSize: 11),
    ),
  ),
  body: const MarketplaceHomeScreen(),
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required AzamanTheme theme,
  required _FakeGateway gateway,
}) async {
  final themeProv = (await tester.runAsync(() => _seedTheme(theme)))!;
  await tester.runAsync(_loadFonts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith(
          (ref) => _RecordingSearchNotifier(),
        ),
        followingListProvider.overrideWith(
          (ref) => _NoopFollowingNotifier(ref.watch(apiClientProvider)),
        ),
        adFeedProvider.overrideWith(
          (ref) => _NoopAdFeedNotifier(ref.watch(apiClientProvider)),
        ),
        marketplaceMixGatewayProvider.overrideWithValue(gateway),
        themeProvider.overrideWith((ref) => themeProv),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        home: RepaintBoundary(key: _rootKey, child: _bandedHome(themeProv)),
      ),
    ),
  );
}

Future<void> _boundedPump(WidgetTester tester, [int frames = 60]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// ── Feed-surface harness (states) ────────────────────────────────────────────

Future<void> _pumpSurface(
  WidgetTester tester, {
  required AzamanTheme theme,
  required _FakeGateway gateway,
  double bottomPadding = _bandHeight + 16,
}) async {
  final themeProv = (await tester.runAsync(() => _seedTheme(theme)))!;
  await tester.runAsync(_loadFonts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceMixGatewayProvider.overrideWithValue(gateway),
        themeProvider.overrideWith((ref) => themeProv),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: Container(
            height: _bandHeight,
            decoration: BoxDecoration(
              color: themeProv.colors.surface,
              border: Border(top: BorderSide(color: themeProv.colors.divider)),
            ),
          ),
          body: RepaintBoundary(
            key: _rootKey,
            child: MixFeedSurface(
              onOpenStore: (_) {},
              bottomPadding: bottomPadding,
            ),
          ),
        ),
      ),
    ),
  );
  final ctx = tester.element(find.byType(MixFeedSurface));
  ProviderScope.containerOf(ctx).read(marketplaceMixProvider.notifier).load();
  await _boundedPump(tester);
}

// ── Storefront journey harness (catalogue → Add → cart) ──────────────────────

class _FakeStorefrontService extends StorefrontService {
  _FakeStorefrontService(this.productsPayload);
  final Map<String, dynamic> productsPayload;

  @override
  Future<StorefrontRenderResponse?> renderStorefront(
    String businessProfileId,
  ) async {
    return StorefrontRenderResponse.fromJson(<String, dynamic>{
      'business': {'name': 'Test Shop', 'category': 'RETAIL'},
      'theme': <String, dynamic>{},
      'layout': <String, dynamic>{'tiles': <dynamic>[]},
    });
  }

  @override
  Future<Map<String, dynamic>> getStorefrontProducts(
    String businessProfileId,
  ) async {
    return productsPayload;
  }
}

Map<String, dynamic> _pricedProduct() => {
  'id': 'p1',
  'name': 'Jollof Plate',
  'description': 'Fresh and hot',
  'priceUsdc': 4.2,
  'priceGhs': '25.50',
  'imageUrls': <String>[],
  'tags': <String>[],
  'preparationMins': 15,
};

Map<String, dynamic> _unpricedProduct() => {
  ..._pricedProduct(),
  'id': 'p2',
  'name': 'Fried Yam',
  'priceGhs': null,
};

Map<String, dynamic> _productsPayload() => {
  'business': {'id': 'bp-1', 'name': 'Test Shop', 'category': 'RETAIL'},
  'hasStorefront': true,
  'products': [_pricedProduct(), _unpricedProduct()],
};

// ── The suite ─────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (width, height) in _configs) {
    for (final theme in AzamanTheme.values) {
      final mode = theme == AzamanTheme.dark ? 'dark' : 'light';
      final w = width.toInt();

      group('${w}dp $mode', () {
        setUpAll(() async {});

        testWidgets('mix entry — in-place Mix with band clearance', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final gateway = _FakeGateway(
            (cursor, call) async => _page(_reviewOffers(), null),
          );
          await _pumpHome(tester, theme: theme, gateway: gateway);

          // Toggle Mix ON in place.
          await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
          await _boundedPump(tester);

          expect(
            find.byKey(const ValueKey('mix_inplace_feed')),
            findsOneWidget,
          );
          expect(find.text('Jollof Rice'), findsOneWidget);
          expect(
            find.text('GH₵\u00A025.00'),
            findsOneWidget,
            reason:
                'authoritative GHS listing price renders exactly (NBSP, per card contract)',
          );
          expect(
            find.text('Price unavailable'),
            findsOneWidget,
            reason: 'the unpriced offer is honest, never a from-amount',
          );

          // Clearance: under extendBody the feed VIEWPORT legitimately
          // spans the full height (content scrolls under the band edge);
          // the contract is that the feed's CONTENT clears the band — so
          // scroll to the very end and require the LAST interactive card
          // to sit fully above the band (no covered controls).
          final screenBottom = height;
          final feedScrollable = find
              .descendant(
                of: find.byKey(const ValueKey('mix_inplace_feed')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.dragUntilVisible(
            find.text('Kente Cloth (2 yards)'),
            feedScrollable,
            const Offset(0, -100),
            maxIteration: 60,
          );
          // Reach the true end of the feed before measuring.
          final scrollPosition = tester
              .state<ScrollableState>(feedScrollable)
              .position;
          while (scrollPosition.extentAfter > 0) {
            await tester.drag(feedScrollable, const Offset(0, -200));
            await _boundedPump(tester, 5);
          }
          await _boundedPump(tester);
          final lastCard = tester.getRect(find.text('Kente Cloth (2 yards)'));
          expect(
            lastCard.bottom,
            lessThanOrEqualTo(screenBottom - _bandHeight),
            reason: 'the last card is fully reachable above the band',
          );

          await _capture(tester, 'mix_entry_${w}_$mode');
        });

        testWidgets('mix searching — truthful multi-request feedback', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final secondPage = Completer<MixDiscoveryPage>();
          var calls = 0;
          final gateway = _FakeGateway((cursor, call) async {
            calls += 1;
            if (calls == 1) return _page([], 'CUR-1');
            return secondPage.future;
          });
          await _pumpSurface(tester, theme: theme, gateway: gateway);

          expect(calls, 2);
          expect(
            find.byKey(const ValueKey('mix_searching_wide')),
            findsOneWidget,
            reason: 'the walk is visibly in progress, never silent',
          );
          await _capture(tester, 'mix_searching_${w}_$mode');

          // Let the walk resolve honestly for teardown.
          secondPage.complete(_page(_reviewOffers(), null));
          await _boundedPump(tester);
        });

        testWidgets('mix stalled — explicit panel, no looping Show more', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final gateway = _FakeGateway(
            (cursor, call) async => _page([], 'CUR-REPEAT'),
          );
          await _pumpSurface(tester, theme: theme, gateway: gateway);

          expect(
            find.byKey(const ValueKey('mix_stalled_notice')),
            findsOneWidget,
          );
          expect(
            find.text('Show more'),
            findsNothing,
            reason: 'a repeated cursor never masquerades as a next page',
          );
          await _capture(tester, 'mix_stalled_${w}_$mode');
        });

        testWidgets('mix empty + cursor — continuation, not exhaustion', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          var calls = 0;
          final gateway = _FakeGateway((cursor, call) async {
            calls += 1;
            if (calls == 1) return _page([], 'CUR-1');
            if (calls <=
                1 + MarketplaceMixNotifier.kMaxFirstPageContinuations) {
              return _page([], 'CUR-$calls');
            }
            return _page([
              MixOffer(
                productId: 'p-x',
                businessId: 'bp-x',
                bizId: 'BIZ-x',
                businessName: 'Hidden Gem',
                businessCategory: 'FOOD_BEVERAGE',
                name: 'Kelewele Platter',
                price: const MixOfferPrice.fixedGhs('15.00'),
                isAvailable: true,
              ),
            ], null);
          });
          await _pumpSurface(tester, theme: theme, gateway: gateway);

          // The continuation affordance is present — the empty page with a
          // cursor is NOT rendered as exhausted inventory.
          expect(
            find.byKey(const ValueKey('mix_empty_continue')),
            findsOneWidget,
          );
          await _capture(tester, 'mix_more_state_${w}_$mode');

          // Tapping it surfaces the items waiting beyond the scan window.
          await tester.tap(find.byKey(const ValueKey('mix_empty_continue')));
          await _boundedPump(tester);
          expect(find.text('Kelewele Platter'), findsOneWidget);
          await _capture(tester, 'mix_more_results_${w}_$mode');
        });

        testWidgets('storefront catalogue — GHS listing + order sheet', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final themeProv = (await tester.runAsync(() => _seedTheme(theme)))!;
          await tester.runAsync(_loadFonts);
          final fake = _FakeStorefrontService(_productsPayload());
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                storefrontServiceProvider.overrideWithValue(fake),
                themeProvider.overrideWith((ref) => themeProv),
              ],
              child: MaterialApp(
                theme: ThemeProvider.getThemeData(theme),
                home: RepaintBoundary(
                  key: _rootKey,
                  child: const StorefrontScreen(
                    businessProfileId: 'bp-1',
                    businessName: 'Test Shop',
                  ),
                ),
              ),
            ),
          );
          await _boundedPump(tester, 40);

          for (var i = 0; i < 10; i++) {
            if (tester.any(find.text('Jollof Plate'))) break;
            await tester.drag(
              find.byType(CustomScrollView).first,
              const Offset(0, -300),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text('GH₵25.50'), findsOneWidget);
          expect(find.text('Price unavailable'), findsOneWidget);
          await _capture(tester, 'storefront_${w}_$mode');

          // Journey truth: tapping Add routes to the CART (the order
          // sheet is a separate direct-order surface), and the cart bar
          // carries the EXPLICIT USDC payable subtotal — never a bare '$'.
          await tester.tap(find.text('Add').first);
          await _boundedPump(tester, 20);
          expect(
            find.text('4.20 USDC'),
            findsOneWidget,
            reason: 'cart bar payable subtotal is explicitly USDC',
          );
          expect(
            find.textContaining(r'$'),
            findsNothing,
            reason: r'no bare-$ payable amounts anywhere',
          );
          await _capture(tester, 'cart_bar_${w}_$mode');
        });

        testWidgets('order sheet — explicit USDC payable, GHS listed fact', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final themeProv = (await tester.runAsync(() => _seedTheme(theme)))!;
          await tester.runAsync(_loadFonts);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [themeProvider.overrideWith((ref) => themeProv)],
              child: MaterialApp(
                theme: ThemeProvider.getThemeData(theme),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: _rootKey,
                    child: StorefrontOrderSheet(
                      businessProfileId: 'bp-1',
                      businessName: 'Test Shop',
                      product: _pricedProduct(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _boundedPump(tester, 20);
          expect(
            find.textContaining('USDC'),
            findsWidgets,
            reason: 'every payable amount is explicitly USDC',
          );
          expect(find.text('Place Order · 4.20 USDC'), findsOneWidget);
          expect(find.text('Listed: GH₵25.50'), findsOneWidget);
          await _capture(tester, 'order_sheet_${w}_$mode');
        });

        testWidgets('cart — explicit USDC checkout confirmation', (
          tester,
        ) async {
          await _setSurface(tester, Size(width, height));
          final themeProv = (await tester.runAsync(() => _seedTheme(theme)))!;
          final showCart = ValueNotifier<bool>(false);
          addTearDown(showCart.dispose);
          final fake = _FakeStorefrontService(_productsPayload());
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                storefrontServiceProvider.overrideWithValue(fake),
                themeProvider.overrideWith((ref) => themeProv),
              ],
              child: ValueListenableBuilder<bool>(
                valueListenable: showCart,
                builder: (context, cart, _) => MaterialApp(
                  theme: ThemeProvider.getThemeData(theme),
                  home: RepaintBoundary(
                    key: _rootKey,
                    child: cart
                        ? const CartScreen()
                        : const StorefrontScreen(
                            businessProfileId: 'bp-1',
                            businessName: 'Test Shop',
                          ),
                  ),
                ),
              ),
            ),
          );
          await _boundedPump(tester, 40);

          // Reach the Add button and fill the cart (the real journey).
          for (var i = 0; i < 10; i++) {
            if (tester.any(find.text('GH₵25.50'))) break;
            await tester.drag(
              find.byType(CustomScrollView).first,
              const Offset(0, -300),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; i < 6; i++) {
            final rects = tester.widgetList<Text>(find.text('Add'));
            if (rects.isNotEmpty) {
              final rect = tester.getRect(find.text('Add').first);
              if (rect.bottom < height && rect.top > 0) break;
            }
            await tester.drag(
              find.byType(CustomScrollView).first,
              const Offset(0, -200),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.text('Add').first);
          await tester.pump(const Duration(milliseconds: 100));

          showCart.value = true;
          await _boundedPump(tester, 40);

          expect(
            find.textContaining('USDC'),
            findsWidgets,
            reason: 'cart labels every payable amount USDC explicitly',
          );
          expect(
            find.textContaining('\$'),
            findsNothing,
            reason: 'no bare dollar figure anywhere in checkout',
          );
          await _capture(tester, 'cart_${w}_$mode');
        });
      });
    }
  }
}
