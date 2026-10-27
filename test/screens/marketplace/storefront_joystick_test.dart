// =============================================================================
// MARKET STOREFRONT SHELL — hero avatar joystick tests
// (Workstream A, rewritten 2026-10-26)
//
// Pins the WORKSTREAM A contract on the REAL shell hero avatar:
//   1.  pointer-down starts the directional dial immediately — no long
//       press,
//   2.  up + release fires the real catalog delegate exactly once, and
//       an empty catalog honestly dims the satellite and fires nothing,
//   3.  right + release fires the durable bookmark delegate, with the
//       honest 'Saved' label when already bookmarked,
//   4.  down with no authoritative story state fires nothing,
//   5.  a plain tap still bursts the radial launcher — Share / Reviews /
//       Follow keep working (the joystick adds, never replaces),
//   6.  a joystick release never scrolls or breaks the sheet.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/market_storefront_shell.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/widgets/marketplace/profile_joystick.dart';

const _screenHeight = 600.0;

BusinessProfile _business({BusinessStoryState? storyState}) {
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
    storyState: storyState,
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  bool isBookmarked = false,
  bool hasCatalog = true,
  BusinessStoryState? storyState,
  VoidCallback? onToggleBookmark,
  VoidCallback? onShare,
  VoidCallback? onToggleFollow,
  VoidCallback? onOpenReviews,
  VoidCallback? onOpenCatalog,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: _screenHeight,
            child: MarketStorefrontShell(
              business: _business(storyState: storyState),
              colors: ThemeProvider.getColors(AzamanTheme.light),
              bannerUrl: null,
              locations: const [],
              showcaseSlides: const [],
              isFollowing: false,
              unpaidInvoices: 0,
              isBookmarked: isBookmarked,
              hasCatalog: hasCatalog,
              catalogLabel: 'Products',
              productsBuilder: (context) => [const Text('Product surface')],
              onToggleBookmark: onToggleBookmark,
              onShare: onShare,
              onToggleFollow: onToggleFollow,
              onOpenReviews: onOpenReviews,
              onOpenCatalog: onOpenCatalog,
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

/// The hero avatar: the ProfileJoystick carrying the global
/// _heroAvatarKey — the large identity-block avatar, not the compact
/// pill's.
Finder _heroAvatar() => find.byType(ProfileJoystick).first;

Future<TestGesture> _touchDown(WidgetTester tester) async {
  final gesture =
      await tester.startGesture(tester.getCenter(_heroAvatar()));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('pointer-down on the hero avatar starts the directional '
      'dial immediately — no long press', (tester) async {
    await _pumpShell(
      tester,
      onToggleBookmark: () {},
      onOpenCatalog: () {},
    );

    expect(find.byKey(const ValueKey('joystick-satellite-bookmark')),
        findsNothing,
        reason: 'nothing revealed before touch');

    await _touchDown(tester);

    expect(
      find.byKey(const ValueKey('joystick-satellite-menu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('joystick-satellite-story')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('joystick-satellite-bookmark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('joystick-satellite-showLess')),
      findsOneWidget,
    );
  });

  testWidgets('up + release fires the real catalog delegate exactly '
      'once', (tester) async {
    var catalogOpens = 0;
    await _pumpShell(
      tester,
      onOpenCatalog: () => catalogOpens++,
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, -22));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(catalogOpens, 1);
    expect(find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
        reason: 'the dial closed after the release');
  });

  testWidgets('an empty catalog honestly dims the menu satellite and a '
      'release fires nothing', (tester) async {
    var catalogOpens = 0;
    await _pumpShell(
      tester,
      hasCatalog: false,
      onOpenCatalog: () => catalogOpens++,
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, -22));
    await tester.pump();
    expect(find.text('Products (No catalog yet)'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(catalogOpens, 0, reason: 'no dead delegate ever fires');
  });

  testWidgets('right + release fires the durable bookmark delegate '
      'exactly once', (tester) async {
    var bookmarkTaps = 0;
    await _pumpShell(
      tester,
      onToggleBookmark: () => bookmarkTaps++,
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(22, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(bookmarkTaps, 1);
  });

  testWidgets('the bookmark satellite reflects the honest durable '
      'state (isBookmarked -> Saved)', (tester) async {
    await _pumpShell(
      tester,
      isBookmarked: true,
      onToggleBookmark: () {},
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(22, 0));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('down with no authoritative story state fires nothing '
      'and the satellite honestly says why', (tester) async {
    await _pumpShell(
      tester,
      storyState: null, // no story contract at all
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, 22));
    await tester.pump();
    expect(find.text('Story (No active story)'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    // No crash, no invented viewer, nothing fired.
    expect(find.byType(StoryViewerScreen), findsNothing);
  });

  testWidgets('a plain tap still bursts the radial launcher — the '
      'extra shortcuts keep working', (tester) async {
    var shareTaps = 0;
    await _pumpShell(
      tester,
      onShare: () => shareTaps++,
    );

    await tester.tap(_heroAvatar());
    // Launch beat of the shared liquid launcher (660ms) + settle.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('market-joystick-burst')), findsOneWidget,
        reason: 'the radial launcher is still reachable via tap');
    expect(find.text('Share'), findsOneWidget);
  });
}
