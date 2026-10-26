// =============================================================================
// MARKET STOREFRONT SHELL — JOYSTICK (directional shortcuts) widget tests
//
// Pins the long-press radial shortcut contract on the hero avatar:
//   1.  long-press bursts the joystick anchored on the avatar,
//   2.  ONLY wired delegates become satellites (no dead shortcuts),
//   3.  the Save satellite reflects the honest bookmark state
//       (isBookmarked → 'Saved'),
//   4.  picking a satellite closes the joystick and fires the delegate
//       exactly once,
//   5.  tapping the scrim dismisses without firing anything,
//   6.  long-press with nothing wired stays silent (no route, no crash).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/market_storefront_shell.dart';

const _screenHeight = 600.0;

BusinessProfile _business() {
  return BusinessProfile(
    id: 'biz-1',
    bizId: 'BIZ-TEST01',
    businessName: 'Makola Fresh Market',
    category: 'RETAIL',
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 42,
    completedEscrows: 40,
    userId: 1,
    totalVolume: 1200,
    averageRating: 4.8,
    reviewCount: 24,
    username: 'makola',
    description: 'Genuine Accra goods.',
    address: '12 Kojo Thompson Rd, Accra',
    logoUrl: 'https://img.example/logo.png',
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  bool isBookmarked = false,
  VoidCallback? onToggleBookmark,
  VoidCallback? onShare,
  VoidCallback? onToggleFollow,
  VoidCallback? onOpenReviews,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: _screenHeight,
            child: MarketStorefrontShell(
              business: _business(),
              colors: ThemeProvider.getColors(AzamanTheme.light),
              bannerUrl: null,
              locations: const [],
              showcaseSlides: const [],
              isFollowing: false,
              unpaidInvoices: 0,
              isBookmarked: isBookmarked,
              hasCatalog: true,
              catalogLabel: 'Products',
              productsBuilder: (context) =>
                  [const Text('Product surface')],
              onToggleBookmark: onToggleBookmark,
              onShare: onShare,
              onToggleFollow: onToggleFollow,
              onOpenReviews: onOpenReviews,
            ),
          ),
        ),
      ),
    ),
  );
  // JOYSTICK tests act at the ARRIVAL composition: the discovery
  // choreography eventually settles the sheet at the shopping snap,
  // where the hero identity is honestly faded out and pointer-ignored —
  // the joystick correctly cannot open there. Here we stay inside the
  // entrance beat (before the dip), where the avatar is live.
  await tester.pump(const Duration(milliseconds: 50));
}

/// The HERO avatar is the large (radius 36 → 72px) CircleAvatar in the
/// identity block, not the compact pill's 30px one.
Finder _heroAvatar(WidgetTester tester) {
  final candidates = find.byType(CircleAvatar);
  for (final candidate in candidates.evaluate()) {
    final rect = tester.getRect(find.byWidget(candidate.widget));
    if (rect.width >= 60) return find.byWidget(candidate.widget);
  }
  return find.byType(CircleAvatar).first;
}

Future<void> _burst(WidgetTester tester) async {
  await tester.longPress(_heroAvatar(tester));
  // Launch beat of the shared liquid launcher (660ms) + settle.
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('long-press on the hero avatar bursts the joystick '
      'anchored on it', (tester) async {
    await _pumpShell(
      tester,
      onToggleBookmark: () {},
      onShare: () {},
    );
    await _burst(tester);

    expect(find.byKey(const Key('market-joystick-burst')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('nothing wired renders nothing — no dead burst',
      (tester) async {
    await _pumpShell(tester); // all delegates null
    await _burst(tester);

    expect(find.byKey(const Key('market-joystick-burst')), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('unwired delegates stay hidden while wired ones appear',
      (tester) async {
    await _pumpShell(
      tester,
      onShare: () {},
      onOpenReviews: () {},
      // bookmark + follow deliberately NOT wired
    );
    await _burst(tester);

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
    expect(find.text('Save'), findsNothing,
        reason: 'no bookmark delegate → no Save satellite');
    expect(find.text('Follow'), findsNothing);
  });

  testWidgets('the Save satellite reflects the honest bookmark state',
      (tester) async {
    await _pumpShell(
      tester,
      isBookmarked: true,
      onToggleBookmark: () {},
    );
    await _burst(tester);

    expect(find.text('Saved'), findsOneWidget,
        reason: 'already durable-saved reads Saved, not Save');
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('picking a satellite closes the joystick and fires the '
      'delegate exactly once', (tester) async {
    var bookmarkTaps = 0;
    await _pumpShell(
      tester,
      onToggleBookmark: () => bookmarkTaps++,
    );
    await _burst(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(bookmarkTaps, 1);
    expect(find.byKey(const Key('market-joystick-burst')), findsNothing,
        reason: 'the joystick route closed after the pick');
  });

  testWidgets('tapping the scrim dismisses the joystick without firing '
      'any delegate', (tester) async {
    var bookmarkTaps = 0;
    var shareTaps = 0;
    await _pumpShell(
      tester,
      onToggleBookmark: () => bookmarkTaps++,
      onShare: () => shareTaps++,
    );
    await _burst(tester);

    // Tap far from the burst box → the barrier.
    await tester.tapAt(const Offset(20, 580));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('market-joystick-burst')), findsNothing);
    expect(bookmarkTaps, 0);
    expect(shareTaps, 0);
  });
}
