import 'package:flutter/widgets.dart' show AxisDirection, FixedScrollMetrics;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/stories/inbox_story_rail_sliver.dart';
import 'package:azaman/widgets/stories/story_rail_snap_physics.dart';

void main() {
  const open = -108.0;

  group('StoryRailSnapPhysics.resolveTarget', () {
    test('rest closes below the open fraction, opens past it', () {
      // 30% pulled (offset -32.4) → back to closed.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open * 0.3,
          velocity: 0,
        ),
        0,
      );
      // 50% pulled → open.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open * 0.5,
          velocity: 0,
        ),
        open,
      );
      // Just past the fraction counts as committed; just short does not.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open * 0.45,
          velocity: 0,
        ),
        open,
      );
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open * 0.35,
          velocity: 0,
        ),
        0,
      );
    });

    test('a fling decides by direction regardless of position', () {
      // Negative velocity = pulling down = towards open.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: -5,
          velocity: -900,
        ),
        open,
      );
      // Positive velocity = pushing up = towards closed.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open + 5,
          velocity: 900,
        ),
        0,
      );
    });

    test('slow release is not a fling', () {
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: -5,
          velocity: -200,
        ),
        0,
      );
    });

    test('UX C — a CASUAL flick below the fling threshold does not toggle', () {
      // 800 px/s used to be a fling (old threshold 600) that collapsed the
      // rail by direction alone. Now it is a casual scroll: position wins,
      // and the position is well short of the commit fraction.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: -98,
          velocity: 800,
        ),
        open,
      );
      // A committed fling still decides by direction.
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: -98,
          velocity: 1200,
        ),
        0,
      );
    });

    test('detents themselves are stable', () {
      expect(
        StoryRailSnapPhysics.resolveTarget(open: open, pixels: 0, velocity: 0),
        0,
      );
      expect(
        StoryRailSnapPhysics.resolveTarget(
          open: open,
          pixels: open,
          velocity: 0,
        ),
        open,
      );
    });
  });

  group('UX C — rail band friction', () {
    const physics = StoryRailSnapPhysics(travel: true);

    FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: open,
      maxScrollExtent: 500,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    test('a drag traveling inside the band is resisted', () {
      // Finger equivalent of -40px: the user offset is inverted from
      // scroll pixels, so a -40 user offset moves pixels +40.
      expect(
        physics.applyPhysicsToUserOffset(metrics(-60), -40),
        closeTo(-40 * StoryRailSnapPhysics.railBandFriction, 0.001),
      );
    });

    test('band crossing a detent keeps the outside portion 1:1', () {
      // From open (-108), a -200 user offset travels +200 in pixels: the
      // 108px band slice shrinks to 65%, the 92px list remainder is 1:1.
      final applied = physics.applyPhysicsToUserOffset(metrics(open), -200);
      const bandPart = 108 * StoryRailSnapPhysics.railBandFriction;
      expect(applied, closeTo(-(bandPart + 92), 0.001));
    });

    test('drags entirely outside the band are untouched', () {
      expect(physics.applyPhysicsToUserOffset(metrics(100), -40), -40);
      expect(physics.applyPhysicsToUserOffset(metrics(open), 40), 40);
    });
  });

  group('InboxStoryRailSliver.revealExtent', () {
    test('0 at rest, 1 fully open, clamped, 1 when there is no rail', () {
      expect(
        InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: 0),
        0,
      );
      expect(
        InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: open),
        1,
      );
      expect(
        InboxStoryRailSliver.revealExtent(
          minScrollExtent: open,
          pixels: open / 2,
        ),
        closeTo(0.5, 1e-9),
      );
      expect(
        InboxStoryRailSliver.revealExtent(minScrollExtent: open, pixels: 300),
        0,
      );
      expect(
        InboxStoryRailSliver.revealExtent(minScrollExtent: 0, pixels: 0),
        1,
      );
    });
  });
}
