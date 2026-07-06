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
 
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: hasUnseenStory
        ? BorderSide(width: 2.4, color: isBoosted ? colors.accent : colors.textTertiary.withOpacity(0.4))
        : BorderSide.none,
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
      padding: EdgeInsets.all(hasUnseenStory ? 2.5 : 0),
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius - 2.5)),
        ),
        child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(avatarUrl!, fit: BoxFit.cover, width: size, height: size)
          : Container(color: colors.surface,
              child: Icon(Icons.person, color: colors.textTertiary)),
      ),
    );
  }
}
