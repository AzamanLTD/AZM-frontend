import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
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

Future<void> _fonts() async {
  for (final e in {
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'MaterialIcons': 'test/goldens/fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final bytes = await File(e.value).readAsBytes();
    await (FontLoader(e.key)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)))).load();
  }
}

void main() {
  testWidgets('story morph frames', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(_fonts);
    final c = await _pump(tester);
    for (final p in [1.0, 0.75, 0.5, 0.25, 0.0]) {
      c.jumpTo(-StoryRailMetrics.height * p);
      await tester.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../../goldens/stories/morph_${(p * 100).round()}.png'));
      await tester.pumpAndSettle();
    }
  });
}
