// =============================================================================
// MARKET STOREFRONT SHELL — widget tests (Marketplace Storefront task)
//
// Pins the interaction contract of the new customer-facing market surface:
//   1.  arrival composition (banner + logo + name + products visible),
//   2.  the sheet starts at the overview/arrival snap,
//   3.  dragging down reveals the information behind the sheet,
//   4.  dragging up locks the shopping snap,
//   5.  the discovery animation runs exactly once per screen,
//   6.  the compact market pill only appears at the collapse threshold,
//   7.  the market name stays visible in the compact pill,
//   8.  product content stays reachable after the hero collapses,
//   9.  reduced motion disables the discovery choreography,
//   10. no-banner markets render a coherent gradient hero,
//   11. missing info fields never produce empty information blocks,
//   12. the vertical content entry points (catalog shortcut / primary CTA)
//       still fire their delegates.
//
// Extents are measured behaviorally via the sheet's on-screen rect, so the
// tests survive any internal controller refactor.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/screens/marketplace/market_storefront_shell.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

const _screenHeight = 600.0;

BusinessProfile _business({
  String name = 'Makola Fresh Market',
  String category = 'RETAIL',
  String? description = 'Genuine Accra goods, straight from the source.',
  String? logoUrl = 'https://img.example/logo.png',
  String? coverImageUrl = 'https://img.example/cover.jpg',
  String? phoneNumber = '+233 20 000 0000',
  String? website = 'https://example.com',
  String? contactEmail = 'hello@example.com',
  String? address,
  int reviewCount = 24,
  double averageRating = 4.8,
}) {
  return BusinessProfile(
    id: 'biz-1',
    bizId: 'BIZ-TEST01',
    businessName: name,
    category: category,
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 42,
    completedEscrows: 40,
    userId: 1,
    totalVolume: 1200,
    averageRating: averageRating,
    reviewCount: reviewCount,
    username: 'makola',
    description: description,
    website: website,
    logoUrl: logoUrl,
    coverImageUrl: coverImageUrl,
    phoneNumber: phoneNumber,
    contactEmail: contactEmail,
    address: address ?? '12 Kojo Thompson Rd, Accra',
  );
}

BusinessLocation _location({Map<String, dynamic>? hours}) {
  return BusinessLocation(
    id: 'loc-1',
    businessProfileId: 'biz-1',
    label: 'Main Branch',
    address: '12 Kojo Thompson Rd, Accra',
    latitude: 5.56,
    longitude: -0.19,
    galleryUrls: const [],
    isPrimary: true,
    isActive: true,
    operatingHours: hours ??
        const {
          'mon': '08:00-18:00',
          'tue': '08:00-18:00',
          'wed': '08:00-18:00',
          'thu': '08:00-18:00',
          'fri': '08:00-18:00',
          'sat': '09:00-16:00',
          'sun': '09:00-14:00',
        },
  );
}

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  final media = MediaQueryData(
    disableAnimations: disableAnimations,
    padding: const EdgeInsets.only(top: 24),
  );
  return ProviderScope(
    child: MediaQuery(
      data: media,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: child,
      ),
    ),
  );
}

Future<double> _pumpShell(
  WidgetTester tester, {
  BusinessProfile? business,
  List<BusinessLocation> locations = const [],
  List<Widget> Function(BuildContext)? products,
  Map<String, dynamic>? extraShell,
}) async {
  final biz = business ?? _business();
  final shell = MarketStorefrontShell(
    business: biz,
    colors: ThemeProvider.getColors(AzamanTheme.light),
    bannerUrl: biz.coverImageUrl,
    locations: locations,
    showcaseSlides: const [],
    isFollowing: false,
    unpaidInvoices: 0,
    hasCatalog: true,
    catalogLabel: 'Products',
    productsBuilder: products ?? (context) => [const Text('Product surface')],
    onOpenCatalog: extraShell?['onOpenCatalog'] as VoidCallback?,
    onPrimaryCta: extraShell?['onPrimaryCta'] as VoidCallback?,
  );
  await tester.pumpWidget(_wrap(shell));
  return biz.coverImageUrl != null ? 0 : 0;
}

Rect _sheetRect(WidgetTester tester) {
  return tester.getRect(find.byKey(const Key('market-storefront-sheet')));
}

double _extentOf(WidgetTester tester) =>
    1.0 - (_sheetRect(tester).top / _screenHeight);

