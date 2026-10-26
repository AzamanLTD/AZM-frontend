// =============================================================================
// WORKSTREAM F1 (2026-10-25) — the marketplace story rail's EXPLICIT
// expansion (the "pin").
//
// The defect this suite pins down: tapping the collapsed stories
// affordance while scrolled down used to `_scrollCtrl.animateTo(0)` —
// the whole feed was dragged back to the top and the scroll anchor was
// destroyed. The fix is an explicit expansion state:
//
//   • tap expands the rail IN PLACE — the page NEVER returns to the top;
//   • the results list scrolls DOWN by exactly the rail's growth (same
//     curve/duration), so the first visible results stay visually
//     anchored while the rail slides in over them;
//   • the pin only ever OPENS: the scroll-driven collapse grammar keeps
//     all its authority whenever the pin is not held;
//   • the pin hands back SEAMLESSLY when the feed returns to its top
//     (the scroll ratio there is already 1 — no jump, no opacity pop);
//   • returning from the story viewer preserves both the expansion and
//     the anchor;
//   • reduced motion lands directly, per the shared rail grammar;
//   • the collapsed affordance's geometry never jumps when the avatars'
//     unseen state changes (dims) — shared ring visuals untouched.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';
import 'package:azaman/widgets/story_ring.dart';

// ── Harness ──────────────────────────────────────────────────────────────────

/// Structural stand-in so notifiers satisfy constructors without a network
/// client (all loads are overridden; the client is never used).
class _NullApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ten deterministic businesses so the results list actually scrolls.
class _SeededSearch extends BusinessSearchNotifier {
  _SeededSearch() : super(BusinessService()) {
    state = state.copyWith(results: [
      for (var i = 0; i < 10; i++)
        BusinessProfile(
          id: 'biz-$i',
          bizId: 'BIZ-$i',
          businessName: 'Business $i',
          category: 'RETAIL',
          isVerified: true,
          isSuspended: false,
          kybStatus: 'VERIFIED',
          totalEscrows: 4,
          completedEscrows: 4,
          userId: 1,
          totalVolume: 0,
          averageRating: 0,
          username: 'biz-$i',
          createdAt: DateTime(2026, 10, 20 - i),
        ),
    ]);
  }

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

class _NoopAds extends AdFeedNotifier {
  _NoopAds() : super(_NullApiClient());

  @override
  Future<void> load() async {}
}

/// A MUTABLE following list: the tests flip the unseen ("dims") state
/// without a network call, in place.
class _MutableFollowing extends FollowingListNotifier {
  _MutableFollowing() : super(_NullApiClient());

  bool _loaded = false;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    state = AsyncValue.data(_list(unseen: true));
  }

  List<Map<String, dynamic>> _list({required bool unseen}) => [
        {
          'id': 'b1',
          'businessName': 'Adinkra Lounge',
          'logoUrl': null,
          'isVerified': true,
          'lastStoryAt': '2026-10-20T10:00:00Z',
          'lastViewedAt':
              unseen ? null : '2026-10-21T00:00:00Z', // seen after the story
        },
        {
          'id': 'b2',
          'businessName': 'Cocoa Line',
          'logoUrl': null,
          'isVerified': false,
          'lastStoryAt': '2026-10-20T11:00:00Z',
          'lastViewedAt':
              unseen ? '2026-10-19T00:00:00Z' : '2026-10-21T00:00:00Z',
        },
        {
          'id': 'b3',
          'businessName': 'Trotro Threads',
          'logoUrl': null,
          'isVerified': false,
          'lastStoryAt': '2026-10-18T09:00:00Z',
          'lastViewedAt': '2026-10-18T10:00:00Z', // stays seen either way
        },
      ];

  /// Flips every unseen story to seen (the "avatar dims" transition).
  void markAllSeen() {
    state = AsyncValue.data(_list(unseen: false));
  }
}

/// Booking service stub: the expanded rail's story fetch returns ONE real
/// production-shaped story, so the tap opens the REAL viewer route.
class _StubBookingService extends MarketplaceBookingService {
  _StubBookingService() : super(apiClient: _NullApiClient());

  @override
  Future<List<BusinessStory>> getBusinessStories(String businessProfileId) =>
      Future.value([
        BusinessStory(
          id: 's1',
          userId: 'u1',
          businessProfileId: businessProfileId,
          mediaUrl: 'https://cdn.example.com/s1.jpg',
          caption: 'Fresh stock this morning',
          createdAt: DateTime(2026, 10, 24),
          expiresAt: DateTime(2026, 10, 25, 12),
          username: 'Adinkra Lounge',
        ),
      ]);
}

