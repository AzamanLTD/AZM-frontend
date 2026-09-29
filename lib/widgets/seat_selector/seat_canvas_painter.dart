// =============================================================================
// AZAMAN — SEAT CANVAS PAINTER
//
// CustomPainter for the seat selector. Draws:
//   1. Vehicle hull/silhouette (windshield curve, door wells, aisle lines) —
//      canvas-drawn since it varies per vehicle layout.
//   2. Seat icons — rendered via pre-decoded SVG Pictures (not live SVG
//      parsing per frame). The Pictures are decoded once and passed in.
//   3. VIP tier badge overlay — drawn procedurally (amber circle + star).
//   4. Selection accent ring — a cheap animated stroke for selected seats.
//
// Performance: all geometry is precomputed by SeatGeometrySolver. This painter
// only reads rects and draws — no computation inside paint().
// =============================================================================

import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'seat_layout_models.dart';
import 'seat_geometry_solver.dart';

/// Decoded SVG pictures for each seat state, cached once.
class SeatIconCache {
  final ui.Picture? available;
  final ui.Picture? selected;
  final ui.Picture? occupied;
  final ui.Picture? blocked;

  const SeatIconCache({
    this.available,
    this.selected,
    this.occupied,
    this.blocked,
  });

  /// Get the picture for a given slot state (considering local selection).
  ui.Picture? pictureFor({
    required GridSlot slot,
    required bool isSelected,
  }) {
    if (!slot.isSeat) { return null; }

    if (slot.status == SeatBookStatus.booked) { return occupied; }
    if (slot.status == SeatBookStatus.blocked ||
        slot.status == SeatBookStatus.reserved) { return blocked; }

    // Available: check if locally selected
    if (isSelected) { return selected; }
    return available;
  }
}

/// Configuration for the vehicle hull rendering.
class HullStyle {
  final Color bodyColor;
  final Color borderColor;
  final double borderRadius;
  final double borderWidth;

  const HullStyle({
    required this.bodyColor,
    required this.borderColor,
    this.borderRadius = 28,
    this.borderWidth = 1.5,
  });
}

/// Cabin lighting overlay — §7.3 "lit cabin": an aisle-centred light pool,
/// end vignettes, a bloom behind selected seats and co-passenger dots on
/// booked seats. Purely additive: when [SeatCanvasPainter.cabinLighting] is
/// null the painter renders byte-identically to the legacy behaviour.
class CabinLighting {
  /// 0.0 = off, 1.0 = full strength. All derived alphas scale by this.
  final double intensity;

  const CabinLighting({this.intensity = 1.0});
}

/// The painter — takes precomputed geometry + cached icons + selection state.
class SeatCanvasPainter extends CustomPainter {
  final ComputedGeometry geometry;
  final SeatIconCache iconCache;
  final Set<String> selectedSeats;
  final HullStyle hullStyle;
  final Color accentColor;
  final Color vipBadgeColor;

  /// Cabin lighting overlay; null = legacy rendering (byte-identical).
  final CabinLighting? cabinLighting;

  /// Pulse value for the selected-seat ring animation (0.0–1.0).
  /// Driven by an AnimationController in the parent, passed via repaint.
  final double selectionPulse;

  /// Current deck to render (only draws seats from this deck).
  final int currentDeck;

