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
            'createdAt': DateTime(2026, 10, 1).add(Duration(minutes: i)).toIso8601String(),
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
        StoryGroup(authorId: i, authorUsername: 'author$i', hasUnseen: i < 2, isBoosted: false, stories: const []),
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
      GroupSummary(id: 'g2', name: 'Trotro crew', status: 'ACTIVE', members: const [], updatedAt: DateTime(2026, 10, 1, 12)),
    ];

Future<ScrollController> _pump(WidgetTester tester, {bool reducedMotion = false, int friends = 20}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      friendProvider.overrideWith((ref) => _FakeFriends(ref, friends)),
      storyFeedProvider.overrideWith((ref) => _FakeFeed(_stories())),
      groupListProvider.overrideWith(() => _FakeGroups(_groups())),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: const Size(360, 720), disableAnimations: reducedMotion),
      child: const MaterialApp(home: FriendsHubScreen()),
    ),
  ));
  await tester.pumpAndSettle();
  final scrollable = tester.widget<CustomScrollView>(find.byKey(const ValueKey('inbox_scroll')));
  return scrollable.controller!;
}

final _scroll = find.byKey(const ValueKey('inbox_scroll'));

void main() {
  testWidgets('closed at rest: offset 0, rail above the viewport, compact strip counts unseen', (tester) async {
    final c = await _pump(tester);
    expect(c.offset, 0);
    expect(c.position.minScrollExtent, -StoryRailMetrics.height);
    expect(find.text('2 new'), findsOneWidget);
    // The rail is laid out (cache extent) but offstage above the viewport.
    final rail = tester.getRect(find.byKey(const ValueKey('inbox_story_rail_list'), skipOffstage: false));
    final viewport = tester.getRect(_scroll);
    expect(rail.bottom, lessThanOrEqualTo(viewport.top + 0.01));
    // Rows render; the header kept its tier.
    expect(find.text('Market Mamas'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox_title')), findsOneWidget);
  });

  testWidgets('a short pull snaps closed; a longer pull snaps open', (tester) async {
    final c = await _pump(tester);
    await tester.drag(_scroll, const Offset(0, StoryRailMetrics.height * 0.3));
    await tester.pumpAndSettle();
    expect(c.offset, 0);

    await tester.drag(_scroll, const Offset(0, StoryRailMetrics.height * 0.6));
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(c.position.minScrollExtent, 0.5));
    expect(find.text('author0'), findsOneWidget);
  });

  testWidgets('tapping the compact strip opens; pushing the list up closes and stops at 0', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('inbox_story_rail_compact')));
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(c.position.minScrollExtent, 0.5));

    // Scroll into the list: the rail closes first, then rows move.
    await tester.drag(_scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(c.offset, greaterThan(0));

    // Back to the top stops at closed; no accidental reopen.
    await tester.drag(_scroll, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(c.offset, 0);
  });

  testWidgets('CORRECTION J: the open rail REPLACES the compact strip — '
      'no smaller story surface underneath', (tester) async {
    final c = await _pump(tester);

    // At rest the strip is the story surface's collapsed presentation.
    var stripRect =
        tester.getRect(find.byKey(const ValueKey('inbox_story_rail_compact')));
    expect(stripRect.height, closeTo(StoryRailCompact.height, 0.5));

    // Open the rail.
    await tester.tap(find.byKey(const ValueKey('inbox_story_rail_compact')));
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(c.position.minScrollExtent, 0.5));

    // The strip has fully collapsed — zero height (or culled entirely at
    // zero extent), so NOTHING remains underneath the expanded story
    // surface. The expanded rail IS the active story surface.
    final stripEls =
        find.byKey(const ValueKey('inbox_story_rail_compact')).evaluate();
    if (stripEls.isNotEmpty) {
      stripRect = tester.getRect(
          find.byKey(const ValueKey('inbox_story_rail_compact')));
      expect(stripRect.height, closeTo(0, 0.5),
          reason: 'the ONE story surface: at full reveal the compact strip '
              'must not remain as a second smaller story strip');
    }
    expect(find.byKey(const ValueKey('inbox_story_rail')), findsOneWidget);

    // Closing returns the strip cleanly — the collapsed presentation is
    // back at its resting height.
    await tester.drag(_scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(_scroll, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(c.offset, 0);
    stripRect =
        tester.getRect(find.byKey(const ValueKey('inbox_story_rail_compact')));
    expect(stripRect.height, closeTo(StoryRailCompact.height, 0.5));
  });

  testWidgets('reduced motion: the rail toggles without a ballistic settle', (tester) async {
    final c = await _pump(tester, reducedMotion: true);
    await tester.drag(_scroll, const Offset(0, StoryRailMetrics.height * 0.6));
    await tester.pump();
    await tester.pump();
    expect(c.offset, closeTo(c.position.minScrollExtent, 0.5));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('empty inbox still offers the rail and the empty state', (tester) async {
    await _pump(tester, friends: 0);
    expect(find.byKey(const ValueKey('inbox_story_rail_compact')), findsOneWidget);
    // Groups exist, so the list is not empty; this just confirms no crash with 0 friends.
    expect(find.text('Trotro crew'), findsOneWidget);
  });
}