/// Pumps the marketplace home with all rails seeded and inert. Returns the
/// results list's real ScrollController and the mutable following notifier.
Future<(ScrollController, _MutableFollowing)> _pumpHome(
  WidgetTester tester, {
  double width = 360,
  double height = 740,
  bool reducedMotion = false,
  MarketplaceBookingService? booking,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final following = _MutableFollowing();
  final body = Scaffold(
    extendBody: true,
    bottomNavigationBar: Container(
      height: 48,
      color: ThemeProvider().colors.surface,
      alignment: Alignment.center,
      child: const Text('48dp nav band', style: TextStyle(fontSize: 10)),
    ),
    body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        disableAnimations: reducedMotion,
      ),
      child: const MarketplaceHomeScreen(),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) => _SeededSearch()),
        followingListProvider.overrideWith((ref) => following..load()),
        adFeedProvider.overrideWith((ref) => _NoopAds()..load()),
        if (booking != null)
          marketplaceBookingServiceProvider.overrideWithValue(booking),
      ],
      child: MaterialApp(home: body),
    ),
  );
  await _settleFrames(tester);

  final list = find.byKey(const ValueKey('marketplace_results_list'));
  return (tester.widget<ListView>(list).controller!, following);
}

/// Bounded settle: advances the clock in frame-sized steps so staggered
/// entrances finish (flutter_animate delays) without pumpAndSettle, which
/// hangs on infinite shimmer loops.
Future<void> _settleFrames(WidgetTester tester, {int frames = 26}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Disposes the home and drains the screen's one-shot timers so a test can
/// end without pending-timer noise.
Future<void> _teardownHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 900));
}

