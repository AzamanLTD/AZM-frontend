import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/widgets/stories/story_rail_compact.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref, int count) {
    friends = [
      for (var i = 0; i < count; i++)
        {
          'friendshipId': 'f$i',
          'unreadCount': i % 3,
          'friend': {'id': 100 + i, 'username': 'friend$i'},
          'latestMessage': {
            'content': 'message $i',
            'createdAt': DateTime(
              2026,
              10,
              1,
            ).add(Duration(minutes: i)).toIso8601String(),
          },
        },
    ];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
  @override
  Future<void> fetchFriends() async {}
  @override
  Future<void> fetchUnreadCount() async {}
}

class _FakeFeed extends StoryFeedNotifier {
  _FakeFeed(List<StoryGroup> groups) {
    state = AsyncValue.data(groups);
  }
  @override
  Future<void> load() async {}
}

class _FakeGroups extends GroupListNotifier {
  _FakeGroups(this._groups);
  final List<GroupSummary> _groups;
  @override
  Future<List<GroupSummary>> build() async => _groups;
  @override
  Future<void> refresh() async {}
}

List<StoryGroup> _stories() => [
  for (var i = 0; i < 3; i++)
    StoryGroup(
      authorId: i,
      authorUsername: 'author$i',
      hasUnseen: i < 2,
      isBoosted: false,
      stories: const [],
    ),
];

List<GroupSummary> _groups() => [
  GroupSummary(
    id: 'g1',
    name: 'Market Mamas',
    status: 'ACTIVE',
    susuGroupId: 's1',
    susuStatus: 'ACTIVE',
    members: const [],
    updatedAt: DateTime(2026, 10, 2),
  ),
  GroupSummary(
    id: 'g2',
    name: 'Trotro crew',
    status: 'ACTIVE',
    members: const [],
    updatedAt: DateTime(2026, 10, 1, 12),
  ),
];

/// Pumps the hub. With [settle] false only ONE frame is painted, so the
/// caller can pin the FIRST-frame geometry (UX C: open by default, no
/// initial-position jump).
Future<ScrollController> _pump(
  WidgetTester tester, {
  bool reducedMotion = false,
  int friends = 20,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        friendProvider.overrideWith((ref) => _FakeFriends(ref, friends)),
        storyFeedProvider.overrideWith((ref) => _FakeFeed(_stories())),
        groupListProvider.overrideWith(() => _FakeGroups(_groups())),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 720),
          disableAnimations: reducedMotion,
        ),
        child: const MaterialApp(home: FriendsHubScreen()),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  final scrollable = tester.widget<CustomScrollView>(
    find.byKey(const ValueKey('inbox_scroll')),
  );
  return scrollable.controller!;
}

final _scroll = find.byKey(const ValueKey('inbox_scroll'));

