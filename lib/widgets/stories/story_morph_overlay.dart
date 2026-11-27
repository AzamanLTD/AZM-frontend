// lib/widgets/stories/story_morph_overlay.dart
// =============================================================================
// THE STORY MORPH — one set of avatars, travelling.
//
// Telegram's stories feel physical because nothing cross-fades: the SAME
// avatars fly between the open row and the collapsed stack, tied frame by
// frame to the scroll, and the list moves with them. This layer is that
// flight.
//
//   open (p = 1)                         collapsed (p = 0)
//   ( me ) ( a ) ( b ) ( c ) ( d )  →    (a)(b)(c)  3 new          ⌄
//    names fade in late                   label + chevron fade in early
//
// At rest the REAL widgets are shown and interactive (the row with its tap
// and hold dial; the compact strip with its tap). Only while the rail is
// between its detents (0 < p < 1) do they hide and this layer draw the same
// avatars at interpolated positions and sizes. The layer ignores pointers,
// so the drag keeps driving the scroll. It reads the row's horizontal
// offset, so a flight always starts where the avatar really is.
//
// Geometry is pure ([StoryMorphGeometry]) and pinned by tests against the
// real row and strip at both ends.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:azaman/widgets/stories/inbox_story_rail_sliver.dart';
import 'package:azaman/widgets/stories/story_rail_compact.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';

/// Where things sit at either end of the morph, in viewport coordinates
/// (the top-left of the inbox scroll view).
abstract final class StoryMorphGeometry {
  /// The open row: item k (k = 0 is "My story"; k = i + 1 is story group i).
  static const double rowInset = AzSpace.xl;
  static const double rowPitch = StoryRailMetrics.ring + (AzSpace.lg - 2);

  static Offset rowCentre(int k, {double scrollX = 0}) => Offset(
        rowInset + k * rowPitch + StoryRailMetrics.ring / 2 - scrollX,
        StoryRailMetrics.verticalPad + StoryRailMetrics.ring / 2,
      );

  static double get rowLabelTop =>
      StoryRailMetrics.verticalPad + StoryRailMetrics.ring + StoryRailMetrics.labelGap;

  /// The collapsed stack: slot j (0..2) of the compact strip.
  static Offset stackCentre(int j) => Offset(
        AzSpace.xl + j * CompactStoryRail.ringOverlap + CompactStoryRail.ringSize / 2,
        StoryRailCompact.height / 2,
      );

  /// Progress of item [k] given rail progress [p] (0 collapsed, 1 open).
  /// Items further along the row trail slightly, so the row unfurls from
  /// the left the way Telegram's does, and folds back right-first.
  static double itemProgress(double p, int k) {
    final lag = math.min(k, 6) * 0.035;
    return ((p - lag) / (1 - lag)).clamp(0.0, 1.0);
  }

  /// Names under the row arrive late, once the avatars have nearly landed.
  static double rowLabelOpacity(double p) => ((p - 0.78) / 0.22).clamp(0.0, 1.0);

  /// The stack's "N new" label and chevron leave early.
  static double stackLabelOpacity(double p) => ((0.3 - p) / 0.3).clamp(0.0, 1.0);
}

class StoryMorphOverlay extends ConsumerWidget {
  const StoryMorphOverlay({
    super.key,
    required this.scroll,
    this.railScroll,
  });

  /// The inbox's vertical controller (the rail's open/closed progress).
  final ScrollController scroll;

  /// The open row's horizontal controller, when the row scrolls sideways.
  final ScrollController? railScroll;

  /// Rail progress from the inbox position: 0 collapsed, 1 open.
  static double progressOf(ScrollController c) {
    if (!c.hasClients) return 1;
    final pos = c.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return 1;
    return InboxStoryRailSliver.revealExtent(
      minScrollExtent: pos.minScrollExtent,
      pixels: pos.pixels,
    );
  }

