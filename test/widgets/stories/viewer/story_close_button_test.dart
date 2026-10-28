// =============================================================================
// WORKSTREAM J — the story viewer's header close button must fire ONCE.
//
// The gesture arbiter is a raw opaque Listener over the WHOLE viewer; the
// header was never marked as chrome (Workstream F2 marked only the bottom
// block). So a tap on the close IconButton ALSO fired the arbiter's tap
// navigation ("right zone = next"):
//   • on the LAST story of the last group, maybePop() ran TWICE — once
//     from the button, once from onGroupComplete → _goToGroup → maybePop —
//     and the second pop removed the route BENEATH the viewer;
//   • mid-group, the tap silently advanced the underlying group during
//     the pop animation (the next story started, markViewed fired).
//
// Contracts proven here:
//   • close on the LAST story pops EXACTLY the viewer — the route beneath
//     survives (one pop, not two);
//   • close mid-group pops the viewer WITHOUT advancing the underlying
//     group (markViewed never fires for the untapped next story);
//   • the button itself still works from every position in the group.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';

class _FakeGateway implements StoryGateway {
  @override
  Set<StoryCapability> get capabilities => const {StoryCapability.view};

  final List<String> viewed = [];

  @override
  // The real gateway contract: deduped per story id per session (the
  // group page may call markViewed repeatedly for the same story on
  // active/playback notifications; duplicates never POST twice).
  Future<void> markViewed(String storyId) async {
    if (!viewed.contains(storyId)) viewed.add(storyId);
  }

  @override
  Future<AzGatewayResult<void>> reply(String storyId, String message) async =>
      const AzUnsupported('reply');

  @override
  Future<AzGatewayResult<void>> boost(String storyId, int amount) async =>
      const AzUnsupported('boost');

  @override
  Future<AzGatewayResult<void>> react(String storyId, String emoji) async =>
      const AzUnsupported('react');

  @override
  Future<AzGatewayResult<void>> shareLink(String storyId) async =>
      const AzUnsupported('share');
}

class _SeededSearch extends BusinessSearchNotifier {
  _SeededSearch() : super(BusinessService()) {
    state = state.copyWith(results: [
      BusinessProfile(
        id: 'b1',
        bizId: 'B1',
        businessName: 'Adinkra Lounge',
        category: 'FOOD_BEVERAGE',
        isVerified: true,
        isSuspended: false,
        kybStatus: 'VERIFIED',
        totalEscrows: 4,
        completedEscrows: 4,
        userId: 1,
        totalVolume: 0,
        averageRating: 0,
        username: 'adinkra',
        createdAt: DateTime(2026, 10, 1),
      ),
    ]);
  }

  @override
  Future<void> search(String query,
      {String? category, bool? verified, String? subcategory}) async {}
}

StoryItem _item(String id) => StoryItem(
      id: id,
      mediaUrl: 'https://cdn.example.com/$id.jpg',
      mediaType: 'IMAGE',
      caption: 'Fresh jollof plates this morning',
      linkedBizId: 'B1',
      durationSeconds: 5,
      boosted: false,
      seen: false,
      createdAt: DateTime(2026, 10, 1),
    );

StoryGroup _group(List<StoryItem> stories) => StoryGroup(
      authorId: 7,
      authorUsername: 'ama',
      hasUnseen: true,
      isBoosted: false,
      stories: stories,
    );

Widget _host(List<StoryGroup> groups, _FakeGateway gateway) =>
    ProviderScope(
      overrides: [
        storyGatewayProvider.overrideWithValue(gateway),
        businessSearchProvider.overrideWith((ref) => _SeededSearch()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoryViewerScreen(
                      groups: groups,
                      heroTag: null,
                    ),
                  ),
                ),
                child: const Text('OPEN VIEWER'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.text('OPEN VIEWER'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1)); // route transition
}

Future<void> _closeViaHeaderButton(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1)); // pop transition
}

void main() {
  testWidgets(
      'close on the LAST story pops exactly ONCE — the route beneath '
      'the viewer survives', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gateway = _FakeGateway();
    await tester.pumpWidget(_host([_group([_item('s0')])], gateway));
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byIcon(Icons.close), findsOneWidget);

    await _closeViaHeaderButton(tester);

    // The viewer is gone…
    expect(find.byType(StoryViewerScreen), findsNothing,
        reason: 'the close button must dismiss the viewer');
    // …and the host route SURVIVES — a double maybePop would have removed
    // it and left a blank navigator.
    expect(find.text('OPEN VIEWER'), findsOneWidget,
        reason: 'exactly one pop fired: the route beneath the viewer '
            'must never be popped by the close button');
  });

  testWidgets(
      'close mid-group pops the viewer WITHOUT advancing the underlying '
      'group — the untapped next story is never marked viewed', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gateway = _FakeGateway();
    await tester.pumpWidget(
        _host([_group([_item('s0'), _item('s1')])], gateway));
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    // Only the FIRST story has been marked viewed so far.
    expect(gateway.viewed, ['s0']);

    await _closeViaHeaderButton(tester);

    expect(find.byType(StoryViewerScreen), findsNothing,
        reason: 'the close button must dismiss the viewer');
    // The tap must NOT have double-fired as right-zone navigation: s1
    // never started, so it was never marked viewed.
    expect(gateway.viewed, ['s0'],
        reason: 'the close tap is chrome — it must not advance the '
            'underlying group to the next story');
  });

  testWidgets('the close button still works from every position in the '
      'group', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gateway = _FakeGateway();
    await tester.pumpWidget(
        _host([_group([_item('s0'), _item('s1'), _item('s2')])], gateway));
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    // Advance to the middle story with a genuine right-zone media tap,
    // then close — the button works regardless of position.
    await tester.tap(
        find.byType(StoryViewerScreen).first,
        warnIfMissed: false);
    // Tap in the media area (well below the header, right side).
    await tester.tapAt(const Offset(300, 600));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 6)); // s1 completes

    await _closeViaHeaderButton(tester);
    expect(find.byType(StoryViewerScreen), findsNothing,
        reason: 'the close button dismisses the viewer from any story');
    expect(find.text('OPEN VIEWER'), findsOneWidget,
        reason: 'and pops only the viewer route');
  });
}