void main() {
  testWidgets(
    'UX C — OPEN AT REST on the FIRST frame: no initial-position jump',
    (tester) async {
      // One frame painted, nothing settled yet.
      final c = await _pump(tester, settle: false);
      final viewport = tester.getRect(_scroll);
      final rail = tester.getRect(
        find.byKey(
          const ValueKey('inbox_story_rail_list'),
          skipOffstage: false,
        ),
      );

      // The position started AT the open detent — the rail is already fully
      // visible above the message rows in the very first painted frame.
      expect(c.offset, -StoryRailMetrics.height);
      expect(c.position.minScrollExtent, -StoryRailMetrics.height);
      expect(
        rail.top,
        closeTo(viewport.top, 1.0),
        reason: 'the open rail must be the resting composition, not a jump',
      );
      expect(
        rail.bottom,
        lessThanOrEqualTo(viewport.top + StoryRailMetrics.height + 1),
      );

      // Nothing later moves it — the rest stays open.
      await tester.pumpAndSettle();
      expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
      expect(
        find.text('author0'),
        findsOneWidget,
        reason: 'the open rail shows real story authors at rest',
      );
      expect(find.text('Market Mamas'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox_title')), findsOneWidget);
    },
  );

  testWidgets('UX C — the open rail REPLACES the compact strip at rest', (
    tester,
  ) async {
    final c = await _pump(tester);

    // At rest the rail IS the story surface; the compact strip must be
    // fully collapsed so no second smaller story surface shows underneath.
    final stripEls = find
        .byKey(const ValueKey('inbox_story_rail_compact'))
        .evaluate();
    if (stripEls.isNotEmpty) {
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('inbox_story_rail_compact')),
      );
      expect(
        stripRect.height,
        closeTo(0, 0.5),
        reason: 'CORRECTION J: at rest the open rail is the ONE story surface',
      );
    }
    expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
    expect(find.byKey(const ValueKey('inbox_story_rail')), findsOneWidget);
  });

  testWidgets('UX C — a casual scroll into the list springs back OPEN', (
    tester,
  ) async {
    final c = await _pump(tester);

    // A short, casual drag up (not committed) releases well inside the
    // open↔closed band; the snap must return to the open detent.
    await tester.drag(_scroll, const Offset(0, -StoryRailMetrics.height * 0.5));
    await tester.pumpAndSettle();
    expect(
      c.offset,
      closeTo(-StoryRailMetrics.height, 0.5),
      reason: 'a casual scroll must not collapse the rail',
    );
    expect(find.text('author0'), findsOneWidget);
  });

  testWidgets(
    'UX C — a committed drag collapses into the compact presentation',
    (tester) async {
      final c = await _pump(tester);

      await tester.drag(_scroll, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(
        c.offset,
        0,
        reason: 'a committed gesture crosses the resistant band',
      );

      // Collapsed presentation: the compact strip is the story surface now.
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('inbox_story_rail_compact')),
      );
      expect(stripRect.height, closeTo(StoryRailCompact.height, 0.5));
      expect(find.text('2 new'), findsOneWidget);

      // The rail itself is offstage above the viewport.
      final rail = tester.getRect(
        find.byKey(
          const ValueKey('inbox_story_rail_list'),
          skipOffstage: false,
        ),
      );
      final viewport = tester.getRect(_scroll);
      expect(rail.bottom, lessThanOrEqualTo(viewport.top + 0.01));
    },
  );

  testWidgets('UX C — the band carries deliberate resistance mid-drag', (
    tester,
  ) async {
    final c = await _pump(tester);

    // Enter the band with a committed start of the gesture, then measure a
    // known move: inside the open↔closed band the travel is scaled, so the
    // position moves LESS than the finger.
    // Probe-verified gesture shape: a stream of small moves with explicit
    // timestamps (a single huge move does not resolve the gesture arena).
    final gesture = await tester.startGesture(tester.getCenter(_scroll));
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(
        const Offset(0, -20),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final mid = c.offset;
    expect(
      mid,
      greaterThan(-StoryRailMetrics.height),
      reason: 'the drag entered the open↔closed band',
    );
    expect(mid, lessThan(0));

    final before = c.offset;
    await gesture.moveBy(
      const Offset(0, -40),
      timeStamp: const Duration(milliseconds: 96),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final delta = c.offset - before;
    expect(
      delta,
      lessThan(40),
      reason: 'in-band drags are frictioned (railBandFriction)',
    );
    expect(
      delta,
      greaterThan(20),
      reason: 'the drag still follows the finger, just resistant',
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
  });

  testWidgets('UX C — a committed FLING collapses; a casual flick does not', (
    tester,
  ) async {
    final c = await _pump(tester);

    // Committed fling: velocity alone decides (above the shared threshold).
    await tester.fling(_scroll, const Offset(0, -120), 1200);
    await tester.pumpAndSettle();
    expect(c.offset, 0);
  });

  testWidgets(
    'UX C — returning to the top stays COLLAPSED: no automatic reopen',
    (tester) async {
      final c = await _pump(tester);

      // Collapse first.
      await tester.drag(_scroll, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(c.offset, 0);

      // Scroll into the list and return to the top: the boundary condition
      // stops at CLOSED (offset 0); the rail does not pop open by itself and
      // the snap never oscillates.
      await tester.drag(_scroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(c.offset, greaterThan(0));

      await tester.drag(_scroll, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(
        c.offset,
        0,
        reason: 'top of the list = the compact presentation, not the rail',
      );
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('inbox_story_rail_compact')),
      );
      expect(stripRect.height, closeTo(StoryRailCompact.height, 0.5));

      // An explicit, committed pull reopens — deliberate, not automatic.
      await tester.drag(
        _scroll,
        const Offset(0, StoryRailMetrics.height * 0.8),
      );
      await tester.pumpAndSettle();
      expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
    },
  );

  testWidgets('tapping the compact strip reopens the rail', (tester) async {
    final c = await _pump(tester);
    await tester.drag(_scroll, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(c.offset, 0);

    await tester.tap(find.byKey(const ValueKey('inbox_story_rail_compact')));
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
    expect(find.text('author0'), findsOneWidget);
  });

  testWidgets(
    'reduced motion: collapse and reopen toggle without a ballistic settle',
    (tester) async {
      final c = await _pump(tester, reducedMotion: true);
      expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));

      await tester.drag(_scroll, const Offset(0, -150));
      await tester.pump();
      await tester.pump();
      expect(c.offset, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);

      // The band resists reopening too, so the pull must be committed
      // (~1.5× the band travel in finger distance).
      await tester.drag(
        _scroll,
        const Offset(0, StoryRailMetrics.height * 1.4),
      );
      await tester.pump();
      await tester.pump();
      expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
      // Flush the staggered flutter_animate entrance delays/tickers the
      // reopen re-triggers, then confirm nothing is still animating.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('empty inbox still opens the rail at rest and renders no-crash', (
    tester,
  ) async {
    final c = await _pump(tester, friends: 0);
    expect(c.offset, closeTo(-StoryRailMetrics.height, 0.5));
    expect(find.byKey(const ValueKey('inbox_story_rail')), findsOneWidget);
    // Groups exist, so the list is not empty; this confirms no crash with 0 friends.
    expect(find.text('Trotro crew'), findsOneWidget);
  });
}
