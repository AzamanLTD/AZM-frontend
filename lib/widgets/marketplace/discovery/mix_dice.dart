// =============================================================================
// AZAMAN — MIX DIE (custom-painted isometric die on the Mix button)
//
// The in-place Mix mode's signature mark: an isometric die/cube with THREE
// visible faces and real pips, custom-painted (no raster asset, no sprite
// sheet, so it themes light/dark and any pixel ratio).
//
// MOTION CONTRACT (the review's "one restrained short 3D twist"):
//   • At rest the die paints fully (a settled cube — no idle animation).
//   • On ACTIVATION (Mix turned on) it plays ONE short grow-out-of-the-
//     button: the cube scales up from a small seed while twisting about
//     its vertical axis, landing on the settled pose. It never loops,
//     never re-fires while active, and never animates while inactive.
//   • REDUCED MOTION (AzMotion, the app's authoritative resolver): the
//     die snaps to the settled pose — no scale tween, no twist. The static
//     mark still communicates the mode.
//
// The pseudo-3D twist is a horizontal shear (a Y-axis rotation projected
// to 2D) — deliberately cheap, one painter, no 3D engine.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';

/// The painted die. [active] tints the faces with the accent while Mix is
/// on; the activation animation is driven by the widget's internal
/// controller (one-shot, activation-edge-triggered).
class MixDie extends ConsumerStatefulWidget {
  const MixDie({super.key, required this.active, this.size = 22});

  /// Whether Mix mode is on (accent-tinted faces + activation edge).
  final bool active;

  /// Logical size of the die's layout box.
  final double size;

  @override
  ConsumerState<MixDie> createState() => _MixDieState();
}

class _MixDieState extends ConsumerState<MixDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void initState() {
    super.initState();
    // Settled from the first frame — an idle die never animates.
    _grow.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant MixDie old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      // ONE restrained grow+twist on activation. Reduced motion: land
      // directly (AzMotion is the app's authoritative resolver — the same
      // gate the deck and story rails use).
      if (!AzMotion.of(context).travel) {
        _grow.value = 1.0;
      } else {
        _grow.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return AnimatedBuilder(
      animation: _grow,
      builder: (context, _) => CustomPaint(
        key: const ValueKey('mix_die'),
        size: Size.square(widget.size),
        painter: _IsoDiePainter(
          t: _grow.value,
          active: widget.active,
          colors: colors,
        ),
      ),
    );
  }
}

/// The isometric die painter: three faces (top, left, right) with pips
/// (top 3 · left 1 · right 5 — a real dice arrangement, not decoration).
class _IsoDiePainter extends CustomPainter {
  _IsoDiePainter({required this.t, required this.active, required this.colors});

  /// Activation progress 0..1 (1 = settled). Reduced-motion never passes a
  /// mid value.
  final double t;
  final bool active;
  final AzamanColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // Grow out of the button: seed → full cube (easeOutCubic, restrained).
    final growCurve = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final scale = 0.3 + 0.7 * growCurve;

    // The twist: starts at ~0.62 rad and unwinds to 0 as it settles. One
    // short twist, gone by the time the die lands.
    final twist =
        (1 - Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0))) * 0.62;

    final base = active ? colors.accent : colors.textTertiary;
    final top = Color.lerp(base, Colors.white, 0.42)!;
    final left = base;
    final right = Color.lerp(base, Colors.black, 0.30)!;
    final pip = colors.background;

    // ── Face geometry (2:1 isometric, half-width u, half-height v) ────────
    final u = s * 0.46;
    final v = s * 0.23;
    final faceH = s * 0.52; // vertical extent of each side face

    canvas.save();
    canvas.translate(s / 2, s / 2 + s * 0.06); // optical centering
    canvas.scale(scale, scale);

    // Pseudo-3D Y-axis rotation: shear the X axis by the twist angle — the
    // cube visibly turns about its vertical axis without any 3D engine.
    final shear = Matrix4.identity()..setEntry(0, 2, twist * 0.5);
    canvas.transform(shear.storage);

    // Top face (diamond).
    final topFace = Path()
      ..moveTo(0, -faceH / 2 - 2 * v)
      ..lineTo(u, -faceH / 2 - v)
      ..lineTo(0, -faceH / 2)
      ..lineTo(-u, -faceH / 2 - v)
      ..close();

    // Left face: parallelogram under the top face's left edge.
    final leftFace = Path()
      ..moveTo(-u, -faceH / 2 - v)
      ..lineTo(0, -faceH / 2)
      ..lineTo(0, faceH / 2)
      ..lineTo(-u, faceH / 2 - v)
      ..close();

    // Right face: mirror of the left.
    final rightFace = Path()
      ..moveTo(0, -faceH / 2)
      ..lineTo(u, -faceH / 2 - v)
      ..lineTo(u, faceH / 2 - v)
      ..lineTo(0, faceH / 2)
      ..close();

    final facePaint = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = colors.background.withValues(alpha: 0.35);

    facePaint.color = left;
    canvas.drawPath(leftFace, facePaint);
    facePaint.color = right;
    canvas.drawPath(rightFace, facePaint);
    facePaint.color = top;
    canvas.drawPath(topFace, facePaint);
    canvas.drawPath(topFace, edgePaint);

    // ── Pips ──────────────────────────────────────────────────────────────
    final pipPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = pip;
    final r = s * 0.055;

    // Top face: 3 pips along its center line.
    canvas.drawCircle(Offset(0, -faceH / 2 - v * 1.55), r * 0.8, pipPaint);
    canvas.drawCircle(
      Offset(-u * 0.30, -faceH / 2 - v * 1.15),
      r * 0.8,
      pipPaint,
    );
    canvas.drawCircle(
      Offset(u * 0.30, -faceH / 2 - v * 1.15),
      r * 0.8,
      pipPaint,
    );

    // Left face: 1 pip (center).
    canvas.drawCircle(Offset(-u * 0.5, -v * 0.15), r * 0.85, pipPaint);

    // Right face: 5 pips (quincunx).
    canvas.drawCircle(Offset(u * 0.48, -v * 0.9), r * 0.6, pipPaint);
    canvas.drawCircle(Offset(u * 0.48, v * 0.9), r * 0.6, pipPaint);
    canvas.drawCircle(Offset(u * 0.10, -v * 0.9), r * 0.6, pipPaint);
    canvas.drawCircle(Offset(u * 0.10, v * 0.9), r * 0.6, pipPaint);
    canvas.drawCircle(Offset(u * 0.29, 0), r * 0.6, pipPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_IsoDiePainter old) =>
      t != old.t || active != old.active || colors != old.colors;
}
