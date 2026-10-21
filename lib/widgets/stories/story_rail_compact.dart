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


/// Data-neutral item for the shared collapsed story presentation.
///
/// Surfaces supply their own story sources (chat: the personal story
/// feed; marketplace: followed businesses) — the geometry and visual
/// language below is the ONE collapsed presentation.
@immutable
class CompactStoryItem {
  final String? avatarUrl;
  final StoryRingCounts counts;

  /// Verified/boosted ring treatment (real data only, §9).
  final bool isBoosted;

  const CompactStoryItem({
    required this.avatarUrl,
    required this.counts,
    this.isBoosted = false,
  });
}

/// The SHARED collapsed story presentation (Workstream A, 2026-10-21).
///
/// The same visual language on every story surface: up to three
/// overlapping 24dp circular [StoryRing]s (14dp overlap), a caption
/// label, and an expand chevron — exactly the geometry the chat hub's
/// collapsed rail has always rendered. Callers differ only in DATA
/// ([CompactStoryItem]s) and in whether the chevron sits at the row's
/// far edge (chat's full-width strip) or right beside the label
/// (marketplace's header-row affordance).
class CompactStoryRail extends ConsumerWidget {
  /// Rings are 24dp and overlap by 14dp — the chat collapsed geometry.
  static const double ringSize = 24;
  static const double ringOverlap = 14;

  final List<CompactStoryItem> items;
  final String label;
  final VoidCallback onTap;

  /// Chat (full-width strip): the chevron floats at the far edge.
  /// Marketplace (left affordance in the header row): the chevron sits
  /// directly after the label so the action icons keep the row's right.
  final bool chevronAtEnd;

  /// Chat pads the strip with the rail's leading space; the marketplace
  /// header row already carries its own horizontal padding.
  final EdgeInsets padding;

  final Key? stripKey;
  final Key? labelKey;

  const CompactStoryRail({
    super.key,
    this.stripKey,
    this.labelKey,
    required this.items,
    required this.label,
    required this.onTap,
    this.chevronAtEnd = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AzSpace.xl),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final avatars = items.take(3).toList(growable: false);

    final chevron = Icon(
      Icons.keyboard_arrow_down_rounded,
      size: 18,
      color: colors.textTertiary,
    );

    return GestureDetector(
      key: stripKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: StoryRailCompact.height,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (avatars.isNotEmpty)
                SizedBox(
                  width: ringSize + ringOverlap * (avatars.length - 1).clamp(0, 2),
                  height: ringSize,
                  child: Stack(
                    children: [
                      for (var i = 0; i < avatars.length; i++)
                        Positioned(
                          left: i * ringOverlap,
                          child: StoryRing(
                            avatarUrl: avatars[i].avatarUrl,
                            counts: avatars[i].counts,
                            isBoosted: avatars[i].isBoosted,
                            size: ringSize,
                          ),
                        ),
                    ],
                  ),
                ),
              if (avatars.isNotEmpty) const SizedBox(width: AzSpace.sm),
              // Flexible + ellipsis: when the affordance is squeezed by the
              // action icons on a 320dp header row, the label gracefully
              // truncates instead of overflowing — the ring geometry never
              // scales (parity is the point of this component).
              Flexible(
                child: Text(
                  label,
                  key: labelKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AzText.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              if (chevronAtEnd) ...[
                const Spacer(),
                chevron,
              ] else
                chevron,
            ],
          ),
        ),
      ),
    );
  }
}

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
    final groups = ref.watch(
      storyFeedProvider.select((f) => f.valueOrNull ?? const <StoryGroup>[]),
    );
    final unseen = groups.where((g) => g.hasUnseen).length;
    final avatars = groups.take(3).toList(growable: false);

    // Workstream A (2026-10-21): the strip body is the SHARED collapsed
    // presentation — the marketplace header renders the same component
    // with business data, so the two surfaces cannot drift apart again.
    final stripBody = CompactStoryRail(
      stripKey: const ValueKey('inbox_story_rail_compact_body'),
      labelKey: const ValueKey('inbox_story_rail_compact_label'),
      items: [
        for (final g in avatars)
          CompactStoryItem(
            avatarUrl: g.authorAvatarUrl,
            // REAL data path (§9); geometry scales to 24dp.
            counts: StoryRingCounts.fromGroup(g),
            isBoosted: false,
          ),
      ],
      label: unseen > 0 ? '$unseen new' : 'Stories',
      onTap: onTap,
      chevronAtEnd: true,
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