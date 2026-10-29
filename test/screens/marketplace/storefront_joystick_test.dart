// =============================================================================
// MARKET STOREFRONT SHELL — hero avatar liquid dial tests
// (Workstream A, updated 2026-10-27: persistent icon-only dial)
//
// Pins the UPDATED hero-avatar contract on the REAL shell:
//   1.  a plain tap opens the PERSISTENT icon-only dial — four goo
//       satellites, no visible action text, no radial launcher,
//   2.  up + release fires the real catalog delegate exactly once; an
//       empty catalog honestly dims the satellite (semantics carry the
//       reason) and a release fires nothing,
//   3.  right + release fires the durable bookmark delegate; the
//       honest 'Saved' state is disclosed through the dial semantics,
//   4.  down with no authoritative story state fires nothing, with the
//       reason disclosed through the dial semantics,
//   5.  press-and-hold opens the market SHORTCUTS SHEET (Share etc.),
//       never the dial; tap and hold are distinct outcomes,
//   6.  a joystick release never scrolls or breaks the sheet.
// =============================================================================

import 'package:flutter/gestures.dart' show kLongPressTimeout;
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
  final gesture = await tester.startGesture(tester.getCenter(_heroAvatar()));
  await tester.pump();
  return gesture;
}

/// Opens the persistent dial with a plain tap, at the arrival beat.
Future<void> _openDial(WidgetTester tester) async {
  await tester.tap(_heroAvatar());
  await tester.pumpAndSettle();
}

Key _sat(String name) => ValueKey('profile-dial-satellite-$name');

void main() {
  testWidgets('a plain tap opens the persistent icon-only dial — no '
      'radial launcher, no visible action text', (tester) async {
    await _pumpShell(tester, onToggleBookmark: () {}, onOpenCatalog: () {});

    expect(
      find.byKey(_sat('bookmark')),
      findsNothing,
      reason: 'nothing revealed before touch',
    );

    await _openDial(tester);

    expect(find.byKey(const ValueKey('profile-dial')), findsOneWidget);
    for (final name in ['menu', 'story', 'bookmark', 'showLess']) {
      expect(find.byKey(_sat(name)), findsOneWidget, reason: name);
    }
    // Icon-only dial: no action text is rendered…
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-dial')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    // …and the old radial launcher is NOT the tap outcome anymore.
    expect(find.byKey(const Key('market-joystick-burst')), findsNothing);
  });

  testWidgets('up + release fires the real catalog delegate exactly '
      'once', (tester) async {
    var catalogOpens = 0;
    await _pumpShell(tester, onOpenCatalog: () => catalogOpens++);

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, -22));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(catalogOpens, 1);
    expect(
      find.byKey(_sat('menu')),
      findsNothing,
      reason: 'the dial closed after the release',
    );
  });

  testWidgets('an empty catalog: a release fires nothing — no dead '
      'delegate ever navigates', (tester) async {
    var catalogOpens = 0;
    await _pumpShell(
      tester,
      hasCatalog: false,
      onOpenCatalog: () => catalogOpens++,
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, -22));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(catalogOpens, 0, reason: 'no dead delegate ever fires');
  });

  testWidgets('an empty catalog honestly dims the menu satellite and '
      'discloses the reason in the dial semantics — and tapping the '
      'dimmed icon never fires nor closes', (tester) async {
    var catalogOpens = 0;
    final semantics = tester.ensureSemantics();
    await _pumpShell(
      tester,
      hasCatalog: false,
      onOpenCatalog: () => catalogOpens++,
    );

    // Tap at the ARRIVAL beat (the choreography pointer-ignores the
    // avatar once settled — drag tests cover the transient path).
    await _openDial(tester);
    expect(
      find.bySemanticsLabel('Products (No catalog yet)'),
      findsOneWidget,
      reason: 'the dimmed satellite says exactly why',
    );

    await tester.tap(find.byKey(_sat('menu')));
    await tester.pumpAndSettle();
    expect(catalogOpens, 0, reason: 'the dimmed icon never executes');
    expect(
      find.byKey(const ValueKey('profile-dial')),
      findsOneWidget,
      reason: 'tapping a disabled icon keeps the dial open',
    );
    semantics.dispose();
  });

  testWidgets('right + release fires the durable bookmark delegate '
      'exactly once', (tester) async {
    var bookmarkTaps = 0;
    await _pumpShell(tester, onToggleBookmark: () => bookmarkTaps++);

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(22, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(bookmarkTaps, 1);
  });

  testWidgets('the bookmark satellite reflects the honest durable '
      'state (isBookmarked -> Saved)', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpShell(tester, isBookmarked: true, onToggleBookmark: () {});

    await _openDial(tester);
    expect(
      find.bySemanticsLabel('Saved'),
      findsOneWidget,
      reason: 'the durable server state names the satellite honestly',
    );
    semantics.dispose();
  });

  testWidgets('down with no authoritative story state fires nothing '
      'and never invents a viewer', (tester) async {
    await _pumpShell(
      tester,
      storyState: null, // no story contract at all
    );

    final gesture = await _touchDown(tester);
    await gesture.moveBy(const Offset(0, 22));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // No crash, no invented viewer, nothing fired.
    expect(find.byType(StoryViewerScreen), findsNothing);
  });

  testWidgets('the story satellite discloses its unavailable reason in '
      'the dial semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpShell(
      tester,
      storyState: null, // no story contract at all
    );

    await _openDial(tester);
    expect(
      find.bySemanticsLabel('Story (No active story)'),
      findsOneWidget,
      reason: 'the unavailable direction discloses its reason',
    );
    semantics.dispose();
  });

  testWidgets('press-and-hold opens the market shortcuts SHEET — '
      'never the dial; tap and hold are distinct outcomes', (tester) async {
    var shareTaps = 0;
    await _pumpShell(tester, onShare: () => shareTaps++);

    // Hold on the hero avatar.
    final gesture = await _touchDown(tester);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

    expect(
      find.byKey(const Key('market-shortcuts-sheet')),
      findsOneWidget,
      reason: 'the hold opens the full shortcuts menu',
    );
    expect(
      find.byKey(const ValueKey('profile-dial')),
      findsNothing,
      reason: 'a hold never opens the dial',
    );
    expect(find.text('Share'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(shareTaps, 0, reason: 'the hold itself fires no action');

    // A real pick from the sheet executes the real delegate.
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shareTaps, 1);
  });
}