Future<void> _settleDiscovery(WidgetTester tester) async {
  // Advance explicitly through the choreography timeline:
  // entrance beat (180ms) → dip (220ms) → hold (220ms) → settle (350ms).
  // (pumpAndSettle alone stops while no frame is scheduled even though a
  // discovery timer is still pending, which would freeze the sheet mid-way.)
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 420));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('market loads with banner + logo + name + initial product content',
      (tester) async {
    await _pumpShell(tester,
        products: (context) => [const Text('Kente Cloth — 40 USDC')]);

    expect(find.byType(AzamanNetworkImage), findsWidgets);
    expect(find.text('Makola Fresh Market'), findsWidgets);
    // Products are visible in the arrival state — the user lands in a store,
    // not an information screen.
    expect(find.text('Kente Cloth — 40 USDC'), findsOneWidget);
    expect(find.byKey(const Key('market-storefront-handle')), findsOneWidget);
  });

  testWidgets('sheet begins at the arrival/overview snap', (tester) async {
    await _pumpShell(tester);
    // First frame: extent == overview snap (0.62), before any choreography.
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.overview, 0.01));
  });

  testWidgets('sheet can move to the information state and reveal the panel',
      (tester) async {
    await _pumpShell(tester, locations: [_location()]);
    await _settleDiscovery(tester);

    // Pull the sheet down from shopping — information appears behind it.
    await tester.drag(
      find.byType(ListView).last,
      const Offset(0, 260),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.info, 0.01));
    expect(find.text('About this market'), findsOneWidget);
    expect(find.text('Genuine Accra goods, straight from the source.'),
        findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
  });

  testWidgets('sheet snaps back cleanly into the shopping state', (tester) async {
    await _pumpShell(tester, locations: [_location()]);
    await _settleDiscovery(tester);

    // Down to info first...
    await tester.drag(find.byType(ListView).last, const Offset(0, 300),
        warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.info, 0.01));

    // ...then lift back into shopping.
    await tester.drag(find.byType(ListView).last, const Offset(0, -340),
        warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));
  });

  testWidgets('discovery animation runs exactly once for the screen',
      (tester) async {
    final biz = _business();
    var following = false;
    late StateSetter? ignore;
    Widget buildShell(bool isFollowing) => _wrap(MarketStorefrontShell(
          business: biz,
          colors: ThemeProvider.getColors(AzamanTheme.light),
          bannerUrl: biz.coverImageUrl,
          locations: const [],
          showcaseSlides: const [],
          isFollowing: isFollowing,
          unpaidInvoices: 0,
          hasCatalog: false,
          catalogLabel: 'Catalog',
          productsBuilder: (context) => [const Text('Product surface')],
        ));

    await tester.pumpWidget(buildShell(following));
    // Let the full dip-and-settle play out.
    await _settleDiscovery(tester);
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));

    // Rebuild the SAME screen state (e.g. follow state flipped after a tap) —
    // the discovery choreography must not replay.
    following = true;
    await tester.pumpWidget(buildShell(following));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));
  });

  testWidgets('compact market identity appears only after the collapse threshold',
      (tester) async {
    await _pumpShell(tester, locations: [_location()]);
    // First frame: overview state — the pill is present in the tree but
    // fully transparent and untouchable.
    final pill = find.descendant(
      of: find.byKey(const Key('market-compact-pill')),
      matching: find.byType(Text),
    );
    Opacity pillOpacity(WidgetTester t) => t.widget<Opacity>(
          find.ancestor(
            of: find.byKey(const Key('market-compact-pill')),
            matching: find.byType(Opacity),
          ).first,
        );

    expect(pillOpacity(tester).opacity, 0.0);
    expect(pill, findsOneWidget); // tree presence, not visibility

    await _settleDiscovery(tester);
    // Collapsed to shopping: the pill is fully opaque.
    expect(pillOpacity(tester).opacity, 1.0);
  });

  testWidgets('market name stays visible in the compact state', (tester) async {
    await _pumpShell(tester);
    await _settleDiscovery(tester);

    final nameInPill = find.descendant(
      of: find.byKey(const Key('market-compact-pill')),
      matching: find.text('Makola Fresh Market'),
    );
    expect(nameInPill, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: nameInPill,
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacity.opacity, 1.0);
  });

  testWidgets('long business name does not overflow in hero or pill',
      (tester) async {
    await _pumpShell(
      tester,
      business: _business(
          name:
              'Makola International Fresh Produce and Handwoven Textiles Enterprise'),
      locations: [_location()],
    );
    await _settleDiscovery(tester);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).last, const Offset(0, 260),
        warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('product content remains accessible after the hero collapses',
      (tester) async {
    await _pumpShell(
      tester,
      products: (context) => [
        for (var i = 1; i <= 20; i++) Text('Product item $i'),
      ],
    );
    await _settleDiscovery(tester);
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));

    // The sheet's product list still scrolls while locked at shopping.
    await tester.scrollUntilVisible(
      find.text('Product item 20'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Product item 20'), findsOneWidget);
  });

  testWidgets('reduced motion disables the discovery choreography',
      (tester) async {
    // The app's own reduced-motion seam (TASK-026): AzMotion consults the
    // AzSensory override before the OS flag.
    AzSensory.apply(const SensoryPreferences(forceReduceMotion: true));
    addTearDown(() => AzSensory.apply(const SensoryPreferences()));
    final biz = _business();
    await tester.pumpWidget(_wrap(
      MarketStorefrontShell(
        business: biz,
        colors: ThemeProvider.getColors(AzamanTheme.light),
        bannerUrl: biz.coverImageUrl,
        locations: const [],
        showcaseSlides: const [],
        isFollowing: false,
        unpaidInvoices: 0,
        hasCatalog: true,
        catalogLabel: 'Products',
        productsBuilder: (context) => [const Text('Product surface')],
      ),
      disableAnimations: true,
    ));

    // No dip: the sheet goes straight to the shopping snap and stays there.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));
  });

  testWidgets('businesses with no banner still render a coherent hero',
      (tester) async {
    await _pumpShell(
      tester,
      business: _business(coverImageUrl: null, logoUrl: null),
    );
    await _settleDiscovery(tester);

    // No network image in the hero at all — the accent gradient fallback
    // carries the identity instead of a broken layout.
    expect(find.byType(AzamanNetworkImage), findsNothing);
    expect(find.text('Makola Fresh Market'), findsWidgets);
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.shopping, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing description/contact/website creates no empty info blocks',
      (tester) async {
    await _pumpShell(
      tester,
      business: _business(
        description: '  ', // whitespace only — counts as absent
        phoneNumber: null,
        website: null,
        contactEmail: null,
        address: null,
        reviewCount: 0,
      ),
      locations: const [], // no locations → no hours either
    );
    await _settleDiscovery(tester);

    // Pull down to the info snap: with no info at all, no section shells.
    await tester.drag(find.byType(ListView).last, const Offset(0, 300),
        warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(_extentOf(tester), closeTo(MarketStorefrontSnaps.info, 0.01));

    expect(find.text('About this market'), findsNothing);
    expect(find.text('Hours'), findsNothing);
    expect(find.text('Location'), findsNothing);
    expect(find.text('Contact'), findsNothing);
    expect(tester.takeException(), isNull);

    // And the partially-filled variant: description renders, but the
    // contact section with no data does not.
    await _pumpShell(
      tester,
      business: _business(
          phoneNumber: null, website: null, contactEmail: null, address: null),
      locations: const [],
    );
    await _settleDiscovery(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, 300),
        warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('About this market'), findsOneWidget);
    expect(find.text('Contact'), findsNothing);
  });

  testWidgets('vertical content entry points still fire their delegates',
      (tester) async {
    var catalogOpened = false;
    var ctaFired = false;
    final biz = _business();
    await tester.pumpWidget(_wrap(MarketStorefrontShell(
      business: biz,
      colors: ThemeProvider.getColors(AzamanTheme.light),
      bannerUrl: biz.coverImageUrl,
      locations: const [],
      showcaseSlides: const [],
      isFollowing: false,
      unpaidInvoices: 0,
      hasCatalog: true,
      catalogLabel: 'Menu',
      productsBuilder: (context) => [const Text('Product surface')],
      onOpenCatalog: () => catalogOpened = true,
      onPrimaryCta: () => ctaFired = true,
    )));
    await _settleDiscovery(tester);

    // The vertical's full catalog experience (flip-book / catalog storefront)
    // remains reachable from the sheet action row.
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(catalogOpened, isTrue);

    // The primary market CTA still routes to the vertical flow.
    await tester.tap(find.byKey(const Key('market-primary-cta')));
    await tester.pump();
    expect(ctaFired, isTrue);
  });
}