  /// True when the real widgets should hide for the morph.
  static bool inFlight(double p) => p > 0.001 && p < 0.999;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final groups = ref.watch(storyFeedProvider.select((f) => f.valueOrNull ?? const <StoryGroup>[]));
    final myAvatar = ref.watch(authProvider.select((a) => a.user?.profilePictureUrl));
    final unseen = groups.where((g) => g.hasUnseen).length;
    final listenables = <Listenable>[scroll, if (railScroll != null) railScroll!];

    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge(listenables),
          builder: (context, _) {
            final p = progressOf(scroll);
            if (!inFlight(p)) return const SizedBox.shrink();
            final scrollX = (railScroll?.hasClients ?? false) ? railScroll!.offset : 0.0;
            final width = MediaQuery.sizeOf(context).width;
            final stackCount = math.min(3, groups.length);
            final children = <Widget>[];

            // Collapsed label + chevron, leaving early.
            final stackLabel = StoryMorphGeometry.stackLabelOpacity(p);
            if (stackLabel > 0 && stackCount > 0) {
              children.add(Positioned(
                left: AzSpace.xl +
                    CompactStoryRail.ringSize +
                    CompactStoryRail.ringOverlap * (stackCount - 1) +
                    AzSpace.sm,
                right: AzSpace.xl,
                top: 0,
                height: StoryRailCompact.height,
                child: Opacity(
                  opacity: stackLabel,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          unseen > 0 ? '$unseen new' : 'Stories',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AzText.caption.copyWith(color: colors.textSecondary),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colors.textTertiary),
                    ],
                  ),
                ),
              ));
            }

            // Avatars, back to front: later items first so the stack's
            // left-most avatar ends on top, as in the strip.
            Widget flier({
              required int k,
              required int slot,
              required String? avatarUrl,
              required StoryRingCounts counts,
              required bool fades,
              String? label,
              bool isMe = false,
            }) {
              final t = StoryMorphGeometry.itemProgress(p, k);
              final from = StoryMorphGeometry.stackCentre(slot);
              final to = StoryMorphGeometry.rowCentre(k, scrollX: scrollX);
              // Position and size move together, 1:1 with the finger: the
              // pitch (14 → 78) and the size (24 → 64) open in step, so the
              // avatars overlap like the stack early and separate cleanly as
              // they land, never clumping mid-flight.
              final centre = Offset.lerp(from, to, t)!;
              final size = lerpDouble(CompactStoryRail.ringSize, StoryRailMetrics.ring, t)!;
              final opacity = fades ? t * t : 1.0;
              final labelOpacity = StoryMorphGeometry.rowLabelOpacity(p);
              return Positioned(
                left: centre.dx - StoryRailMetrics.ring / 2,
                top: centre.dy - size / 2,
                width: StoryRailMetrics.ring,
                child: Opacity(
                  opacity: opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: size,
                        height: size,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomRight,
                          children: [
                            StoryRing(avatarUrl: avatarUrl, counts: counts, size: size),
                            if (isMe)
                              Container(
                                width: size * 0.31,
                                height: size * 0.31,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.accent,
                                  border: Border.all(color: colors.surface, width: 2),
                                ),
                                child: Icon(Icons.add,
                                    size: size * 0.2, color: colors.isDark ? Colors.black : Colors.white),
                              ),
                          ],
                        ),
                      ),
                      if (label != null && labelOpacity > 0)
                        Padding(
                          padding: EdgeInsets.only(
                            top: math.max(0, StoryMorphGeometry.rowLabelTop - (centre.dy + size / 2)),
                          ),
                          child: Opacity(
                            opacity: labelOpacity,
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AzText.caption.copyWith(color: colors.textSecondary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            for (var i = groups.length - 1; i >= 0; i--) {
              final k = i + 1;
              final rowX = StoryMorphGeometry.rowCentre(k, scrollX: scrollX).dx;
              // Only what is or will be on screen.
              if (i >= 3 && (rowX < -StoryRailMetrics.ring || rowX > width + StoryRailMetrics.ring)) continue;
              final g = groups[i];
              children.add(flier(
                k: k,
                slot: math.min(i, 2),
                avatarUrl: g.authorAvatarUrl,
                counts: StoryRingCounts.fromGroup(g),
                fades: i >= 3,
                label: g.authorUsername,
              ));
            }
            // "My story" folds into the first slot and fades.
            children.add(flier(
              k: 0,
              slot: 0,
              avatarUrl: myAvatar,
              counts: const StoryRingCounts.empty(),
              fades: true,
              label: 'My story',
              isMe: true,
            ));

            return Stack(clipBehavior: Clip.hardEdge, children: children);
          },
        ),
      ),
    );
  }
}
