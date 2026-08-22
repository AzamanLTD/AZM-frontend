// lib/widgets/book/page_geometry.dart
// =============================================================================
// PAGE GEOMETRY — the cylindrical page-curl solver.
//
// This file owns all of the maths and *none* of the painting. Given the page
// rect, the anchored corner and the current touch point it produces a
// perspective-correct triangle strip for both the front and back faces of
// the curling sheet, plus the derived lighting/shadow scalars the painter
// needs.
//
// The fold is modelled as a sheet of paper wrapped around a cylinder of
// radius `r` whose axis is the fold line. In fold-aligned coordinates:
//   u = unit vector from the finger toward the grabbed corner (s > 0 is the
//       folded half)
//   v = fold-line direction
//
// For a point at signed distance `s` from the fold:
//   s <= 0      flat on the book       u' = s              z = 0
//   0 < s <= πr on the cylinder        u' = r·sin(s/r)    z = r·(1 − cos(s/r))
//   s > πr      folded back, face-down  u' = −(s − πr)    z = 2r
//
// The fold line is the perpendicular bisector of (anchor corner → touch).
//
// Why a *strip* and not a grid: curvature only exists along u; along v the
// surface is a straight generatrix with constant z — so two vertices per
// slab are geometrically exact. A 2×N strip (N ≈ 28) is pixel-identical to
// a dense N×M grid while producing ~20× fewer vertices.
//
// Everything here is allocation-conscious: the solver reuses its typed-data
// buffers across frames, so a drag produces zero steady-state garbage.
// =============================================================================
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Vertices, VertexMode;

import 'package:flutter/painting.dart';

/// Which physical corner of the leaf the user grabbed.
enum FlipAnchor { topOuter, middleOuter, bottomOuter }

/// Direction of the turn relative to the spine.
enum FlipDirection {
  /// Outer edge on the right; page turns right → left (next page).
  forward,
  /// Outer edge on the left; page turns left → right (previous page).
  backward,
}

/// A solved frame of page-curl geometry.
class CurlGeometry {
  final ui.Vertices? frontFace;
  final ui.Vertices? backFace;
  final Path backOutline;
  final Path frontOutline;
  final Offset crestStart;
  final Offset crestEnd;
  final double liftHeight;
  final double radius;
  final Offset turnDirection;
  final bool hasBackFace;

  const CurlGeometry({
    required this.frontFace,
    required this.backFace,
    required this.backOutline,
    required this.frontOutline,
    required this.crestStart,
    required this.crestEnd,
    required this.liftHeight,
    required this.radius,
    required this.turnDirection,
    required this.hasBackFace,
  });
}

/// Stateless-by-contract, buffer-reusing curl solver.
class PageCurlSolver {
  static const int curvedSlabs = 28;
  static const double cameraDistanceFactor = 2.6;
  static const _lightX = -0.34;
  static const _lightY = -0.55;
  static const _lightZ = 0.76;
  static const double ambient = 0.72;

  Float32List? _fPos, _fTex, _bPos, _bTex;
  Int32List? _fCol, _bCol;

  CurlGeometry solve({
    required Rect pageRect,
    required Offset anchorCorner,
    required Offset touch,
    required Size textureSize,
    double? radiusOverride,
  }) {
    final w = pageRect.width;

    var dx = anchorCorner.dx - touch.dx;
    var dy = anchorCorner.dy - touch.dy;
    var dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.0001) {
      return CurlGeometry(
        frontFace: null,
        backFace: null,
        backOutline: Path(),
        frontOutline: Path()..addRect(pageRect),
        crestStart: Offset.zero,
        crestEnd: Offset.zero,
        liftHeight: 0,
        radius: 0,
        turnDirection: const Offset(-1, 0),
        hasBackFace: false,
      );
    }
    final ux = dx / dist, uy = dy / dist;
    final vx = -uy, vy = ux;

    final mx = (anchorCorner.dx + touch.dx) * 0.5;
    final my = (anchorCorner.dy + touch.dy) * 0.5;

    final maxR = w * 0.17;
    final r = radiusOverride ?? (dist * 0.5 / math.pi).clamp(w * 0.012, maxR).toDouble();

