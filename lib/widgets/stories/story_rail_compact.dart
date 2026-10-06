/// Collapsed story affordance (Overhaul 04 §3.2): stacked avatars + "N new".
///
/// Also the live region that announces "Stories shown/hidden" once per
/// transition — the hub flips [railOpen] on transitions only, never per frame.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:azaman/widgets/stories/inbox_story_rail_sliver.dart';

class StoryRailCompact extends ConsumerWidget {
  final VoidCallback onTap;

  /// Whether the rail above is currently open; drives the live-region label.
  final ValueListenable<bool>? railOpen;

  /// CORRECTION J — the ONE story surface: this strip is the COLLAPSED
  /// presentation of the story rail; the pulled-in rail is its EXPANDED
  /// presentation. As the rail reveals (negative scroll extent) the strip
  /// collapses, so at full reveal NOTHING of it remains underneath the
  /// open rail — no second smaller story surface is ever visible.
  final ScrollController? reveal;

  const StoryRailCompact(
      {super.key, required this.onTap, this.railOpen, this.reveal});

  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final groups = ref.watch(
      storyFeedProvider.select((f) => f.valueOrNull ?? const <StoryGroup>[]),
    );
    final unseen = groups.where((g) => g.hasUnseen).length;
    final avatars = groups.take(3).toList(growable: false);

    final stripBody = SizedBox(
      height: height,
      child: Row(
          children: [
            const SizedBox(width: AzSpace.xl),
            if (avatars.isNotEmpty)
              SizedBox(
                width: 24.0 + 14.0 * (avatars.length - 1).clamp(0, 2),
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < avatars.length; i++)
                      Positioned(
                        left: i * 14.0,
                        child: StoryRing(
                          avatarUrl: avatars[i].authorAvatarUrl,
                          // REAL data path (§9); geometry scales to 24dp.
                          counts: StoryRingCounts.fromGroup(avatars[i]),
                          isBoosted: false,
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
            if (avatars.isNotEmpty) const SizedBox(width: AzSpace.sm),
            Text(
              unseen > 0 ? '$unseen new' : 'Stories',
              key: const ValueKey('inbox_story_rail_compact_label'),
              style: AzText.caption.copyWith(color: colors.textSecondary),
            ),
            const Spacer(),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colors.textTertiary),
            const SizedBox(width: AzSpace.xl),
          ],
        ),
    );

    final rail = reveal;
    final strip = GestureDetector(
      key: const ValueKey('inbox_story_rail_compact'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: rail == null
          ? stripBody
          : AnimatedBuilder(
              animation: rail,
              builder: (context, child) {
                // 0 = closed at rest (strip fully shown), 1 = rail fully
                // open (strip fully collapsed, nothing underneath).
                double extent = 0;
                if (rail.hasClients) {
                  final pos = rail.position;
                  if (pos.hasContentDimensions && pos.hasPixels) {
                    extent = InboxStoryRailSliver.revealExtent(
                        minScrollExtent: pos.minScrollExtent,
                        pixels: pos.pixels);
                  }
                }
                final collapse = Curves.easeOut.transform(extent);
                return Opacity(
                  opacity: 1 - collapse,
                  child: IgnorePointer(
                    ignoring: collapse > 0.5,
                    child: SizedBox(
                      height: height * (1 - collapse),
                      child: child,
                    ),
                  ),
                );
              },
              child: ExcludeSemantics(child: stripBody),
            ),
    );

    final hint = unseen > 0
        ? '$unseen new stories. Pull down or tap to open stories'
        : 'Stories. Pull down or tap to open';
    final open = railOpen;
    if (open == null) {
      return Semantics(button: true, label: hint, child: strip);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: open,
      builder: (_, isOpen, child) => Semantics(
        button: true,
        liveRegion: true,
        label: '${isOpen ? 'Stories shown' : 'Stories hidden'}. $hint',
        child: child,
      ),
      child: strip,
    );
  }
}