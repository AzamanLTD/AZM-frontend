// =============================================================================
// AZMAN — WALLET POCKET SURFACE  (WALLET POUCH §3)
//
// The designed foreground "pouch" of the Home card deck: a deep
// carbon/graphite leather-like pocket with a shallow concave mouth, drawn
// as a real material — never a flat black rectangle, never a blur.
//
//   * restrained multi-stop gradient body (carbon/graphite leather)
//   * shallow concave curved opening (Bézier mouth), with the pocket's
//     front panel height driven by the deck's shared animation progress
//   * a fine recessed seam following the curve, and an inset, evenly
//     spaced stitching path along it — each short stitch rotated to its
//     local path tangent via PathMetrics + getTangentForOffset
//   * rounded outer corners, subtle perimeter bevel, controlled top-edge
//     highlight and a soft contact shadow the mouth casts onto the cards
//   * low-contrast, DETERMINISTIC grain texture (fixed-seed procedural
//     dots — no photographic asset, no resolution dependence)
//   * two small reinforcement tacks near the opening ends
//   * fully OPAQUE: nothing beneath (balance figures, rates, chips) can
//     ever show through
//
// The painter repaints only when the geometry (mouth position) or theme
// changes; the deck wraps it in a RepaintBoundary so the card animations do
// not repaint the pouch pixels, and vice versa.
// =============================================================================

import 'package:flutter/material.dart';

/// The pocket geometry: pure, unit-testable.
///
/// One concave mouth Bézier spanning the width with a shallow center dip
/// [concavity] deep (positive dips down), corner rounding [corner] on the
/// outer bottom corners, and the top edge ending flush with the side rails.
class WalletPocketGeometry {
  const WalletPocketGeometry({
    this.corner = 24,
    this.concavity = 7.0,
    this.seamInset = 9.0,
    this.stitchLength = 5.0,
    this.stitchGap = 6.0,
  });

  /// Outer bottom-corner rounding of the pocket body.
  final double corner;

  /// How deep (px) the mouth's center dips below its end heights.
  final double concavity;

  /// Vertical distance from the mouth curve down to the seam/stitch path.
  final double seamInset;

  /// Length of one stitch segment along the seam.
  final double stitchLength;

  /// Gap between stitches.
  final double stitchGap;

  /// The mouth curve: from the left rail at y=0 dipping to y=concavity at
  /// the center and back to the right rail at y=0 (local coordinates).
  Path mouthPath(double width) {
    final w = width;
    return Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(w * 0.5, concavity * 2, w, 0);
  }

  /// The seam path, offset [seamInset] below the mouth curve.
  Path seamPath(double width) {
    final w = width;
    return Path()
      ..moveTo(0, seamInset)
      ..quadraticBezierTo(w * 0.5, seamInset + concavity * 2, w, seamInset);
  }

  /// Y of the mouth curve at horizontal position [x] (0..width).
  double mouthYAt(double width, double x) {
    final t = (x / width).clamp(0.0, 1.0);
    // Quadratic Bézier with P0=(0,0), P1=(w/2, 2c), P2=(w,0).
    final mt = 1 - t;
    return 2 * mt * t * (concavity * 2);
  }
}

/// The painted pocket. Stack it in FRONT of the cards:
///
///   Stack(children: [cards..., WalletPocketSurface(mouthY: ...), ...])
///
/// [mouthY] is the pocket's mouth top position within the stack; the body
/// paints from the mouth curve down to the stack's bottom. Animate
/// [mouthY] with the deck's shared progress — the painter itself has no
/// controller (§5: one authoritative progress drives card, pouch and
/// shadow).
class WalletPocketSurface extends StatelessWidget {
  const WalletPocketSurface({
    super.key,
    required this.mouthY,
    this.dark = true,
    this.geometry = const WalletPocketGeometry(),
    this.seed = 20261016,
  });

  /// The pocket mouth's top position (stack coordinates).
  final double mouthY;

  /// Theme luminance — the pocket is a physical object, so it keeps its
  /// carbon identity in both themes; the light theme only softens the
  /// highlight/contrast slightly so it does not read as a hole.
  final bool dark;

  final WalletPocketGeometry geometry;