    final corners = <Offset>[
      pageRect.topLeft,
      pageRect.topRight,
      pageRect.bottomRight,
      pageRect.bottomLeft,
    ];
    var sMin = double.infinity, sMax = -double.infinity;
    final cornerS = List<double>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      final s = (c.dx - mx) * ux + (c.dy - my) * uy;
      cornerS[i] = s;
      if (s < sMin) sMin = s;
      if (s > sMax) sMax = s;
    }

    if (sMax <= 0) {
      return CurlGeometry(
        frontFace: null,
        backFace: null,
        backOutline: Path(),
        frontOutline: Path()..addRect(pageRect),
        crestStart: Offset.zero,
        crestEnd: Offset.zero,
        liftHeight: 0,
        radius: r,
        turnDirection: Offset(ux, uy),
        hasBackFace: false,
      );
    }

    final sHalf = math.pi * r * 0.5;
    final sFull = math.pi * r;
    final samples = _buildSamples(sMin, sMax, sHalf, sFull, cornerS);

    final camera = w * cameraDistanceFactor;
    final cx = pageRect.center.dx, cy = pageRect.center.dy;
    final texScaleX = textureSize.width / pageRect.width;
    final texScaleY = textureSize.height / pageRect.height;

    var frontCount = 0, backCount = 0;
    for (final s in samples) {
      if (s <= sHalf) frontCount++;
      if (s >= sHalf) backCount++;
    }

    final fPos = _grow32(_fPos, frontCount * 4);
    final fTex = _grow32(_fTex, frontCount * 4);
    final fCol = _growI32(_fCol, frontCount * 2);
    final bPos = _grow32(_bPos, backCount * 4);
    final bTex = _grow32(_bTex, backCount * 4);
    final bCol = _growI32(_bCol, backCount * 2);
    _fPos = fPos;
    _fTex = fTex;
    _fCol = fCol;
    _bPos = bPos;
    _bTex = bTex;
    _bCol = bCol;

    var fi = 0, bi = 0, fci = 0, bci = 0;
    var maxZ = 0.0;
    Offset crestA = Offset.zero, crestB = Offset.zero;
    var crestFound = false;

    final frontLeft = <Offset>[], frontRight = <Offset>[];
    final backLeft = <Offset>[], backRight = <Offset>[];

    for (final s in samples) {
      final range = _clipRange(pageRect, mx, my, ux, uy, vx, vy, s);
      if (range == null) continue;

      double uOut, z, theta;
      if (s <= 0) {
        uOut = s;
        z = 0;
        theta = 0;
      } else if (s <= sFull) {
        theta = s / r;
        uOut = r * math.sin(theta);
        z = r * (1 - math.cos(theta));
      } else {
        uOut = -(s - sFull);
        z = 2 * r;
        theta = math.pi;
      }

      final bx = mx + ux * uOut;
      final by = my + uy * uOut;

      // Lambert shading
      final nx = -ux * math.sin(theta);
      final ny = -uy * math.sin(theta);
      final nz = math.cos(theta);
      final lambert = (nx * _lightX + ny * _lightY + nz * _lightZ).abs();
      final shade = (ambient + (1 - ambient) * lambert).clamp(0.0, 1.0);
      final colour = (0xFF000000 | (shade * 255).round() << 16 | (shade * 255).round() << 8 | (shade * 255).round());

      for (var e = 0; e <= 1; e++) {
        final t = e == 0 ? range.$1 : range.$2;
        final sx = bx + vx * t;
        final sy = by + vy * t;

        final dx2 = sx - cx, dy2 = sy - cy;
        final persp = camera / (camera + z);
        final px = cx + dx2 * persp;
        final py = cy + dy2 * persp;

        if (z > maxZ) maxZ = z;

        final ox = (sx - pageRect.left);
        final oy = (sy - pageRect.top);
        final tx = ox * texScaleX;
        final ty = oy * texScaleY;

        if (s <= sHalf) {
          fPos[fi] = px;
          fPos[fi + 1] = py;
          fTex[fi] = tx;
          fTex[fi + 1] = ty;
          fi += 2;
          fCol[fci++] = colour;
          (e == 0 ? frontLeft : frontRight).add(Offset(px, py));
        }
        if (s >= sHalf) {
          bPos[bi] = px;
          bPos[bi + 1] = py;
          bTex[bi] = tx;
          bTex[bi + 1] = ty;
          bi += 2;
          bCol[bci++] = colour;
          (e == 0 ? backLeft : backRight).add(Offset(px, py));
        }
        if (!crestFound && s >= sHalf) {
          if (e == 0) {
            crestA = Offset(px, py);
          } else {
            crestB = Offset(px, py);
            crestFound = true;
          }
        }
      }
    }

    final front = fi >= 12
        ? ui.Vertices.raw(
            ui.VertexMode.triangleStrip,
            Float32List.sublistView(fPos, 0, fi),
            textureCoordinates: Float32List.sublistView(fTex, 0, fi),
            colors: Int32List.sublistView(fCol, 0, fci),
          )
        : null;
    final back = bi >= 12
        ? ui.Vertices.raw(
            ui.VertexMode.triangleStrip,
            Float32List.sublistView(bPos, 0, bi),
            textureCoordinates: Float32List.sublistView(bTex, 0, bi),
            colors: Int32List.sublistView(bCol, 0, bci),
          )
        : null;

    return CurlGeometry(
      frontFace: front,
      backFace: back,
      frontOutline: _outline(frontLeft, frontRight),
      backOutline: _outline(backLeft, backRight),
      crestStart: crestA,
      crestEnd: crestB,
      liftHeight: maxZ,
      radius: r,
      turnDirection: Offset(ux, uy),
      hasBackFace: back != null,
    );
  }

  static List<double> _buildSamples(
    double sMin,
    double sMax,
    double sHalf,
    double sFull,
    List<double> cornerS,
  ) {
    final out = <double>[sMin, sMax];
    for (final c in cornerS) {
      if (c > sMin && c < sMax) out.add(c);
    }
    if (sHalf > sMin && sHalf < sMax) out.add(sHalf);
    if (0 > sMin && 0 < sMax) out.add(0);
    if (sFull > sMin && sFull < sMax) out.add(sFull);

    final rollStart = math.max(0.0, sMin);
    final rollEnd = math.min(sFull, sMax);
    if (rollEnd > rollStart) {
      final step = (rollEnd - rollStart) / curvedSlabs;
      for (var i = 1; i < curvedSlabs; i++) {
        out.add(rollStart + step * i);
      }
    }
    out.sort();
    final dedup = <double>[out.first];
    for (var i = 1; i < out.length; i++) {
      if (out[i] - dedup.last > 0.001) dedup.add(out[i]);
    }
    return dedup;
  }

  static (double, double)? _clipRange(
    Rect rect,
    double mx,
    double my,
    double ux,
    double uy,
    double vx,
    double vy,
    double s,
  ) {
    final bx = mx + ux * s, by = my + uy * s;
    var tMin = -double.maxFinite, tMax = double.maxFinite;

    if (vx.abs() < 1e-9) {
      if (bx < rect.left - 0.001 || bx > rect.right + 0.001) return null;
    } else {
      final t1 = (rect.left - bx) / vx;
      final t2 = (rect.right - bx) / vx;
      final lo = math.min(t1, t2), hi = math.max(t1, t2);
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }
    if (vy.abs() < 1e-9) {
      if (by < rect.top - 0.001 || by > rect.bottom + 0.001) return null;
    } else {
      final t1 = (rect.top - by) / vy;
      final t2 = (rect.bottom - by) / vy;
      final lo = math.min(t1, t2), hi = math.max(t1, t2);
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }
    if (tMax - tMin <= 0.001) return null;
    return (tMin, tMax);
  }

  static Path _outline(List<Offset> left, List<Offset> right) {
    final path = Path();
    if (left.isEmpty || right.isEmpty) return path;
    path.moveTo(left.first.dx, left.first.dy);
    for (var i = 1; i < left.length; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }
    for (var i = right.length - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }
    path.close();
    return path;
  }

  static Float32List _grow32(Float32List? buf, int need) =>
      (buf != null && buf.length >= need) ? buf : Float32List(math.max(need, 256));

  static Int32List _growI32(Int32List? buf, int need) =>
      (buf != null && buf.length >= need) ? buf : Int32List(math.max(need, 128));
}

