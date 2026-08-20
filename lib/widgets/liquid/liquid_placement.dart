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
  final double angle; // radians, for debugging / rotation
  const ArcSlot({required this.index, required this.rect, required this.angle});
}

/// Fans [sizes] into the free quadrant around a trigger. For a leading-edge
/// trigger the sector is UP→OUTWARD (-95°…-8°); pills are anchored by their
/// leading edge so the label always reads outward and never leaves the screen.
List<ArcSlot> solveArc({
  required Rect anchor,
  required List<Size> sizes,
  required LiquidSafeArea safe,
  TextDirection direction = TextDirection.ltr,
  double gap = 8,
}) {
  if (sizes.isEmpty) return const [];
  final n = sizes.length;
  final growRight = _growsRight(anchor, safe, direction);

  const startDeg = -95.0, endDeg = -20.0; // y-up
  final rowPitch = sizes.first.height + gap;

  final dTheta = n > 1 ? ((endDeg - startDeg).abs() * math.pi / 180) / (n - 1) : 0.0;
  var radius = n > 1 ? rowPitch / (2 * math.sin(dTheta / 2)) : rowPitch;
  radius = radius.clamp(anchor.height + gap, 3.2 * rowPitch * n / math.pi + rowPitch);

  final slots = <ArcSlot>[];
  for (var i = 0; i < n; i++) {
    final tt = n == 1 ? 0.5 : i / (n - 1);
    final deg = startDeg + (endDeg - startDeg) * tt;
    final rad = deg * math.pi / 180;
    final dx = math.cos(rad) * radius * (growRight ? 1 : -1);
    final dy = math.sin(rad) * radius; // negative = up
    final size = sizes[i];

    var l = growRight
        ? anchor.center.dx + dx * 0.35 + anchor.width * 0.15
        : anchor.center.dx + dx * 0.35 - anchor.width * 0.15 - size.width;
    var t = anchor.center.dy + dy - size.height / 2;

    // Hard clamp — an option the user cannot read is a bug.
    l = l.clamp(safe.left, math.max(safe.left, safe.right - size.width));
    t = t.clamp(safe.top, math.max(safe.top, safe.bottom - size.height));

    slots.add(ArcSlot(index: i, rect: Rect.fromLTWH(l, t, size.width, size.height), angle: rad));
  }

  // De-overlap pass: push each slot up until it clears the previous one, then
  // re-clamp to the top margin so a tall stack compresses instead of escaping.
  for (var i = 1; i < slots.length; i++) {
    final prev = slots[i - 1].rect, cur = slots[i].rect;
    if (cur.overlaps(prev.inflate(2))) {
      var shifted = cur.translate(0, prev.top - cur.bottom - gap);
      if (shifted.top < safe.top) shifted = shifted.translate(0, safe.top - shifted.top);
      slots[i] = ArcSlot(index: i, rect: shifted, angle: slots[i].angle);
    }
  }
  return slots;
}
