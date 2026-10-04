import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/stories/inbox_story_rail_sliver.dart';
import 'package:azaman/widgets/stories/story_rail_snap_physics.dart';

void main() {
  const open = -108.0;

  group('StoryRailSnapPhysics.resolveTarget', () {
    test('rest closes below the open fraction, opens past it', () {
      // 30% pulled (offset -32.4) → back to closed.
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open * 0.3, velocity: 0), 0);
      // 50% pulled → open.
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open * 0.5, velocity: 0), open);
      // Just past the fraction counts as committed; just short does not.
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open * 0.45, velocity: 0), open);
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open * 0.35, velocity: 0), 0);
    });

    test('a fling decides by direction regardless of position', () {
      // Negative velocity = pulling down = towards open.
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: -5, velocity: -900), open);
      // Positive velocity = pushing up = towards closed.
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open + 5, velocity: 900), 0);
    });

    test('slow release is not a fling', () {
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: -5, velocity: -200), 0);
    });

    test('detents themselves are stable', () {
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: 0, velocity: 0), 0);
      expect(StoryRailSnapPhysics.resolveTarget(open: open, pixels: open, velocity: 0), open);
    });
  });

  group('InboxStoryRailSliver.revealExtent', () {
    test('0 at rest, 1 fully open, clamped, 1 when there is no rail', () {
      expect(InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: 0), 0);
      expect(InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: open), 1);
      expect(InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: open / 2), closeTo(0.5, 1e-9));
      expect(InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: 300), 0);
      expect(InboxStoryRailSliver.revealExtent(minScrollExtent: 0, pixels: 0), 1);
    });
  });
}