/// Maps normalised progress → the canonical touch point used when the finger
/// is *not* on the screen (settle animations, programmatic turns, idle hints).
class FlipPath {
  const FlipPath._();

  static Offset touchFor({
    required double progress,
    required Size size,
    required double anchorY,
  }) {
    final w = size.width;
    final x = w - 2 * w * progress;
    final lift = math.sin(progress * math.pi) * size.height * 0.055;
    return Offset(x, anchorY - lift);
  }

  static double progressFor({
    required Offset touch,
    required Size size,
  }) {
    final w = size.width;
    return ((w - touch.dx) / (2 * w)).clamp(0.0, 1.0);
  }

  static double anchorCompensation({
    required double progress,
    required Size size,
  }) =>
      math.sin(progress * math.pi) * size.height * 0.055;

  static FlipAnchor anchorForGrab(Offset local, Size size) {
    final ry = local.dy / size.height;
    if (ry < 0.28) return FlipAnchor.topOuter;
    if (ry > 0.72) return FlipAnchor.bottomOuter;
    return FlipAnchor.middleOuter;
  }

  static Offset cornerFor(FlipAnchor anchor, Size size) {
    final x = size.width;
    switch (anchor) {
      case FlipAnchor.topOuter:
        return Offset(x, 0);
      case FlipAnchor.bottomOuter:
        return Offset(x, size.height);
      case FlipAnchor.middleOuter:
        return Offset(x, size.height * 0.5);
    }
  }
}
