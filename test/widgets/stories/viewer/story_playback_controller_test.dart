// Playback controller: index advancement, pause holds, duration updates
// (Overhaul 05 §3.1). Pure controller tests — no widgets, no video.
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/widgets/stories/viewer/story_playback_controller.dart';

class _TestVSync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

StoryItem _item(String id, {int duration = 5}) => StoryItem(
      id: id,
      mediaUrl: 'https://cdn.example.com/$id.jpg',
      mediaType: 'IMAGE',
      durationSeconds: duration,
      boosted: false,
      seen: false,
      createdAt: DateTime(2026, 10, 1),
    );

StoryGroup _group(int count) => StoryGroup(
      authorId: 7,
      authorUsername: 'ama',
      hasUnseen: true,
      isBoosted: false,
      stories: List.generate(count, (i) => _item('s$i')),
    );

void main() {
  final vsync = _TestVSync();

  StoryPlaybackController start(
    StoryGroup group, {
    int initial = 0,
    void Function()? onComplete,
    void Function()? onRewind,
  }) {
    final controller = StoryPlaybackController(
      vsync: vsync,
      group: group,
      onGroupComplete: onComplete ?? () {},
      onGroupRewindPast: onRewind ?? () {},
    );
    controller.setActive(true);
    controller.start(initialIndex: initial);
    return controller;
  }

  test('durationFor clamps to 1..60 seconds', () {
    expect(StoryPlaybackController.durationFor(_item('a', duration: 0)),
        const Duration(seconds: 1));
    expect(StoryPlaybackController.durationFor(_item('a', duration: 999)),
        const Duration(seconds: 60));
    expect(StoryPlaybackController.durationFor(_item('a', duration: 5)),
        const Duration(seconds: 5));
  });

  testWidgets('advances one item per completed progress, in order',
      (tester) async {
    final controller = start(_group(3));
    expect(controller.index, 0);
    // Tickers started outside a frame baseline at their first tick, and the
    // controller completes an item only on the tick AFTER its full duration,
    // so each item needs: baseline frame + duration + one completion frame.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 5)); // item 0 runs
    await tester.pump(const Duration(milliseconds: 16)); // completion lands
    expect(controller.index, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.index, 2);
    controller.dispose();
  });

  testWidgets('group complete fires only after the last item finishes',
      (tester) async {
    var completions = 0;
    final controller = start(_group(2), onComplete: () => completions++);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16)); // item 0 → item 1
    expect(completions, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16)); // item 1 completes
    expect(completions, 1);
    // The controller does NOT wrap around on its own.
    expect(controller.index, 1);
    controller.dispose();
  });

  testWidgets('previous() rewinds within the group, then rewinds past it',
      (tester) async {
    var rewinds = 0;
    final controller = start(_group(2), onRewind: () => rewinds++);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16)); // now on item 1
    controller.previous();
    expect(controller.index, 0);
    controller.previous();
    expect(rewinds, 1);
    controller.dispose();
  });

  test('hold ORs reasons; only the last release resumes', () {
    final controller = start(_group(3));
    expect(controller.isPaused, isFalse);

    controller.hold(PauseReason.hold);
    expect(controller.isPaused, isTrue);
    controller.release(PauseReason.hold);
    expect(controller.isPaused, isFalse);

    // Overlapping causes: releasing one leaves the other holding.
    controller.hold(PauseReason.hold);
    controller.hold(PauseReason.zoom);
    controller.release(PauseReason.hold);
    expect(controller.isPaused, isTrue);
    controller.release(PauseReason.zoom);
    expect(controller.isPaused, isFalse);
    controller.dispose();
  });

  test('setDuration keeps the current progress value', () {
    final controller = start(_group(3));
    controller.progress.value = 0.5;
    controller.setDuration(const Duration(seconds: 9));
    expect(controller.progress.value, closeTo(0.5, 0.001));
    expect(controller.progress.duration, const Duration(seconds: 9));
    controller.dispose();
  });

  test('setActive(false) pauses an inactive page mid-item', () {
    final controller = start(_group(3));
    controller.progress.value = 0.4;
    controller.setActive(false);
    expect(controller.isPaused, isTrue);
    expect(controller.progress.isAnimating, isFalse);
    final pausedValue = controller.progress.value;
    controller.setActive(true);
    expect(controller.isPaused, isFalse);
    expect(controller.progress.value, closeTo(pausedValue, 0.001));
    controller.dispose();
  });

  test('inactive pages never advance on their own', () {
    final controller = StoryPlaybackController(
      vsync: vsync,
      group: _group(2),
      onGroupComplete: () => fail('inactive page must not complete'),
      onGroupRewindPast: () {},
    );
    controller.start(initialIndex: 0);
    expect(controller.isActive, isFalse);
    expect(controller.progress.isAnimating, isFalse);
    controller.dispose();
  });
}
