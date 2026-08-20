import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ============================================================================
// SPRINGS — analytic damped-oscillator step response (0→0, 1→1).
// Mirrors liquid-taffy springs.ts (HOUSE ζ=0.434 ω=22.46, POP ζ=0.479 ω=18.09).
// ============================================================================

class DampedSpringCurve extends Curve {
  final double omega;
  final double zeta;
  const DampedSpringCurve({required this.omega, required this.zeta});

  @override
  double transformInternal(double t) {
    final d = zeta * omega;
    final wd = omega * math.sqrt(1 - zeta * zeta);
    return 1.0 - math.exp(-d * t) * (math.cos(wd * t) + (d / wd) * math.sin(wd * t));
  }
}

/// 22% overshoot — trigger, panel body, snap-home.
const Curve kHouseSpring = DampedSpringCurve(omega: 22.46, zeta: 0.434);

/// 18% overshoot — each satellite / row launch.
const Curve kPopSpring = DampedSpringCurve(omega: 18.09, zeta: 0.479);

/// cubic-bezier(0.36, 0, 0.66, -0.56) — anticipation dip before motion.
const Curve kAnticipate = Cubic(0.36, 0.0, 0.66, -0.56);

/// cubic-bezier(0.23, 1, 0.32, 1) — presses and snaps.
const Curve kOutStrong = Cubic(0.23, 1.0, 0.32, 1.0);

// ============================================================================
// GOO — blur σ ↔ alpha-threshold pairs solved by liquid-taffy (goo.ts) so the
// rendered rim stays ~1px at every σ. SVG offsets are 0..1 alpha; Flutter's
// ColorFilter.matrix translation column is 0..255, hence _kAlphaScale.
// ============================================================================

const double _kAlphaScale = 255.0;
const double kGooAlphaGain = 30.0;

class GooRim {
  final double outer;
  final double inner;
  const GooRim(this.outer, this.inner);

  static GooRim lerp(GooRim a, GooRim b, double t) =>
      GooRim(ui.lerpDouble(a.outer, b.outer, t)!, ui.lerpDouble(a.inner, b.inner, t)!);
}

const List<double> _kSigmaKnots = [1, 4, 5, 7];
const Map<int, GooRim> _kRimTable = {
  1: GooRim(-14.5146, -24.6721),
  4: GooRim(-12.25, -14.25),
  5: GooRim(-12.7296, -15.063),
  7: GooRim(-11.6925, -13.245),
};

/// Interpolates the *pair* with σ so blur and threshold always move together.
GooRim gooRimFor(double sigma) {
  final s = sigma.clamp(_kSigmaKnots.first, _kSigmaKnots.last);
  for (var i = 0; i < _kSigmaKnots.length - 1; i++) {
    final lo = _kSigmaKnots[i], hi = _kSigmaKnots[i + 1];
    if (s <= hi) {
      return GooRim.lerp(
          _kRimTable[lo.toInt()]!, _kRimTable[hi.toInt()]!, (s - lo) / (hi - lo));
    }
  }
  return _kRimTable[7]!;
}

ui.ColorFilter gooThreshold(double offset) => ui.ColorFilter.matrix(<double>[
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, kGooAlphaGain, offset * _kAlphaScale,
    ]);

const double kGooBlurRest = 1.0;
const double kGooBlurGrab = 5.0;
const double kGooBlurActive = 7.0;

typedef GooShapes = void Function(Canvas canvas, Paint paint);

/// Draws [shapes] twice through the composed blur→threshold filter: once at the
/// OUTER contour in [rim] colour, once at the INNER contour in [body] colour.
/// The sliver between the contours is the constant-width rim (liquid-taffy does
/// the same with feComposite in/in2).
void paintGoo(
  Canvas canvas, {
  required Rect bounds,
  required double sigma,
  required Color body,
  required Color rim,
  required GooShapes shapes,
}) {
  final r = gooRimFor(sigma);
  void pass(double offset, Color color) {
    final layer = Paint()
      ..imageFilter = ui.ImageFilter.compose(
        outer: gooThreshold(offset),
        inner: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal, // never smear the layer edges
        ),
      );
    canvas.saveLayer(bounds, layer);
    shapes(canvas, Paint()
      ..color = color
      ..isAntiAlias = true);
    canvas.restore();
  }

  pass(r.outer, rim);
  pass(r.inner, body);
}

// ============================================================================
// SQUIRCLE — Apple continuous corners (liquid-taffy squircle.ts).
// ============================================================================

