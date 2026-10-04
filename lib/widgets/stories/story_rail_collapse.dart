// EXPERIENCE PASS §16 — the shared story-rail COLLAPSE grammar.
//
// Chat's story rail owns the established interaction primitives
// (StoryRailStrip, StoryRailSnapPhysics, StoryRailMetrics). The
// marketplace's expanded story rail previously kept a second
// "Telegram-like" implementation: inline 96-px travel, its own
// ratio math, and NO reduced-motion handling.
//
// This module is the single source of that grammar for any rail that
// collapses with a page's scroll (the marketplace being the first):
//
//  - The collapse TRAVEL is derived from StoryRailMetrics — a rail
//    collapses over exactly its own extent, the same relationship the
//    inbox rail's reveal uses (travel = the rail's height).
//  - The SNAP threshold is StoryRailSnapPhysics.openFraction — the
//    same open/closed decision point the chat rail snaps at.
//  - Reduced motion lands DIRECTLY: the rail is fully open below the
//    snap threshold and fully collapsed above it — no fractional
//    slide, exactly like reduced motion skips the inbox rail's
//    expressive reveal. Motion users get the 1:1 attached collapse.
//
// No new state machine: this is pure math over the shared constants,
// so Chat and Marketplace cannot drift apart again.
library;

import 'package:azaman/widgets/stories/story_rail_snap_physics.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';

abstract final class StoryRailCollapse {
  /// The collapsed rail's visual extent on the page: the rail content
  /// (ring + label gap + label, straight from StoryRailMetrics) plus the
  /// rail's own bottom breathing room. Derived, not hard-coded — 94 px,
  /// within 2 px of the 96 the marketplace previously inline-coded.
  static const double extentPx =
      StoryRailMetrics.ring + StoryRailMetrics.labelGap + StoryRailMetrics.label + 8;

  /// Scroll travel over which the rail collapses: its own extent — the
  /// rail is gone exactly when its last pixel leaves the viewport, the
  /// same travel-to-extent relationship as the inbox rail's reveal.
  static const double travelPx = extentPx;

  /// 0 = fully collapsed, 1 = fully open.
  ///
  /// [scrollOffset] is the page's current scroll offset; [reducedMotion]
  /// comes from the ambient AzMotion travel flag.
  static double ratio({
    required double scrollOffset,
    required bool reducedMotion,
  }) {
    if (reducedMotion) {
      // Land directly: open below the shared snap threshold, collapsed
      // above it. No fractional travel.
      return scrollOffset < StoryRailSnapPhysics.openFraction * travelPx
          ? 1.0
          : 0.0;
    }
    return (1.0 - scrollOffset / travelPx).clamp(0.0, 1.0);
  }
}
