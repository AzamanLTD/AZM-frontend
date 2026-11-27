/// The story rail as the sliver *before* the inbox center (Overhaul 04 §3.4,
/// UX pass C: the hub rests at the OPEN detent, so this sliver is fully
/// revealed on entry; scrolling into the list collapses it).
///
/// Fade/scale read the controller through an `AnimatedBuilder`; the rail's
/// child is built once and only rewrapped on drag ticks — chat rows never
/// rebuild because of the pull.
library;

import 'package:flutter/material.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/widgets/stories/story_morph_overlay.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';

class InboxStoryRailSliver extends StatelessWidget {
  final ScrollController controller;
  final void Function(List<StoryGroup> groups, int index) onOpenGroup;
  final VoidCallback onCreate;

  /// Profile and Message on the story hold dial (optional).
  final StoryPersonActions? personActions;

  /// The open row's horizontal controller (read by the story morph).
  final ScrollController? railScroll;

  const InboxStoryRailSliver({
    super.key,
    required this.controller,
    required this.onOpenGroup,
    required this.onCreate,
    this.personActions,
    this.railScroll,
  });

  /// 0 = hidden, 1 = fully open. Pure; exposed for tests.
  static double revealExtent({
    required double minScrollExtent,
    required double pixels,
  }) {
    if (minScrollExtent >= 0) return 1;
    return (pixels / minScrollExtent).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      key: const ValueKey('inbox_story_rail'),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            double extent = 1;
            // During the very first layout the position is attached but has
            // no content dimensions yet — treat that as "nothing revealed".
            if (controller.hasClients) {
              final pos = controller.position;
              if (pos.hasContentDimensions && pos.hasPixels) {
                extent = revealExtent(
                  minScrollExtent: pos.minScrollExtent,
                  pixels: pos.pixels,
                );
              } else {
                extent = 0;
              }
            }
            // The real row shows only at rest. Between the detents the
            // StoryMorphOverlay flies the same avatars instead (no
            // cross-fade: nothing is ever drawn twice).
            final flying = StoryMorphOverlay.inFlight(extent);
            return IgnorePointer(
              ignoring: flying,
              child: Opacity(opacity: flying ? 0 : 1, child: child),
            );
          },
          child: StoryRailStrip(
            onOpenGroup: onOpenGroup,
            onCreate: onCreate,
            personActions: personActions,
            controller: railScroll,
          ),
        ),
      ),
    );
  }
}
