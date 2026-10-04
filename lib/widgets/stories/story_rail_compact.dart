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

class StoryRailCompact extends ConsumerWidget {
  final VoidCallback onTap;

  /// Whether the rail above is currently open; drives the live-region label.
  final ValueListenable<bool>? railOpen;

  const StoryRailCompact({super.key, required this.onTap, this.railOpen});

  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final groups = ref.watch(
      storyFeedProvider.select((f) => f.valueOrNull ?? const <StoryGroup>[]),
    );
    final unseen = groups.where((g) => g.hasUnseen).length;
    final avatars = groups.take(3).toList(growable: false);

    final strip = GestureDetector(
      key: const ValueKey('inbox_story_rail_compact'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
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
                          hasUnseenStory: avatars[i].hasUnseen,
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