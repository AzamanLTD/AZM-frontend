// Viewer screen + shell (Overhaul 05 §5): vertical dismiss, group hand-off,
// view marking through the gateway seam, reduced-motion instants.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/widgets/stories/viewer/story_details_sheet.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';

class _FakeGateway implements StoryGateway {
  @override
  Set<StoryCapability> get capabilities => const {
        StoryCapability.view,
        StoryCapability.boost,
      };

  final List<String> viewed = [];

  @override
  Future<void> markViewed(String storyId) async => viewed.add(storyId);

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

StoryItem _item(String id) => StoryItem(
      id: id,
      mediaUrl: 'https://cdn.example.com/$id.jpg',
      mediaType: 'IMAGE',
      durationSeconds: 5,
      boosted: false,
      seen: false,
      createdAt: DateTime(2026, 10, 1),
    );

StoryGroup _group(String author, List<String> ids) => StoryGroup(
      authorId: author == 'ama' ? 7 : 8,
      authorUsername: author,
      hasUnseen: true,
      isBoosted: false,
      stories: [for (final id in ids) _item(id)],
    );

Widget _host(_FakeGateway gateway, List<StoryGroup> groups) => ProviderScope(
      overrides: [storyGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    StoryViewerScreen(groups: groups, heroTag: null),
              )),
              child: const Text('OPEN VIEWER'),
            ),
          ),
        ),
      ),
    );

/// One item: baseline frame + full 5s + the completion tick.
Future<void> _runItem(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // Test surface is 800x600 → dismiss denominator is 300px (h/2).

  testWidgets('opens on the initial group and marks only its story viewed',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_host(
        gateway, [_group('ama', ['s0', 's1']), _group('kofi', ['t0', 't1'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // route transition

    expect(gateway.viewed, contains('s0'));
    expect(gateway.viewed.toSet(), {'s0'},
        reason: 'the inactive creator is never marked');
  });

  testWidgets('completing a creator advances to the next; the last one pops',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_host(
        gateway, [_group('ama', ['s0', 's1']), _group('kofi', ['t0', 't1'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Group 0 runs both items to completion.
    await _runItem(tester); // s0
    expect(gateway.viewed.toSet(), {'s0', 's1'});
    await _runItem(tester); // s1 → group 0 completes
    // Page animation to creator 2 (active flips at the midpoint).
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(gateway.viewed.toSet(), {'s0', 's1', 't0'},
        reason: 'activation of the next creator marks its story');

    // Group 1 runs both items; its completion pops the viewer.
    await _runItem(tester); // t0
    await _runItem(tester); // t1 → last group completes
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400)); // pop transition
    expect(find.text('OPEN VIEWER'), findsOneWidget,
        reason: 'completing the final creator closes the viewer');
  });

  testWidgets('a short vertical pull springs back; a long one dismisses',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_host(
        gateway, [_group('ama', ['s0']), _group('kofi', ['t0'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Short pull: 60px → dismiss 0.2, below the 0.35 commit line.
    final short = await tester.startGesture(const Offset(300, 300));
    await short.moveBy(const Offset(0, 60));
    await tester.pump();
    await short.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // spring back
    expect(find.text('OPEN VIEWER'), findsNothing,
        reason: 'a short pull releases back to the viewer');

    // Long pull: 200px → dismiss 0.67 → commit → pop.
    final long = await tester.startGesture(const Offset(300, 300));
    await long.moveBy(const Offset(0, 200));
    await tester.pump();
    await long.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('OPEN VIEWER'), findsOneWidget,
        reason: 'a decisive pull dismisses the viewer');
  });

  testWidgets('reduced motion: dismiss settles instantly, no spring frames',
      (tester) async {
    AzSensory.reduceMotionOverrideIsSet = true;
    AzSensory.reduceMotionOverride = true;
    addTearDown(() {
      AzSensory.reduceMotionOverrideIsSet = false;
      AzSensory.reduceMotionOverride = false;
    });

    final gateway = _FakeGateway();
    await tester.pumpWidget(_host(
        gateway, [_group('ama', ['s0']), _group('kofi', ['t0'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // route transition

    // Short pull 60px (dismiss 0.2), release → instant settle at 0 with no
    // frames pumped. Then a 90px pull lands at 0.3 — still short of the 0.35
    // commit line — which is only true if the previous pull really settled
    // to zero instantly. With travel enabled this sequence reaches 0.5 and
    // the viewer would have popped.
    final first = await tester.startGesture(const Offset(300, 300));
    await first.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 40));
    await first.up(); // no pump: reduced motion needs no settle frames
    final second = await tester.startGesture(const Offset(300, 300));
    await second.moveBy(const Offset(0, 90));
    await second.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('OPEN VIEWER'), findsNothing,
        reason: 'instant settle keeps 0.2 + 0.3 below the commit line');
  });

  // ── Review pass 2: cancel intent + details-swipe dedupe ─────────────────

  testWidgets('a system-cancelled touch never advances the story',
      (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(_host(gateway, [_group('ama', ['s0', 's1'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 of 2'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1 of 2'), findsOneWidget,
        reason: 'pointer cancel (notification shade, system gesture) must '
            'not act as a tap on the right half');
  });

  testWidgets('a swipe-up opens the details sheet exactly once per gesture',
      (tester) async {
    // Capable gateway: the shell's capability gate passes, so the sheet
    // really opens — and must not stack per pointer-update.
    final gateway = _ViewersGateway();
    await tester.pumpWidget(_host(
        gateway, [_group('ama', ['s0']), _group('kofi', ['t0'])]));
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final gesture = await tester.startGesture(const Offset(300, 300));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StoryDetailsSheet), findsOneWidget,
        reason: 'three upward updates must open ONE sheet, not three');
    await gesture.up();
    await tester.pump();
  });
}

/// Gateway that advertises viewers (as the backend someday will), so the
/// shell's swipe-up gate passes and the sheet path is exercised.
class _ViewersGateway extends _FakeGateway {
  @override
  final Set<StoryCapability> capabilities = const {
    StoryCapability.view,
    StoryCapability.viewers,
  };
}
