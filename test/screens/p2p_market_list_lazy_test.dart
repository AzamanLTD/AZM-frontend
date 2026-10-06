// FINAL PASS §8 — P2P MARKETPLACE: LAZY AD LIST PIN
//
// The brief: "P2P marketplace: The P2P entry must resolve to the canonical
// Buy & Sell USDC experience (no duplicate P2P pages). Do not duplicate
// profile-fetch work during navigation/refresh. Any lazily-mounted ad
// widgets must be in a lazy sliver-based structure, not eagerly-built
// Columns."
//
// The pre-fix screen rendered the ad list as ONE SliverToBoxAdapter whose
// Column built EVERY VendorAdCard eagerly — 50 ads = 50 card builds on the
// first frame, offscreen included. This pin requires the list to be a lazy
// sliver (SliverList + SliverChildBuilderDelegate) so only viewport-visible
// ads materialize.

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/p2p/p2p_market_list_screen.dart';
import 'package:azaman/widgets/vendor_ad_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

// Real font, not Ahem: Ahem renders every glyph exactly `fontSize` wide,
// which fabricates ~2x-wide text and bogus RenderFlex overflows on
// otherwise-fine rows. The home widget tests load Inter the same way.
bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  Future<void> load(String family, String asset) async {
    final bytes = await File(asset).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(
          ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter-Variable.ttf');
  // The app theme types the whole app in ComicNeue — without it the test
  // falls back to Ahem and fabricates bogus RenderFlex overflows.
  await load('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  _fontsLoaded = true;
}

AdListing _ad(int i) => AdListing(
      id: 'ad-$i',
      vendorUsername: 'vendor$i',
      vendorId: 'v$i',
      adType: 'SELL', // Buy tab keeps SELL ads
      pricePerUSD: 15 + (i % 5) * 0.1,
      minLimit: 10,
      maxLimit: 500,
      availableUsdc: 1000,
      paymentMethod: 'ZELLE',
      queueFull: false,
      queueDepth: 0,
      completedTrades: 12,
      completionRate: 0.97,
      aiScore: 0.9,
      isOnline: true,
    );

void main() {
  testWidgets(
      'final pass §8 — the ad list is a LAZY sliver: only viewport-visible '
      'ads are built, never an eager Column of all cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(_surfaceSize);

    final ads = List.generate(50, _ad);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Fixed ad data: 50 ads. If the list were eager, ALL 50 cards
          // would exist in one frame.
          filteredAdsProvider.overrideWithValue(AsyncValue.data(ads)),
        ],
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(AzamanTheme.dark),
          home: const P2PMarketListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final builtCards = find.byType(VendorAdCard);
    final built = builtCards.evaluate().length;

    // Lazy contract: a 400x900 viewport shows only a handful of the 50
    // ads. Anything close to the full list is an eager build.
    expect(built, lessThan(50),
        reason: 'all ${built} ad cards were built on the first frame — the '
            'ad list is still an eagerly-built Column, not a lazy sliver');
    expect(built, greaterThan(0), reason: 'no ads rendered at all');

    // Structural: the scroll must contain a real SliverList (lazy),
    // not only SliverToBoxAdapter adapters.
    expect(find.byType(SliverList), findsOneWidget);
  });
}