  /// Fixed grain seed — deterministic across frames, devices and tests.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WalletPocketPainter(
          mouthY: mouthY,
          dark: dark,
          geometry: geometry,
          seed: seed,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WalletPocketPainter extends CustomPainter {
  _WalletPocketPainter({
    required this.mouthY,
    required this.dark,
    required this.geometry,
    required this.seed,
  });

  final double mouthY;
  final bool dark;
  final WalletPocketGeometry geometry;
  final int seed;

  static const _bodyTop = Color(0xFF33363B);
  static const _bodyMid = Color(0xFF232629);
  static const _bodyBottom = Color(0xFF17181B);
  static const _stitch = Color(0xFF78797D);
  static const _tack = Color(0xFF101114);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final g = geometry;
    final mouthTop = mouthY;
    final concavity = g.concavity;

    // ── Body path: mouth curve on top, rounded outer corners below ──────
    final body = Path()
      ..moveTo(0, mouthTop)
      ..quadraticBezierTo(w * 0.5, mouthTop + concavity * 2, w, mouthTop)
      ..lineTo(w, h - g.corner)
      ..quadraticBezierTo(w, h, w - g.corner, h)
      ..lineTo(g.corner, h)
      ..quadraticBezierTo(0, h, 0, h - g.corner)
      ..close();

    // Multi-stop graphite gradient: subtle ceiling light at the mouth,
    // deepening to near-black at the base — leather reads as lit material.
    final bodyPaint = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_bodyTop, _bodyMid, _bodyBottom],
        stops: [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, mouthTop, w, h - mouthTop));
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(Rect.fromLTWH(0, mouthTop, w, h - mouthTop), bodyPaint);

    // ── Deterministic grain (inside the clip, cheap) ────────────────────
    // Low-contrast procedural speckle from a fixed-seed LCG: a sparse dot
    // lattice that never blurs, never loads an asset, and renders
    // identically on every width.
    final grain = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.028);
    var v = seed;
    double next() {
      // xorshift-ish deterministic 0..1
      v = (v * 1103515245 + 12345) & 0x7fffffff;
      return v / 0x7fffffff;
    }

    const cell = 7.0;
    for (var y = mouthTop + concavity; y < h; y += cell) {
      for (var x = 0.0; x < w; x += cell) {
        if (next() > 0.72) {
          canvas.drawCircle(
            Offset(x + next() * cell, y + next() * cell * 0.5),
            0.6 + next() * 0.5,
            grain,
          );
        }
      }
    }

    // ── Recessed seam + stitching along the curve ────────────────────────
    final seam = g.seamPath(w);
    final seamShift = mouthTop;

    // Recessed channel: a slightly darker line under the stitches gives the
    // seam its inset depth.
    final channelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..isAntiAlias = true;
    canvas.drawPath(seam.shift(Offset(0, seamShift)), channelPaint);

    // Stitches: evenly spaced short segments, each rotated to its local
    // path tangent (PathMetrics + getTangentForOffset — §3 suggestion).
    final stitchPaint = Paint()
      ..color = _stitch.withValues(alpha: dark ? 0.55 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final metrics = seam.computeMetrics();
    for (final metric in metrics) {
      final total = metric.length;
      final step = g.stitchLength + g.stitchGap;
      var dist = 3.0;
      while (dist + g.stitchLength <= total - 3.0) {
        final start = metric.getTangentForOffset(dist);
        final end = metric.getTangentForOffset(dist + g.stitchLength);
        if (start != null && end != null) {
          canvas.drawLine(
            start.position + Offset(0, seamShift),
            end.position + Offset(0, seamShift),
            stitchPaint,
          );
        }
        dist += step;
      }
    }

    // Side rails: the stitching continues briefly down each side edge of
    // the pocket (the reference's stitching runs along the top and sides).
    final railStep = g.stitchLength + g.stitchGap;
    for (final x in [g.seamInset + 1.0, w - g.seamInset - 1.0]) {
      var y = mouthTop + concavity + g.seamInset + railStep;
      while (y < h - g.corner - 4) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + g.stitchLength),
          stitchPaint,
        );
        y += railStep;
      }
    }

    // ── Reinforcement tacks near the opening ends ───────────────────────
    for (final tx in [22.0, w - 22.0]) {
      final cy = mouthTop + g.mouthYAt(w, tx) + 14;
      // Indented ring + darker centre: a rivet pressed into the leather.
      canvas.drawCircle(
        Offset(tx, cy),
        3.4,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        Offset(tx, cy),
        2.2,
        Paint()
          ..color = _tack
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        Offset(tx, cy - 0.7),
        1.0,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..isAntiAlias = true,
      );
    }

    // ── Perimeter bevel + controlled highlights ─────────────────────────
    // Outer bevel: a hair-thin darker outline rounds the silhouette.
    final bevel = Paint()
      ..color = Colors.black.withValues(alpha: dark ? 0.55 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;
    canvas.drawPath(body, bevel);

    // Mouth highlight: a soft light line ON the curve's crest — the
    // pocket's edge catching the same top-left lamp as the card rims.
    final mouthGlow = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.16 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..isAntiAlias = true;
    canvas.drawPath(g.mouthPath(w).shift(Offset(0, mouthTop)), mouthGlow);

    canvas.restore();

    // ── Contact shadow cast UP onto the cards above the mouth ───────────
    // Drawn OUTSIDE the clip: a soft gradient just above the mouth edge,
    // so the cards read as sliding INTO the pocket (depth cue).
    final shadowRect = Rect.fromLTWH(0, mouthTop - 7, w, 8 + concavity);
    final shadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: dark ? 0.38 : 0.28),
        ],
      ).createShader(shadowRect);
    final shadowPath = Path()
      ..moveTo(0, mouthTop - 7)
      ..lineTo(w, mouthTop - 7)
      ..lineTo(w, mouthTop + concavity * 2)
      ..quadraticBezierTo(
        w * 0.5,
        mouthTop + concavity * 4 - 7,
        0,
        mouthTop + concavity * 2,
      )
      ..close();
    canvas.drawPath(shadowPath, shadow);
  }

  @override
  bool shouldRepaint(_WalletPocketPainter old) =>
      old.mouthY != mouthY ||
      old.dark != dark ||
      old.seed != seed ||
      old.geometry != geometry;
}
