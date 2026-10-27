// ============================================================================
// DIAL GOO PAINTER — the ONE shared goo-dial painter behind both liquid
// dials: the marketplace category speed dial (PR #142) and the profile
// liquid dial (profile_joystick.dart).
//
// Extracted verbatim from category_speed_dial.dart's _DialGooPainter so
// the category selector's established appearance is untouched: the same
// flight/sigma envelope, the same satellite launch timing
// (satelliteScale / satelliteTravel), the same neck chain and the same
// blur→threshold double pass from liquid_engine's paintGoo.
//
// The two dials differ only in shape metrics, expressed as parameters:
//   * anchorRadius / satelliteRadius  — squircle corner radii (the
//     category dial's pill radius vs the profile dial's circle radius).
//   * neckBaseRadius                   — the goo bead chain thickness.
//   * anchorAsRing                     — the profile dial paints its
//     anchor as a RING (even-odd outer minus inner) so the avatar PHOTO
//     stays visible through the middle; the category dial paints the
//     filled pill and re-draws its opaque ghost on top.
//   * neckStartRadius                  — distance from the anchor center
//     where the bead chains start. The category dial starts beads at the
//     center (its ghost pill covers them); the profile dial starts them
//     at the avatar rim so no goo bead ever paints over the photo.
// ============================================================================

import 'package:flutter/material.dart';

import 'liquid_engine.dart';
import 'liquid_placement.dart';

// ── Satellite launch timing (verbatim from the category dial) ──────────────

const double _restScale = 0.12;

/// Two-beat launch: OOZE (0.16s to 0.42) then LAUNCH on the pop spring, with
/// the width axis 30 ms behind the height axis.
({double sx, double sy}) satelliteScale(double t, int index) {
  final at = 0.03 + index * 0.045;
  final local = t - at;
  if (local <= 0) return (sx: _restScale, sy: _restScale);
  if (local < 0.16) {
    final k = Curves.easeInOut.transform(local / 0.16);
    final s = _restScale + (0.42 - _restScale) * k;
    return (sx: s, sy: s);
  }
  final ky = kPopSpring.transform(((local - 0.16) / 0.30).clamp(0.0, 1.0));
  final kx = kPopSpring.transform(((local - 0.19) / 0.30).clamp(0.0, 1.0));
  return (sx: 0.42 + 0.58 * kx, sy: 0.42 + 0.58 * ky);
}

double satelliteTravel(double t, int index) =>
    kHouseSpring.transform(((t - 0.03 - index * 0.045) / 0.46).clamp(0.0, 1.0));

class DialGooPainter extends CustomPainter {
  /// Animation progress 0..1 (already reduced-motion-normalized by the
  /// caller: pass 1.0 for reduced motion).
  final double t;

  /// Top-left of the painting layer in GLOBAL coordinates — all rects
  /// (anchor, slots) are global and are shifted by this before painting.
  final Offset origin;

  final Rect anchor;
  final List<ArcSlot> slots;
  final Color body;
  final Color rim;

  /// Squircle corner radius of the anchor shape (filled mode).
  final double anchorRadius;

  /// Squircle corner radius of every satellite (scaled by launch
  /// progress, exactly like the category dial's pills).
  final double satelliteRadius;

  /// Goo bead chain base radius ([drawNeck]'s baseRadius).
  final double neckBaseRadius;

  /// Anchor inflation at full flight, in px (category: 2.0 — the pill
  /// breathes outward as the fan opens).
  final double anchorInflate;

  /// Paint the anchor as an even-odd ring instead of a filled shape
  /// (profile dial: the avatar photo must stay visible).
  final bool anchorAsRing;

  /// Bead chains start this far from the anchor center (profile dial:
  /// the rim, so goo never covers the photo).
  final double neckStartRadius;

  DialGooPainter({
    required this.t,
    required this.origin,
    required this.anchor,
    required this.slots,
    required this.body,
    required this.rim,
    required this.anchorRadius,
    required this.satelliteRadius,
    required this.neckBaseRadius,
    this.anchorInflate = 2.0,
    this.anchorAsRing = false,
    this.neckStartRadius = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.001) return;
    final flight = (t / 0.45).clamp(0.0, 1.0) *
        (1 - ((t - 0.62) / 0.38).clamp(0.0, 1.0));
    final sigma = kGooBlurRest + (kGooBlurActive - kGooBlurRest) * flight;
    final a = anchor.shift(-origin);

    paintGoo(
      canvas,
      bounds: Offset.zero & size,
      sigma: sigma,
      body: body,
      rim: rim,
      shapes: (c, paint) {
        if (anchorAsRing) {
          // RING: outer silhouette inflated by the flight breathing, inner
          // hole = the avatar itself (deflated 1px so no goo sliver hugs
          // the photo's exact edge). even-odd subtracts the hole.
          final outer = a.inflate(anchorInflate * flight);
          final path = Path()
            ..addOval(outer)
            ..addOval(a.deflate(1.0))
            ..fillType = PathFillType.evenOdd;
          c.drawPath(path, paint);
        } else {
          c.drawRRect(
            RRect.fromRectAndRadius(
              a.inflate(anchorInflate * flight),
              Radius.circular(anchorRadius),
            ),
            paint,
          );
        }
        for (final slot in slots) {
          final s = satelliteScale(t, slot.index);
          final travel = satelliteTravel(t, slot.index);
          if (travel <= 0) continue;
          final target = slot.rect.shift(-origin);
          final centre = Offset.lerp(a.center, target.center, travel)!;
          final r = Rect.fromCenter(
            center: centre,
            width: target.width * s.sx,
            height: target.height * s.sy,
          );
          // Neck chains start at the rim (not the center) when
          // [neckStartRadius] > 0 — the profile photo must never be
          // painted over by goo beads.
          final neckFrom = neckStartRadius <= 0
              ? a.center
              : a.center +
                  (centre - a.center).normalized * neckStartRadius;
          drawNeck(
            c,
            paint,
            from: neckFrom,
            to: centre,
            baseRadius: neckBaseRadius,
            t: (travel * 1.4).clamp(0.0, 1.0),
            tension: flight,
          );
          c.drawPath(squirclePath(r, satelliteRadius * s.sy), paint);
        }
      },
    );
  }

  @override
  bool shouldRepaint(DialGooPainter old) =>
      old.t != t || old.slots != slots || old.anchor != anchor;
}

/// Unit vector of [v] (Offset.zero for a zero-length vector).
extension on Offset {
  Offset get normalized {
    final d = distance;
    if (d < 0.0001) return Offset.zero;
    return this / d;
  }
}