/// Collapses the rail (scroll deep), taps the collapsed affordance, and
/// advances the 400ms pin animation in ticker-sized steps.
Future<void> _pinOpen(WidgetTester tester, ScrollController ctrl) async {
  ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
  await _settleFrames(tester, frames: 6);
  await tester
      .tap(find.byKey(const ValueKey('marketplace_story_rail_compact')));
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _extentHeight(WidgetTester tester) => tester
    .getRect(find.byKey(const ValueKey('marketplace_story_rail_extent')))
    .height;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('tapping the collapsed affordance expands IN PLACE — the page '
      'NEVER returns to the top', (tester) async {
    final (ctrl, _) = await _pumpHome(tester);

    ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
    await _settleFrames(tester, frames: 6);
    expect(_extentHeight(tester), closeTo(0, 0.5),
        reason: 'scrolled down: the rail is fully collapsed');

    final offsetBefore = ctrl.offset;
    await tester
        .tap(find.byKey(const ValueKey('marketplace_story_rail_compact')));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // F1 contract: the anchor is PRESERVED, not destroyed. The offset grows
    // by exactly the rail's extent (the compensation), and never drops to 0.
    expect(ctrl.offset, closeTo(offsetBefore + StoryRailCollapse.extentPx, 1.0),
        reason: 'the list scrolls DOWN by the rail growth (anchor preserved)');
    expect(ctrl.offset, greaterThan(offsetBefore));
    expect(ctrl.offset, greaterThan(StoryRailCollapse.extentPx),
        reason: 'the page is never dragged back to the top');

    // The rail is fully open, at the shared extent, with the seeded rings.
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5));
    final rings = tester.widgetList<StoryRing>(find.descendant(
      of: find.byType(MarketplaceExpandedStories),
      matching: find.byType(StoryRing),
    ));
    expect(rings.length, 3);
    await _teardownHome(tester);
  });

  testWidgets('the first visible results stay visually anchored while the '
      'rail slides in', (tester) async {
    final (ctrl, _) = await _pumpHome(tester);

    ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
    await _settleFrames(tester, frames: 6);

    // The rail grows over the TOP of the results window (content stays
    // frozen on screen), so the anchor assertion targets the LOWEST
    // visible result — it stays fully visible throughout.
    final names = tester
        .widgetList<Text>(find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^Business \d$').hasMatch(w.data!)))
        .map((t) => t.data!)
        .toSet();
    expect(names, isNotEmpty, reason: 'seeded results render in the list');
    // Pick the deepest card on screen (max rect.top) — never the covered one.
    String anchor = names.first;
    double deepest = -1;
    for (final n in names) {
      final top = tester.getTopLeft(find.text(n).first).dy;
      if (top > deepest && top < 560) {
        deepest = top;
        anchor = n;
      }
    }
    final rectBefore = tester.getRect(find.text(anchor).first);

    await tester
        .tap(find.byKey(const ValueKey('marketplace_story_rail_compact')));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final rectAfter = tester.getRect(find.text(anchor).first);
    expect(rectAfter.top, closeTo(rectBefore.top, 0.75),
        reason: 'the compensation scroll keeps the visible content fixed '
            'on screen while the rail grows in over the window top');
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5));
    await _teardownHome(tester);
  });

  testWidgets('explicit expansion state: scrolling down while pinned keeps '
      'the rail open', (tester) async {
    final (ctrl, _) = await _pumpHome(tester);

    await _pinOpen(tester, ctrl);
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5));

    // Scroll further down: the explicit expansion state holds — the rail
    // does NOT collapse again behind the user's back.
    ctrl.jumpTo(ctrl.offset + 400);
    await _settleFrames(tester, frames: 6);
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5),
        reason: 'the pin is an explicit expansion state, not a scroll trick');
    await _teardownHome(tester);
  });

  testWidgets('seamless handback: returning to the top hands control back '
      'to the scroll grammar — with no jump', (tester) async {
    final (ctrl, _) = await _pumpHome(tester);

    await _pinOpen(tester, ctrl);
    final pinnedExtent = _extentHeight(tester);

    // Scroll back to the feed's top: the pin releases — the rail is STILL
    // fully open (the scroll ratio at the top is 1), so the handoff is
    // invisible: same height, same frame budget.
    ctrl.jumpTo(0);
    await _settleFrames(tester, frames: 6);
    expect(_extentHeight(tester), closeTo(pinnedExtent, 0.5),
        reason: 'the pin handback at the top is seamless — no height jump');

    // The scroll grammar owns the rail again: scrolling down collapses it.
    ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
    await _settleFrames(tester, frames: 6);
    expect(_extentHeight(tester), closeTo(0, 0.5),
        reason: 'after the handback the scroll-driven collapse resumes');
    await _teardownHome(tester);
  });

  testWidgets('returning from the story viewer preserves the expansion and '
      'the anchor', (tester) async {
    final (ctrl, _) = await _pumpHome(tester, booking: _StubBookingService());

    await _pinOpen(tester, ctrl);
    final offsetAfterPin = ctrl.offset;
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5));

    // Tap the first expanded ring: the REAL viewer route opens.
    final ring = find.descendant(
      of: find.byType(MarketplaceExpandedStories),
      matching: find.byType(StoryRing),
    ).first;
    await tester.tap(ring, warnIfMissed: false);
    await _settleFrames(tester, frames: 12);
    expect(find.byType(StoryViewerScreen), findsOneWidget,
        reason: 'the tap opened the real story viewer route');

    // Return from the viewer: the pin AND the anchor survived the round trip.
    // The immersive viewer has no back button (vertical-drag dismissal
    // grammar); return the way a route return does.
    final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first);
    navigator.pop();
    await _settleFrames(tester, frames: 12);
    expect(find.byType(StoryViewerScreen), findsNothing);
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5),
        reason: 'the explicit expansion state survives the viewer');
    expect(ctrl.offset, closeTo(offsetAfterPin, 1.0),
        reason: 'the scroll anchor survives the viewer');
    await _teardownHome(tester);
  });

  testWidgets('reduced motion: the pin lands directly — no fractional slide',
      (tester) async {
    final (ctrl, _) = await _pumpHome(tester, reducedMotion: true);

    ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
    await tester.pump(const Duration(milliseconds: 100));
    final offsetBefore = ctrl.offset;
    expect(_extentHeight(tester), closeTo(0, 0.5));

    await tester
        .tap(find.byKey(const ValueKey('marketplace_story_rail_compact')));
    await tester.pump(const Duration(milliseconds: 50));

    // Direct landing: full extent and full compensation in the SAME frame.
    expect(_extentHeight(tester), closeTo(StoryRailCollapse.extentPx, 0.5));
    expect(ctrl.offset, closeTo(offsetBefore + StoryRailCollapse.extentPx, 1.0));
    await _teardownHome(tester);
  });

  testWidgets('no layout jump when the avatars\' unseen state changes '
      '(dims)', (tester) async {
    final (ctrl, following) = await _pumpHome(tester);

    ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
    await _settleFrames(tester, frames: 6);
    final affordance =
        find.byKey(const ValueKey('marketplace_story_rail_compact'));
    final rectBefore = tester.getRect(affordance);

    // Every unseen story becomes seen — the rings dim, the label changes.
    following.markAllSeen();
    await _settleFrames(tester, frames: 6);

    final rectAfter = tester.getRect(affordance);
    expect(rectAfter.height, closeTo(rectBefore.height, 0.5),
        reason: 'the dims transition never resizes the affordance');
    expect(rectAfter.width, closeTo(rectBefore.width, 0.5));
    expect(rectAfter.top, closeTo(rectBefore.top, 0.5),
        reason: 'and never moves it — no layout jump');
    await _teardownHome(tester);
  });
}
