import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

class StoryRing extends ConsumerWidget {
  final String? avatarUrl;
  final bool hasUnseenStory;
  final bool isBoosted;
  final double size;
  const StoryRing({
    super.key, this.avatarUrl, required this.hasUnseenStory,
    required this.isBoosted, this.size = 64,
  });
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    // FIX (2026-07-06): 0.34 read as "a square with rounded corners" --
    // not a true squircle. ContinuousRectangleBorder uses a superellipse
    // curve (not simple corner arcs), so pushing the radius factor much
    // closer to half the size is what actually makes the SIDES bulge
    // outward continuously (the iOS app-icon look the user wants),
    // rather than just rounding the corners of an otherwise-square edge.
    final radius = size * 0.5; // squircle curvature scales with size
 
    // FIX (2026-07-06): when hasUnseenStory is false (which is EVERY "My
    // Status" avatar, since you can't have "unseen" your own story, plus
    // any already-viewed friend story), this used BorderSide.none with no
    // fill and no gradient -- the squircle enclosure was completely
    // invisible, exactly the bug reported. Now a subtle fixed border
    // always renders so the shape reads as an intentional squircle frame
    // in every state; the accent/gradient ring is reserved for drawing
    // extra attention to an unseen (optionally boosted) story on top of
    // that base enclosure.
    final ringPadding = hasUnseenStory ? 2.5 : 1.4;
    final borderWidth = hasUnseenStory ? 2.4 : 1.2;
    final borderColor = hasUnseenStory
        ? (isBoosted ? colors.accent : colors.textTertiary.withOpacity(0.4))
        : colors.divider;

    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(width: borderWidth, color: borderColor),
    );
 
    return Container(
      width: size, height: size,
      decoration: ShapeDecoration(
        shape: shape,
        gradient: hasUnseenStory && isBoosted
          ? LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [colors.accent, colors.accent.withOpacity(0.55)],
            )
          : null,
        color: hasUnseenStory && !isBoosted ? colors.textTertiary.withOpacity(0.15) : null,
      ),
      padding: EdgeInsets.all(ringPadding),
      child: ClipPath(
        // FIX: the clip radius must shrink by the SAME amount as the
        // padding actually applied above, or the inner image gets clipped
        // to a tighter curve than the outer frame -- previously hardcoded
        // to `radius - 2.5` even when padding was 0, leaving a mismatched,
        // slightly-off-looking inset on every "seen"/My Status avatar.
        clipper: ShapeBorderClipper(
          shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius - ringPadding)),
        ),
        child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(avatarUrl!, fit: BoxFit.cover, width: size, height: size)
          : Container(color: colors.surface,
              child: Icon(Icons.person, color: colors.textTertiary)),
      ),
    );
  }
}