  SeatCanvasPainter({
    required this.geometry,
    required this.iconCache,
    required this.selectedSeats,
    required this.hullStyle,
    required this.accentColor,
    this.vipBadgeColor = const Color(0xFFF59E0B),
    this.cabinLighting,
    this.selectionPulse = 0.0,
    this.currentDeck = 0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Draw vehicle hull ──────────────────────────────────────────
    _drawHull(canvas, size);

    // ── 1b. Cabin lighting (optional overlay) ──────────────────────────
    if (cabinLighting != null) {
      _drawCabinLighting(canvas, size);
    }

    // ── 2. Draw deck separator if multi-deck ──────────────────────────
    if (geometry.layout.isMultiDeck) {
      _drawDeckSeparator(canvas, size);
    }

    // ── 3. Draw seats for the current deck ────────────────────────────
    final deckRects = geometry.deckRects[currentDeck] ?? [];

    for (final slotRect in deckRects) {
      if (!slotRect.slot.isSeat) continue;

      final isSelected = selectedSeats.contains(slotRect.slot.seatId);

      // ── Selection bloom (cabin lighting only) ────────────────────────
      if (cabinLighting != null && isSelected) {
        _drawSelectionBloom(canvas, slotRect.visualRect);
      }

      // Draw seat icon
      final picture = iconCache.pictureFor(
        slot: slotRect.slot,
        isSelected: isSelected,
      );

      if (picture != null) {
        canvas.save();
        canvas.translate(slotRect.visualRect.left, slotRect.visualRect.top);
        canvas.drawPicture(picture);
        canvas.restore();
      } else {
        // Fallback: draw a simple rect if icon not yet decoded
        _drawFallbackSeat(canvas, slotRect.visualRect, slotRect.slot, isSelected);
      }

      // ── VIP badge overlay (top-left corner) ──────────────────────────
      if (slotRect.slot.tier == SeatTier.vip) {
        _drawVipBadge(canvas, slotRect.visualRect);
      }

      // ── Co-passenger dot (cabin lighting only, booked seats) ─────────
      final seatId = slotRect.slot.seatId;
      if (cabinLighting != null &&
          seatId != null &&
          slotRect.slot.status == SeatBookStatus.booked) {
        _drawAvatarDot(canvas, slotRect.visualRect, seatId);
      }

      // ── Selection accent ring ───────────────────────────────────────
      if (isSelected) {
        _drawSelectionRing(canvas, slotRect.visualRect);
      }

      // ── Seat label (seat number) ────────────────────────────────────
      if (slotRect.slot.seatLabel != null) {
        _drawSeatLabel(canvas, slotRect.visualRect, slotRect.slot, isSelected);
      }
    }
  }

  void _drawSeatLabel(Canvas canvas, Rect seatRect, GridSlot slot, bool isSelected) {
    // Choose text color that contrasts with the seat fill
    final Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (slot.status == SeatBookStatus.booked ||
        slot.status == SeatBookStatus.blocked ||
        slot.status == SeatBookStatus.reserved) {
      textColor = Colors.white;
    } else {
      textColor = Colors.black54;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: slot.seatLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        seatRect.center.dx - tp.width / 2,
        seatRect.center.dy - tp.height / 2,
      ),
    );
    tp.dispose();
  }

  void _drawHull(Canvas canvas, Size size) {
    final bounds = geometry.totalBounds;

    final paint = Paint()
      ..color = hullStyle.bodyColor
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(hullStyle.borderRadius),
    );

    canvas.drawRRect(rrect, paint);

    final borderPaint = Paint()
      ..color = hullStyle.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = hullStyle.borderWidth;

    canvas.drawRRect(rrect, borderPaint);