Path squirclePath(Rect rect, double radius) {
  final w = rect.width, h = rect.height;
  final s = math.min(radius * 1.528665, math.min(w / 2, h / 2));
  double u(double k) => s * (k / 1.528665);
  final c = [1.528665, 1.08849, 0.86840, 0.63149, 0.37283, 0.16906, 0.07491]
      .map(u)
      .toList(growable: false);
  final l = rect.left, t = rect.top, rr = rect.right, b = rect.bottom;

  return Path()
    ..moveTo(l + c[0], t)
    ..lineTo(rr - c[0], t)
    ..cubicTo(rr - c[1], t, rr - c[2], t, rr - c[3], t + c[6])
    ..cubicTo(rr - c[4], t + c[5], rr - c[5], t + c[4], rr - c[6], t + c[3])
    ..cubicTo(rr, t + c[2], rr, t + c[1], rr, t + c[0])
    ..lineTo(rr, b - c[0])
    ..cubicTo(rr, b - c[1], rr, b - c[2], rr - c[6], b - c[3])
    ..cubicTo(rr - c[5], b - c[4], rr - c[4], b - c[5], rr - c[3], b - c[6])
    ..cubicTo(rr - c[2], b, rr - c[1], b, rr - c[0], b)
    ..lineTo(l + c[0], b)
    ..cubicTo(l + c[1], b, l + c[2], b, l + c[3], b - c[6])
    ..cubicTo(l + c[4], b - c[5], l + c[5], b - c[4], l + c[6], b - c[3])
    ..cubicTo(l, b - c[2], l, b - c[1], l, b - c[0])
    ..lineTo(l, t + c[0])
    ..cubicTo(l, t + c[1], l, t + c[2], l + c[6], t + c[3])
    ..cubicTo(l + c[5], t + c[4], l + c[4], t + c[5], l + c[3], t + c[6])
    ..cubicTo(l + c[2], t, l + c[1], t, l + c[0], t)
    ..close();
}

// ============================================================================
// NECK / BEAD CHAIN — liquid-taffy stretch.ts GRAB_CHAIN.
// ============================================================================

class GooBead {
  final double follow; // fraction of full travel
  final double size;   // radius multiplier
  final double thin;   // necking at full tension
  final double lag;    // trailing offset
  const GooBead(this.follow, this.size, this.thin, this.lag);
}

const List<GooBead> kGrabChain = [
  GooBead(1.00, 0.85, 0.06, 0.16),
  GooBead(0.84, 0.72, 0.16, 0.18),
  GooBead(0.68, 0.65, 0.19, 0.20),
  GooBead(0.52, 0.64, 0.19, 0.22),
  GooBead(0.36, 0.70, 0.14, 0.24),
  GooBead(0.20, 0.80, 0.08, 0.26),
];

void drawNeck(
  Canvas canvas,
  Paint paint, {
  required Offset from,
  required Offset to,
  required double baseRadius,
  required double t,
  required double tension,
}) {
  if (t <= 0.001) return;
  for (var i = 0; i < kGrabChain.length; i++) {
    final link = kGrabChain[i];
    final local = ((t - i * 0.04) / 0.6).clamp(0.0, 1.0);
    if (local <= 0) continue;
    final travel = link.follow * local;
    final p = Offset.lerp(from, to, travel)!;
    final r = baseRadius * link.size * (1 - tension * link.thin) * local;
    if (r > 0.5) canvas.drawCircle(p, r, paint);
  }
}

/// Release wobble: overshoot squash → counter-stretch → spring settle.
({double x, double y}) jelloWobble(double t) {
  if (t < 0.15) {
    final k = kOutStrong.transform(t / 0.15);
    return (x: 1 + 0.20 * k, y: 1 - 0.18 * k);
  }
  if (t < 0.33) {
    final k = Curves.easeInOut.transform((t - 0.15) / 0.18);
    return (x: 1.20 + (0.93 - 1.20) * k, y: 0.82 + (1.09 - 0.82) * k);
  }
  final k = kHouseSpring.transform(((t - 0.33) / 0.67).clamp(0.0, 1.0));
  return (x: 0.93 + 0.07 * k, y: 1.09 - 0.09 * k);
}

bool liquidReducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ============================================================================
// v3 ADDITIONS
// ============================================================================

/// Open/close state machine. Guards against rapid double-taps: a tap during
/// `opening`/`closing` is swallowed instead of inserting a second OverlayEntry
/// or removing an entry that a running reverse still paints into.
enum LiquidPhase { closed, opening, open, closing }

/// Nothing is tappable before it is readable.
///
/// v2 wrapped rows/pills in a bare `Opacity`, which still hit-tests at alpha 0 —
/// a user could tap "Transfer" before it existed on screen. Gate every animated
/// child through this instead of `Opacity`.
class LiquidReveal extends StatelessWidget {
  final double opacity;
  final double tapThreshold;
  final Widget child;
  const LiquidReveal({
    super.key,
    required this.opacity,
    required this.child,
    this.tapThreshold = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    final o = opacity.clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: o < tapThreshold,
      child: Opacity(opacity: o, child: child),
    );
  }
}

/// Minimum interactive target. Material + iOS both want ≥ 44 dp.
const double kLiquidMinTapTarget = 44.0;
