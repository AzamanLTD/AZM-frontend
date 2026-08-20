import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class LiquidSafeArea {
  final Size screen;
  final EdgeInsets padding;
  final double margin;
  const LiquidSafeArea({required this.screen, required this.padding, this.margin = 12});

  double get left => padding.left + margin;
  double get right => screen.width - padding.right - margin;
  double get top => padding.top + margin;
  double get bottom => screen.height - padding.bottom - margin;
}

/// True when the menu should grow towards increasing x.
/// LTR: grow right from a left-anchored trigger. RTL: mirror it.
bool _growsRight(Rect anchor, LiquidSafeArea safe, TextDirection dir) {
  final nearLeftEdge = anchor.center.dx <= safe.screen.width / 2;
  // The physical edge always wins — an off-screen option is a bug, not a style.
  if (anchor.center.dx < safe.left + 96) return true;
  if (anchor.center.dx > safe.right - 96) return false;
  return dir == TextDirection.rtl ? !nearLeftEdge : nearLeftEdge;
}

class PanelPlacement {
  final Rect rect;      // final panel rect, global
  final Offset origin;  // scale origin (trigger centre) in panel-local coords
  final bool above;
  const PanelPlacement({required this.rect, required this.origin, required this.above});

  /// Offset from the anchor's top-left to the panel's top-left.
  /// Feed this to CompositedTransformFollower so the panel tracks the trigger.
  Offset followerOffset(Rect anchor) => rect.topLeft - anchor.topLeft;
}

PanelPlacement solvePanel({
  required Rect anchor,
  required Size panel,
  required LiquidSafeArea safe,
  TextDirection direction = TextDirection.ltr,
  double gap = 14,
}) {
  final maxW = safe.right - safe.left;
  final w = math.min(panel.width, maxW);

  final growRight = _growsRight(anchor, safe, direction);
  var left = growRight ? anchor.left : anchor.right - w;
  left = left.clamp(safe.left, math.max(safe.left, safe.right - w));

  final spaceAbove = anchor.top - gap - safe.top;
  final spaceBelow = safe.bottom - anchor.bottom - gap;
  final above = spaceAbove >= panel.height || spaceAbove >= spaceBelow;
  final h = math.min(panel.height, math.max(above ? spaceAbove : spaceBelow, 120.0));
  final top = above ? anchor.top - gap - h : anchor.bottom + gap;

  final rect = Rect.fromLTWH(left, top, w, h);
  return PanelPlacement(
    rect: rect,
    origin: anchor.center - rect.topLeft, // ooze out of the button
    above: above,
  );
}

class ArcSlot {
  final int index;
  final Rect rect;    // final pill rect, global
  final double angle; // radians from the horizontal-outward axis
  const ArcSlot({required this.index, required this.rect, required this.angle});
}

