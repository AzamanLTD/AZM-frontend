import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/widgets/stories/story_morph_overlay.dart';

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
  Finder ringsIn(Finder scope) => find.descendant(
        of: scope,
        matching: find.byKey(const ValueKey('story-ring-paint')),
      );

  testWidgets('open end: the flight lands exactly on the real row', (tester) async {
    await _pump(tester);
    final origin = tester.getTopLeft(_scroll);
    final rail = find.byKey(const ValueKey('inbox_story_rail_list'));
    final rowRings = tester.widgetList(ringsIn(rail)).length;
    expect(rowRings, greaterThanOrEqualTo(2));
    // Item 1 is story group 0 (item 0 is My story).
    final real = tester.getCenter(ringsIn(rail).at(1));
    final geo = origin + StoryMorphGeometry.rowCentre(1);
    expect((real - geo).distance, lessThan(1.0), reason: 'no jump at the open end');
  });

  testWidgets('collapsed end: the flight lands exactly on the real stack', (tester) async {
    final c = await _pump(tester);
    await tester.drag(_scroll, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(c.offset, 0);
    final origin = tester.getTopLeft(_scroll);
    final strip = find.byKey(const ValueKey('inbox_story_rail_compact'));
    for (var j = 0; j < 3; j++) {
      final real = tester.getCenter(ringsIn(strip).at(j));
      final geo = origin + StoryMorphGeometry.stackCentre(j);
      expect((real - geo).distance, lessThan(1.0), reason: 'slot $j has no jump at the closed end');
    }
  });

  testWidgets('mid-drag: the real row hides and the same avatars fly between ends', (tester) async {
    final c = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_scroll));
    for (var i = 1; i <= 4; i++) {
      await g.moveBy(const Offset(0, -15), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final p = StoryMorphOverlay.progressOf(c);
    expect(StoryMorphOverlay.inFlight(p), isTrue, reason: 'the rail is between detents');

    // The real row is hidden (nothing is drawn twice).
    final railOpacity = tester.widget<Opacity>(find
        .ancestor(of: find.byKey(const ValueKey('inbox_story_rail_list')), matching: find.byType(Opacity))
        .first);
    expect(railOpacity.opacity, 0);

    // The overlay flies one ring per story group plus My story.
    final overlay = find.byType(StoryMorphOverlay);
    final fliers = ringsIn(overlay);
    expect(tester.widgetList(fliers).length, 4);

    // Group 0 sits between its stack slot and its row place.
    final origin = tester.getTopLeft(_scroll);
    final ring = fliers.at(2); // painted back to front: groups 2,1,0 then me
    final centre = tester.getCenter(ring) - origin;
    final from = StoryMorphGeometry.stackCentre(0);
    final to = StoryMorphGeometry.rowCentre(1);
    expect(centre.dy, inInclusiveRange(from.dy - 1, to.dy + 1));
    final size = tester.getSize(ring).width;
    expect(size, inExclusiveRange(24, 64), reason: 'it is mid-flight, between the two sizes');

    await g.up(timeStamp: const Duration(milliseconds: 90));
    await tester.pumpAndSettle();
    expect(StoryMorphOverlay.inFlight(StoryMorphOverlay.progressOf(c)), isFalse);
    expect(tester.widgetList(ringsIn(overlay)).length, 0, reason: 'at rest the real widgets are back');
  });

  test('items further along the row trail, and names arrive late', () {
    expect(StoryMorphGeometry.itemProgress(0.5, 0), 0.5);
    expect(StoryMorphGeometry.itemProgress(0.5, 4), lessThan(0.5));
    expect(StoryMorphGeometry.itemProgress(1, 6), closeTo(1, 1e-9));
    expect(StoryMorphGeometry.itemProgress(0, 3), 0);
    expect(StoryMorphGeometry.rowLabelOpacity(0.6), 0);
    expect(StoryMorphGeometry.rowLabelOpacity(1), closeTo(1, 1e-9));
    expect(StoryMorphGeometry.stackLabelOpacity(0), 1);
    expect(StoryMorphGeometry.stackLabelOpacity(0.5), 0);
  });
}
