/// Expanded story rail (Overhaul 04 §3.1).
///
/// Extracted from the inbox body so the hub and any other surface share one
/// rail. Layout constants are derived in [StoryRailMetrics], not sprinkled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/motion/az_identity_morph.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/story_ring.dart';

abstract final class StoryRailMetrics {
  static const double ring = 64;
  static const double labelGap = AzSpace.xs + 2;
  static const double label = 16;
  static const double verticalPad = AzSpace.md;

  /// Full rail height: ring + gap + one caption line + vertical padding.
  static const double height = ring + labelGap + label + verticalPad * 2; // 108
}

class StoryRailStrip extends ConsumerWidget {
  final void Function(List<StoryGroup> groups, int index) onOpenGroup;
  final VoidCallback onCreate;

  const StoryRailStrip({super.key, required this.onOpenGroup, required this.onCreate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final feed = ref.watch(storyFeedProvider);
    final myAvatar = ref.watch(authProvider.select((a) => a.user?.profilePictureUrl));
    // A failed feed shows only "My story" — same as the old body.
    final groups = feed.valueOrNull ?? const <StoryGroup>[];

    return SizedBox(
      height: StoryRailMetrics.height,
      child: ListView.separated(
        key: const ValueKey('inbox_story_rail_list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AzSpace.xl,
          vertical: StoryRailMetrics.verticalPad,
        ),
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.lg - 2),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _RailItem(
              label: 'My story',
              labelColor: colors.textSecondary,
              onTap: onCreate,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  StoryRing(
                    avatarUrl: myAvatar,
                    // "My story" tile is not a story state — plain border.
                    counts: const StoryRingCounts.empty(),
                    isBoosted: false,
                    size: StoryRailMetrics.ring,
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 14,
                      color: colors.isDark ? Colors.black : Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }
          final g = groups[i - 1];
          return _RailItem(
            label: g.authorUsername,
            labelColor: g.hasUnseen ? colors.textPrimary : colors.textSecondary,
            onTap: () => onOpenGroup(groups, i - 1),
            child: AzIdentityMorph(
              tag: AzIdentityTag.story(g.authorId),
              travel: AzMotion.of(context).travel,
              child: StoryRing(
                avatarUrl: g.authorAvatarUrl,
                // REAL data path: exact seen/unseen counts from the feed.
                counts: StoryRingCounts.fromGroup(g),
                isBoosted: g.isBoosted,
                size: StoryRailMetrics.ring,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  final Widget child;

  const _RailItem({
    required this.label,
    required this.labelColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label story',
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: StoryRailMetrics.ring,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(height: StoryRailMetrics.labelGap),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AzText.caption.copyWith(color: labelColor),
                ),
              ],
            ),
          ),
        ),
      );
}