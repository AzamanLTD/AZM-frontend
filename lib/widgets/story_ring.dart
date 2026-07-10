import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

// ── StoryRing ─────────────────────────────────────────────────────────────────
//
// Shows a squircle avatar with an optional story indicator ring.
//
// When [hasUnseenStory] is true:
//   • storyCount == 1 → full glowing accent ring (single solid arc)
//   • storyCount  > 1 → ring split into [storyCount] equal arc segments
//                       with a small gap between each (Instagram-style)
// When [hasUnseenStory] is false:
//   → subtle dim border, no glow
//
// New optional params:
//   storyCount   — number of story segments (default 1 = solid ring)
//   glowEnabled  — add a soft glow bloom on unseen ring (default true)

class StoryRing extends ConsumerWidget {
  final String? avatarUrl;
  final bool hasUnseenStory;
  final bool isBoosted;
  final double size;
  final int storyCount;
  final bool glowEnabled;

  const StoryRing({
    super.key,
    this.avatarUrl,
    required this.hasUnseenStory,
    required this.isBoosted,
    this.size = 64,
    this.storyCount = 1,
    this.glowEnabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final radius = size * 0.5;
    final ringPadding = hasUnseenStory ? 3.0 : 1.4;

    final ringColor = isBoosted ? colors.accent : const Color(0xFFFFD700);
    final dimColor = colors.divider;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StoryRingPainter(
          hasUnseen: hasUnseenStory,
          storyCount: storyCount.clamp(1, 20),
          ringColor: ringColor,
          dimColor: dimColor,
          strokeWidth: hasUnseenStory ? 2.4 : 1.2,
          squircleRadius: radius,
          glow: hasUnseenStory && glowEnabled,
        ),
        child: Padding(
          padding: EdgeInsets.all(ringPadding),
          child: ClipPath(
            clipper: ShapeBorderClipper(
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(radius - ringPadding),
              ),
            ),
            child: avatarUrl != null && avatarUrl!.isNotEmpty
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    errorBuilder: (_, __, ___) => _placeholder(colors),
                  )
                : _placeholder(colors),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(AzamanColors colors) => Container(
        color: colors.softSurface,
        child: Icon(Icons.person, color: colors.textTertiary, size: size * 0.45),
      );
}

// ── Custom painter ──────────────────────────────────────────────────────────

class _StoryRingPainter extends CustomPainter {
  final bool hasUnseen;
  final int storyCount;
  final Color ringColor;
  final Color dimColor;
  final double strokeWidth;
  final double squircleRadius;
  final bool glow;

  _StoryRingPainter({
    required this.hasUnseen,
    required this.storyCount,
    required this.ringColor,
    required this.dimColor,
    required this.strokeWidth,
    required this.squircleRadius,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Use a circular ring drawn around the squircle content
    // Radius is slightly less than half the widget size to keep within bounds
    final ringR = (math.min(size.width, size.height) / 2) - (strokeWidth / 2) - 0.5;

    if (!hasUnseen) {
      // Dim border — simple circle
      final paint = Paint()
        ..color = dimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, ringR, paint);
      return;
    }

    // Glow bloom layer
    if (glow) {
      final glowPaint = Paint()
        ..color = ringColor.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      if (storyCount == 1) {
        canvas.drawCircle(center, ringR, glowPaint);
      }
    }

    if (storyCount == 1) {
      // Full solid arc
      final paint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, ringR, paint);
    } else {
      // Segmented arcs — equally spaced with small gaps
      // Total gap angle (in radians) between segments
      const gapDeg = 6.0; // degrees gap per segment boundary
      final gapRad = gapDeg * math.pi / 180;
      final totalGap = gapRad * storyCount;
      final segmentSweep = (2 * math.pi - totalGap) / storyCount;

      final paint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Start at top (-π/2), draw clockwise
      double startAngle = -math.pi / 2;
      for (int i = 0; i < storyCount; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ringR),
          startAngle,
          segmentSweep,
          false,
          paint,
        );
        startAngle += segmentSweep + gapRad;
      }
    }
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) =>
      old.hasUnseen != hasUnseen ||
      old.storyCount != storyCount ||
      old.ringColor != ringColor ||
      old.dimColor != dimColor;
}