    // Windshield / front-of-vehicle header
    final headerRect = Rect.fromLTRB(
      bounds.left + 20,
      bounds.top + 20,
      bounds.right - 20,
      bounds.top + 20 + 40,
    );
    final headerPaint = Paint()
      ..color = hullStyle.borderColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final headerRRect = RRect.fromRectAndRadius(
      headerRect,
      const Radius.circular(16),
    );
    canvas.drawRRect(headerRRect, headerPaint);
  }

  void _drawDeckSeparator(Canvas canvas, Size size) {
    // Draw a thin dashed line between decks
    for (int i = 0; i < geometry.layout.decks.length - 1; i++) {
      final bounds = geometry.deckBounds[i];
      if (bounds == null) continue;

      final y = bounds.bottom + 12;
      final paint = Paint()
        ..color = hullStyle.borderColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      // Simple dashed line
      const dashWidth = 8.0;
      const dashGap = 6.0;
      double x = geometry.totalBounds.left + 20;
      while (x < geometry.totalBounds.right - 20) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + dashWidth, y),
          paint,
        );
        x += dashWidth + dashGap;
      }
    }
  }

  void _drawVipBadge(Canvas canvas, Rect seatRect) {
    const badgeSize = 18.0;
    final center = Offset(seatRect.left + badgeSize / 2 + 2, seatRect.top + badgeSize / 2 + 2);
    const radius = badgeSize / 2;

    // Amber circle background
    final circlePaint = Paint()
      ..color = vipBadgeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    // 5-point star inside the circle
    final starPath = ui.Path();
    const starRadius = radius * 0.6;
    const innerRadius = starRadius * 0.4;
    for (int i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2 + i * 2 * math.pi / 5;
      final innerAngle = outerAngle + math.pi / 5;
      final outerPoint = Offset(
        center.dx + starRadius * math.cos(outerAngle),
        center.dy + starRadius * math.sin(outerAngle),
      );
      final innerPoint = Offset(
        center.dx + innerRadius * math.cos(innerAngle),
        center.dy + innerRadius * math.sin(innerAngle),
      );
      if (i == 0) {
        starPath.moveTo(outerPoint.dx, outerPoint.dy);
      } else {
        starPath.lineTo(outerPoint.dx, outerPoint.dy);
      }
      starPath.lineTo(innerPoint.dx, innerPoint.dy);
    }
    starPath.close();

    final starPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(starPath, starPaint);
  }

  void _drawSelectionRing(Canvas canvas, Rect seatRect) {
    // Pulsing accent ring around the selected seat
    final pulseScale = 1.0 + 0.08 * selectionPulse;
    final expanded = Rect.fromCenter(
      center: seatRect.center,
      width: seatRect.width * pulseScale + 4,
      height: seatRect.height * pulseScale + 4,
    );

    final ringPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3 + 0.2 * selectionPulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + selectionPulse;

    canvas.drawRRect(
      RRect.fromRectAndRadius(expanded, const Radius.circular(12)),
      ringPaint,
    );
  }

  void _drawCabinLighting(Canvas canvas, Size size) {
    final bounds = geometry.totalBounds;
    final light = cabinLighting!;
    if (light.intensity <= 0) return;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      bounds,
      Radius.circular(hullStyle.borderRadius),
    ));

    // Aisle-centred light pool — the aisle is the vehicle's horizontal
    // centre, so a radial pool centred on the hull middle reads as cabin
    // light regardless of the layout's column geometry.
    final center = bounds.center;
    final radius = math.max(bounds.width, bounds.height) * 0.55;
    final lightPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          const Color(0xFFFFFFFF).withValues(alpha: 0.10 * light.intensity),
          const Color(0xFFFFFFFF).withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(bounds, lightPaint);

    // End vignettes — the cabin darkens toward the windshield and rear.
    final vignetteWidth = bounds.width * 0.22;
    final frontPaint = Paint()
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.topLeft + Offset(vignetteWidth, 0),
        [
          const Color(0xFF000000).withValues(alpha: 0.12 * light.intensity),
          const Color(0xFF000000).withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(
      Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.left + vignetteWidth,
        bounds.bottom,
      ),
      frontPaint,
    );

    final rearPaint = Paint()
      ..shader = ui.Gradient.linear(
        bounds.topRight,
        bounds.topRight - Offset(vignetteWidth, 0),
        [
          const Color(0xFF000000).withValues(alpha: 0.12 * light.intensity),
          const Color(0xFF000000).withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(
      Rect.fromLTRB(
        bounds.right - vignetteWidth,
        bounds.top,
        bounds.right,
        bounds.bottom,
      ),
      rearPaint,
    );

    canvas.restore();
  }

  void _drawSelectionBloom(Canvas canvas, Rect seatRect) {
    final bloom = Paint()
      ..color = accentColor.withValues(alpha: 0.16 * cabinLighting!.intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(seatRect.center, seatRect.width * 0.85, bloom);
  }

  /// Deterministic decorative co-passenger dot on booked seats. The booking
  /// model carries no occupant data (see Findings F-043), so the position
  /// varies by a stable hash of the seat id — never by frame randomness.
  void _drawAvatarDot(Canvas canvas, Rect seatRect, String seatId) {
    final hash = seatId.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final slot = hash % 3; // bottom-left, bottom-centre, bottom-right
    final dx = seatRect.left + 5 + slot * (seatRect.width - 10) / 2;
    final dy = seatRect.bottom - 5;

    final dot = Paint()..color = const Color(0xB3FFFFFF);
    canvas.drawCircle(Offset(dx, dy), 3.2, dot);

    final rim = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(dx, dy), 3.2, rim);
  }

  void _drawFallbackSeat(Canvas canvas, Rect rect, GridSlot slot, bool isSelected) {
    // Simple colored rect fallback when SVG picture isn't decoded yet
    Color color;
    if (slot.status == SeatBookStatus.booked) {
      color = Colors.red.shade300;
    } else if (slot.status == SeatBookStatus.blocked ||
        slot.status == SeatBookStatus.reserved) {
      color = Colors.red.shade800;
    } else if (isSelected) {
      color = accentColor;
    } else {
      color = Colors.grey.shade200;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(SeatCanvasPainter oldDelegate) {
    return oldDelegate.selectedSeats != selectedSeats ||
        oldDelegate.selectionPulse != selectionPulse ||
        oldDelegate.currentDeck != currentDeck ||
        oldDelegate.geometry != geometry ||
        oldDelegate.cabinLighting != cabinLighting;
  }
}

/// Separate lightweight painter for the minimap — renders simplified
/// state-colored dots, not full seat icons or hull detail.
class SeatMinimapPainter extends CustomPainter {
  final ComputedGeometry geometry;
  final Set<String> selectedSeats;
  final Color availableColor;
  final Color selectedColor;
  final Color bookedColor;
  final Color blockedColor;
  final Rect viewportIndicator;
  final int currentDeck;

  SeatMinimapPainter({
    required this.geometry,
    required this.selectedSeats,
    required this.availableColor,
    required this.selectedColor,
    required this.bookedColor,
    required this.blockedColor,
    this.viewportIndicator = Rect.zero,
    this.currentDeck = 0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = geometry.totalBounds;
    if (bounds.isEmpty) return;

    // Scale to fit minimap size
    final scaleX = size.width / bounds.width;
    final scaleY = size.height / bounds.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final deckRects = geometry.deckRects[currentDeck] ?? [];

    for (final slotRect in deckRects) {
      if (!slotRect.slot.isSeat) continue;

      final isSelected = selectedSeats.contains(slotRect.slot.seatId);
      final status = slotRect.slot.status;

      Color color;
      if (isSelected) {
        color = selectedColor;
      } else if (status == SeatBookStatus.booked) {
        color = bookedColor;
      } else if (status == SeatBookStatus.blocked ||
          status == SeatBookStatus.reserved) {
        color = blockedColor;
      } else {
        color = availableColor;
      }

      // Scale the seat rect to minimap coordinates
      final dotRect = Rect.fromLTWH(
        (slotRect.visualRect.left - bounds.left) * scale,
        (slotRect.visualRect.top - bounds.top) * scale,
        math.max(slotRect.visualRect.width * scale, 2),
        math.max(slotRect.visualRect.height * scale, 2),
      );

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(dotRect, const Radius.circular(2)),
        paint,
      );
    }

    // Viewport indicator rectangle
    if (viewportIndicator != Rect.zero) {
      final indicatorRect = Rect.fromLTWH(
        (viewportIndicator.left - bounds.left) * scale,
        (viewportIndicator.top - bounds.top) * scale,
        viewportIndicator.width * scale,
        viewportIndicator.height * scale,
      );

      final indicatorPaint = Paint()
        ..color = selectedColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(indicatorRect, indicatorPaint);
    }
  }

  @override
  bool shouldRepaint(SeatMinimapPainter oldDelegate) {
    return oldDelegate.selectedSeats != selectedSeats ||
        oldDelegate.viewportIndicator != viewportIndicator ||
        oldDelegate.currentDeck != currentDeck;
  }
}