/// Fans [sizes] into a compact quarter-circle arc that opens toward whichever
/// horizontal side has room (mirrored for RTL) and whichever vertical side
/// (up/down) has more room.
///
/// Per-pair chord distances (not a single global "biggest pill" bound) keep
/// short labels closer together than long ones. If the natural sweep would
/// exceed the aesthetic cap, the radius grows to compress — but only until
/// the screen edge is reached. If pills STILL can't all fit on one ring, a
/// de-overlap pass pushes offenders apart along the arc, then a final
/// safe-area clamp catches any stragglers.
List<ArcSlot> solveArc({
  required Rect anchor,
  required List<Size> sizes,
  required LiquidSafeArea safe,
  TextDirection direction = TextDirection.ltr,
  double gap = 8,
  double maxSweepDeg = 88,
}) {
  if (sizes.isEmpty) return const [];
  final n = sizes.length;
  final growRight = _growsRight(anchor, safe, direction);
  final hSign = growRight ? 1.0 : -1.0;

  final spaceUp = anchor.top - safe.top;
  final spaceDown = safe.bottom - anchor.bottom;
  final growUp = spaceUp >= spaceDown;
  final vSign = growUp ? -1.0 : 1.0;
  final maxSweep = maxSweepDeg * math.pi / 180;

  // Half-diagonal of each pill (for chord math).
  final halfDiags = sizes
      .map((s) => math.sqrt(s.width * s.width + s.height * s.height) / 2)
      .toList();

  // Chord needed between adjacent pills i and i+1.
  double chordBetween(int i, int j) => halfDiags[i] + halfDiags[j] + gap;

  // Max radius before pill i at angle rad would cross a safe-area edge.
  double maxRadiusAt(int i, double rad) {
    final pw = sizes[i].width / 2, ph = sizes[i].height / 2;
    final dx = math.cos(rad) * hSign;
    final dy = math.sin(rad) * vSign;
    var r = double.infinity;
    if (dx > 1e-6) {
      r = math.min(r, (safe.right - pw - anchor.center.dx) / dx);
    } else if (dx < -1e-6) {
      r = math.min(r, (anchor.center.dx - pw - safe.left) / -dx);
    }
    if (dy > 1e-6) {
      r = math.min(r, (safe.bottom - ph - anchor.center.dy) / dy);
    } else if (dy < -1e-6) {
      r = math.min(r, (anchor.center.dy - ph - safe.top) / -dy);
    }
    return math.max(r, 0);
  }

  // Min radius so pill i at angle rad clears the trigger rectangle.
  double anchorClearance(int i, double rad) {
    final pw = sizes[i].width / 2, ph = sizes[i].height / 2;
    return (anchor.width / 2 + pw) * math.cos(rad).abs() +
        (anchor.height / 2 + ph) * math.sin(rad).abs() +
        gap;
  }

  double angleForChord(double r, double chord) =>
      2 * math.asin((chord / (2 * math.max(r, 1.0))).clamp(0.0, 1.0));

  // --- Step 1: find the smallest radius where every pill fits on one arc
  // within the sweep cap AND the screen edges AND clears the trigger. ---

  double minRadiusForClearance() {
    var r = 0.0;
    for (var i = 0; i < n; i++) {
      // At angle 0 (horizontal), clearance is max for wide anchors.
      r = math.max(r, anchorClearance(i, 0));
    }
    return r;
  }

  // Cumulative angles starting from offset, using per-pair chord at radius r.
  List<double> computeAngles(double r, double offset) {
    final rads = <double>[offset];
    for (var i = 1; i < n; i++) {
      rads.add(rads[i - 1] + angleForChord(r, chordBetween(i - 1, i)));
    }
    return rads;
  }

  bool allFit(double r, double offset) {
    if (r < 0) return false;
    final rads = computeAngles(r, offset);
    if (rads.last > maxSweep + 1e-6) return false;
    for (var i = 0; i < n; i++) {
      if (r > maxRadiusAt(i, rads[i]) + 1e-3) return false;
      if (r < anchorClearance(i, rads[i]) - 1e-3) return false;
    }
    return true;
  }

  // Try offsets from 0 (compact) to maxSweep (fully leaning into the side).
  // For each offset, scan radii from small to large.
  double? solveRadius() {
    final rMin = minRadiusForClearance();
    final rMax = math.max(rMin, math.max(safe.screen.width, safe.screen.height));
    const samples = 300;
    for (final offsetDeg in [0.0, 12.0, 24.0, 36.0, 48.0, 60.0, 72.0, maxSweepDeg]) {
      final offset = offsetDeg * math.pi / 180;
      if (offset > maxSweep + 1e-6) continue;
      for (var k = 0; k <= samples; k++) {
        final r = rMin + (rMax - rMin) * k / samples;
        if (allFit(r, offset)) return r;
      }
    }
    return null;
  }

  final foundR = solveRadius();

  List<ArcSlot> buildSlots(double r, double offset) {
    final rads = computeAngles(r, offset);
    final slots = <ArcSlot>[];
    for (var i = 0; i < n; i++) {
      final rad = rads[i];
      var rect = Rect.fromCenter(
        center: anchor.center.translate(
          math.cos(rad) * hSign * r,
          math.sin(rad) * vSign * r,
        ),
        width: sizes[i].width,
        height: sizes[i].height,
      );
      // Safety clamp.
      if (rect.left < safe.left) rect = rect.shift(Offset(safe.left - rect.left, 0));
      if (rect.right > safe.right) rect = rect.shift(Offset(safe.right - rect.right, 0));
      if (rect.top < safe.top) rect = rect.shift(Offset(0, safe.top - rect.top));
      if (rect.bottom > safe.bottom) rect = rect.shift(Offset(0, safe.bottom - rect.bottom));
      slots.add(ArcSlot(index: i, rect: rect, angle: rad));
    }
    return slots;
  }

  if (foundR != null) {
    // Determine which offset worked.
    for (final offsetDeg in [0.0, 12.0, 24.0, 36.0, 48.0, 60.0, 72.0, maxSweepDeg]) {
      final offset = offsetDeg * math.pi / 180;
      if (offset > maxSweep + 1e-6) continue;
      if (allFit(foundR, offset)) {
        return buildSlots(foundR, offset);
      }
    }
  }

  // --- Step 2: fallback — place at the best offset we can, with a de-overlap
  // pass. Use the offset that maximizes the number of pills that fit before
  // exceeding maxSweep, then push the rest down the arc. ---

  // Pick offset=0 and the largest radius that fits the most pills.
  final rFallback = minRadiusForClearance().clamp(1.0, double.infinity);
  var bestOffset = 0.0;
  var bestFitCount = 0;
  for (final offsetDeg in [0.0, 24.0, 48.0, 72.0]) {
    final offset = offsetDeg * math.pi / 180;
    final rads = computeAngles(rFallback, offset);
    var fitCount = 0;
    for (var i = 0; i < n; i++) {
      if (rads[i] > maxSweep + 1e-6) break;
      if (rFallback > maxRadiusAt(i, rads[i]) + 1e-3) break;
      if (rFallback < anchorClearance(i, rads[i]) - 1e-3) break;
      fitCount = i + 1;
    }
    if (fitCount > bestFitCount) {
      bestFitCount = fitCount;
      bestOffset = offset;
    }
  }

  // Build slots at fallback radius/offset, clamping angles to maxSweep.
  var rads = computeAngles(rFallback, bestOffset);
  // Clamp any angles exceeding maxSweep, spaced by the minimum step at this radius.
  final minStep = n > 1
      ? angleForChord(rFallback, halfDiags.fold<double>(0, math.max) * 2 + gap)
      : 0.0;
  for (var i = 1; i < n; i++) {
    if (rads[i] > maxSweep) rads[i] = math.min(maxSweep, rads[i - 1] + minStep);
  }

  var slots = <ArcSlot>[];
  for (var i = 0; i < n; i++) {
    final rad = rads[i];
    var rect = Rect.fromCenter(
      center: anchor.center.translate(
        math.cos(rad) * hSign * rFallback,
        math.sin(rad) * vSign * rFallback,
      ),
      width: sizes[i].width,
      height: sizes[i].height,
    );
    if (rect.left < safe.left) rect = rect.shift(Offset(safe.left - rect.left, 0));
    if (rect.right > safe.right) rect = rect.shift(Offset(safe.right - rect.right, 0));
    if (rect.top < safe.top) rect = rect.shift(Offset(0, safe.top - rect.top));
    if (rect.bottom > safe.bottom) rect = rect.shift(Offset(0, safe.bottom - rect.bottom));
    slots.add(ArcSlot(index: i, rect: rect, angle: rad));
  }

  // De-overlap pass: for each slot that overlaps a predecessor, first try
  // pushing it further along the arc (increase angle). If the angle hits
  // maxSweep and it STILL overlaps, push it radially outward (increase
  // radius) — this is effectively a mini "second ring" for stragglers
  // that the single-arc sweep couldn't separate.
  for (var i = 1; i < slots.length; i++) {
    final prev = slots[i - 1].rect;
    var cur = slots[i].rect;
    if (!cur.overlaps(prev.deflate(1))) continue;

    var rad = rads[i];
    var r = rFallback;
    var resolved = false;

    // Phase 1: push along the arc.
    for (var extra = 0.02; extra <= maxSweep; extra += 0.02) {
      final newRad = math.min(rad + extra, maxSweep);
      var newRect = Rect.fromCenter(
        center: anchor.center.translate(
          math.cos(newRad) * hSign * r,
          math.sin(newRad) * vSign * r,
        ),
        width: sizes[i].width,
        height: sizes[i].height,
      );
      if (newRect.left < safe.left) newRect = newRect.shift(Offset(safe.left - newRect.left, 0));
      if (newRect.right > safe.right) newRect = newRect.shift(Offset(safe.right - newRect.right, 0));
      if (newRect.top < safe.top) newRect = newRect.shift(Offset(0, safe.top - newRect.top));
      if (newRect.bottom > safe.bottom) newRect = newRect.shift(Offset(0, safe.bottom - newRect.bottom));
      if (!newRect.overlaps(prev.deflate(1))) {
        rad = newRad;
        cur = newRect;
        resolved = true;
        break;
      }
      if (newRad >= maxSweep) break;
    }

    // Phase 2: push radially outward (only if angular push failed).
    if (!resolved) {
      for (var dr = 4.0; dr < safe.screen.longestSide; dr += 4.0) {
        final newR = r + dr;
        var newRect = Rect.fromCenter(
          center: anchor.center.translate(
            math.cos(rad) * hSign * newR,
            math.sin(rad) * vSign * newR,
          ),
          width: sizes[i].width,
          height: sizes[i].height,
        );
        if (newRect.left < safe.left) newRect = newRect.shift(Offset(safe.left - newRect.left, 0));
        if (newRect.right > safe.right) newRect = newRect.shift(Offset(safe.right - newRect.right, 0));
        if (newRect.top < safe.top) newRect = newRect.shift(Offset(0, safe.top - newRect.top));
        if (newRect.bottom > safe.bottom) newRect = newRect.shift(Offset(0, safe.bottom - newRect.bottom));
        // Check against ALL prior slots, not just the immediately previous one.
        var overlapsAny = false;
        for (var j = 0; j < i; j++) {
          if (newRect.overlaps(slots[j].rect.deflate(1))) { overlapsAny = true; break; }
        }
        if (!overlapsAny) {
          r = newR;
          cur = newRect;
          resolved = true;
          break;
        }
      }
    }

    rads[i] = rad;
    slots[i] = ArcSlot(index: i, rect: cur, angle: rad);

    // If still not resolved (extremely tight screen), leave it — the safety
    // clamp at least keeps it on-screen.
  }

  return slots;
}
