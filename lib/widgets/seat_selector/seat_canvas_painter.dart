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
  ui.Picture? pictureFor({required GridSlot slot, required bool isSelected}) {
    if (!slot.isSeat) {
      return null;
    }

    if (slot.status == SeatBookStatus.booked) {
      return occupied;
    }
    if (slot.status == SeatBookStatus.blocked ||
        slot.status == SeatBookStatus.reserved) {
      return blocked;
    }

    // Available: check if locally selected
    if (isSelected) {
      return selected;
    }
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

/// Colours for the drawn vehicle (the top-down renderer). Built from the
/// app's theme colours by [SeatPalette.fromTheme]; nothing here is fixed to
/// light or dark.
class SeatPalette {
  /// Cabin floor (the vehicle body).
  final Color body;

  /// Hull outline, dashboard and bulkhead lines.
  final Color hull;

  /// Windshield and rear window.
  final Color glass;

  /// An open seat: cushion, backrest, outline and number.
  final Color seat;
  final Color seatBack;
  final Color seatEdge;
  final Color seatInk;

  /// A taken seat.
  final Color taken;
  final Color takenBack;
  final Color takenInk;

  /// The driver's and the mate's seats.
  final Color crew;
  final Color crewBack;
  final Color crewInk;

  /// Your seat, and the door.
  final Color accent;
  final Color accentBack;
  final Color onAccent;

  final Color vip;

  /// "Driver", "Mate", "Door".
  final Color caption;

  /// Tail lights.
  final Color tail;

  const SeatPalette({
    required this.body,
    required this.hull,
    required this.glass,
    required this.seat,
    required this.seatBack,
    required this.seatEdge,
    required this.seatInk,
    required this.taken,
    required this.takenBack,
    required this.takenInk,
    required this.crew,
    required this.crewBack,
    required this.crewInk,
    required this.accent,
    required this.accentBack,
    required this.onAccent,
    required this.vip,
    required this.caption,
    required this.tail,
  });

  factory SeatPalette.fromTheme({
    required Color accent,
    required Color surface,
    required Color divider,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color background,
    required Color danger,
  }) {
    final dark = background.computeLuminance() < 0.25;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    final body = dark
        ? Color.lerp(surface, white, 0.035)!
        : Color.lerp(surface, white, 0.6)!;
    final seat = dark
        ? Color.lerp(surface, white, 0.13)!
        : Color.lerp(background, black, 0.035)!;
    final taken = dark
        ? Color.lerp(surface, black, 0.28)!
        : Color.lerp(divider, textTertiary, 0.55)!;
    final crew = dark ? Color.lerp(textPrimary, surface, 0.18)! : textPrimary;
    return SeatPalette(
      body: body,
      hull: dark
          ? Color.lerp(divider, white, 0.10)!
          : Color.lerp(divider, textTertiary, 0.35)!,
      glass: Color.lerp(accent, body, dark ? 0.72 : 0.80)!,
      seat: seat,
      seatBack: Color.lerp(seat, textTertiary, dark ? 0.30 : 0.26)!,
      seatEdge: Color.lerp(seat, textTertiary, dark ? 0.42 : 0.40)!,
      seatInk: textSecondary,
      taken: taken,
      takenBack: Color.lerp(taken, black, dark ? 0.25 : 0.12)!,
      takenInk: dark ? textTertiary : Color.lerp(taken, white, 0.78)!,
      crew: crew,
      crewBack: Color.lerp(crew, dark ? black : black, 0.22)!,
      crewInk: dark ? background : white,
      accent: accent,
      accentBack: Color.lerp(accent, black, 0.24)!,
      onAccent: accent.computeLuminance() > 0.5 ? black : white,
      vip: const Color(0xFFF59E0B),
      caption: textTertiary,
      tail: danger,
    );
  }
}

/// How one seat glyph is drawn.
enum SeatLook { open, mine, taken, notForSale, crew }

/// Draws one top-down, forward-facing seat (cushion, armrests, backrest)
/// into [rect]. Shared by the vehicle and its legend so they always match.
void paintSeatGlyph(
  Canvas canvas,
  Rect rect,
  SeatPalette p,
  SeatLook look, {
  String? label,
  bool vip = false,
  String? fontFamily,
}) {
  final w = rect.width;
  final h = rect.height;
  final (Color cushion, Color back, Color ink) = switch (look) {
    SeatLook.open => (p.seat, p.seatBack, p.seatInk),
    SeatLook.mine => (p.accent, p.accentBack, p.onAccent),
    SeatLook.taken => (p.taken, p.takenBack, p.takenInk),
    SeatLook.notForSale => (p.body, p.seatBack, p.caption),
    SeatLook.crew => (p.crew, p.crewBack, p.crewInk),
  };

  final arm = w * 0.11;
  RRect armRect(double left) => RRect.fromRectAndRadius(
    Rect.fromLTWH(left, rect.top + h * 0.26, arm, h * 0.62),
    Radius.circular(arm / 2),
  );
  final cushionRect = RRect.fromRectAndCorners(
    Rect.fromLTRB(
      rect.left + arm + w * 0.03,
      rect.top + h * 0.06,
      rect.right - arm - w * 0.03,
      rect.bottom - h * 0.20,
    ),
    topLeft: Radius.circular(w * 0.24),
    topRight: Radius.circular(w * 0.24),
    bottomLeft: Radius.circular(w * 0.10),
    bottomRight: Radius.circular(w * 0.10),
  );
  final backRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(
      rect.left + w * 0.06,
      rect.bottom - h * 0.27,
      rect.right - w * 0.06,
      rect.bottom,
    ),
    Radius.circular(h * 0.11),
  );

  final fill = Paint()..style = PaintingStyle.fill;
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, w * 0.022)
    ..color = look == SeatLook.open ? p.seatEdge : back;

  // Armrests and backrest sit under the cushion.
  fill.color = back;
  canvas.drawRRect(armRect(rect.left), fill);
  canvas.drawRRect(armRect(rect.right - arm), fill);
  canvas.drawRRect(backRect, fill);

  if (look == SeatLook.notForSale) {
    // An outline with a single stroke through it: there, but not sold.
    canvas.drawRRect(cushionRect, Paint()..color = p.body);
    final dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.03)
      ..color = p.seatEdge;
    canvas.drawRRect(cushionRect, dashed);
    final c = cushionRect.outerRect;
    canvas.drawLine(
      Offset(c.left + c.width * 0.28, c.bottom - c.height * 0.28),
      Offset(c.right - c.width * 0.28, c.top + c.height * 0.28),
      dashed..strokeCap = StrokeCap.round,
    );
  } else {
    fill.color = cushion;
    canvas.drawRRect(cushionRect, fill);
    canvas.drawRRect(cushionRect, edge);
  }

  if (vip && look != SeatLook.taken) {
    // A gold crown line along the cushion's front edge.
    final c = cushionRect.outerRect;
    canvas.drawLine(
      Offset(c.left + c.width * 0.26, c.top + h * 0.035),
      Offset(c.right - c.width * 0.26, c.top + h * 0.035),
      Paint()
        ..color = p.vip
        ..strokeWidth = math.max(1.6, h * 0.05)
        ..strokeCap = StrokeCap.round,
    );
  }

  final centre = cushionRect.outerRect.center;
  if (look == SeatLook.taken || look == SeatLook.crew) {
    // Someone sits here: a head and shoulders.
    final s = w * 0.15;
    final person = Paint()
      ..color = ink.withValues(alpha: look == SeatLook.crew ? 0.92 : 0.85);
    canvas.drawCircle(
      Offset(centre.dx, centre.dy - s * 0.55),
      s * 0.62,
      person,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centre.dx, centre.dy + s * 1.15),
        width: s * 2.5,
        height: s * 1.9,
      ),
      math.pi,
      math.pi,
      true,
      person,
    );
    return;
  }

  if (label != null && label.isNotEmpty && look != SeatLook.notForSale) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: math.min(12.5, w * 0.24),
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.2,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}

/// A seat glyph for legends and keys.
class SeatGlyphPainter extends CustomPainter {
  final SeatPalette palette;
  final SeatLook look;
  final bool vip;

  const SeatGlyphPainter(this.palette, this.look, {this.vip = false});

  @override
  void paint(Canvas canvas, Size size) {
    paintSeatGlyph(canvas, Offset.zero & size, palette, look, vip: vip);
  }

  @override
  bool shouldRepaint(SeatGlyphPainter old) =>
      old.palette != palette || old.look != look || old.vip != vip;
}

/// The painter — takes precomputed geometry + cached icons + selection state.
///
/// With a [palette] it draws the vehicle itself: a top-down body with the
/// windshield and mirrors at the front, the cab (driver front-left with the
/// wheel, the mate beside the kerb-side door), a bulkhead, then the
/// passenger rows and the rear window. Without one it keeps the legacy
/// icon rendering.
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

  /// Drawn-vehicle colours; null keeps the legacy icon rendering.
  final SeatPalette? palette;

  /// Font for seat numbers and captions in the drawn vehicle.
  final String? fontFamily;

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
    this.palette,
    this.fontFamily,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (palette != null) {
      _paintDrawn(canvas, palette!);
      return;
    }
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
        _drawFallbackSeat(
          canvas,
          slotRect.visualRect,
          slotRect.slot,
          isSelected,
        );
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

  // ── Drawn vehicle ─────────────────────────────────────────────────────

  void _paintDrawn(Canvas canvas, SeatPalette p) {
    final bounds = geometry.totalBounds;
    final body = Rect.fromLTRB(
      bounds.left + 9,
      bounds.top + 4,
      bounds.right - 9,
      bounds.bottom - 4,
    );
    // A trip with no seat map yet has no vehicle to draw (and its bounds are
    // too small to inset into a body).
    if (geometry.allRects.isEmpty || body.width < 80 || body.height < 80) {
      return;
    }
    final nose = math.min(46.0, body.width * 0.16);
    final hull = RRect.fromRectAndCorners(
      body,
      topLeft: Radius.circular(nose),
      topRight: Radius.circular(nose),
      bottomLeft: const Radius.circular(24),
      bottomRight: const Radius.circular(24),
    );
    final cab = currentDeck == 0 ? geometry.cabBand : null;

    // Shadow, then the mirrors (outside the body), then the body.
    canvas.drawRRect(
      hull.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x1F000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final mirrorY = body.top + nose * 0.95;
    final mirror = Paint()..color = p.hull;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.left - 7, mirrorY, 8, 18),
        const Radius.circular(3),
      ),
      mirror,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.right - 1, mirrorY, 8, 18),
        const Radius.circular(3),
      ),
      mirror,
    );
    canvas.drawRRect(hull, Paint()..color = p.body);

    if (cabinLighting != null && cabinLighting!.intensity > 0) {
      final i = cabinLighting!.intensity;
      canvas.save();
      canvas.clipRRect(hull);
      canvas.drawRect(
        body,
        Paint()
          ..shader = ui.Gradient.radial(
            body.center,
            math.max(body.width, body.height) * 0.6,
            [
              const Color(0xFFFFFFFF).withValues(alpha: 0.07 * i),
              const Color(0x00FFFFFF),
            ],
          ),
      );
      canvas.drawRect(
        Rect.fromLTRB(body.left, body.bottom - 64, body.right, body.bottom),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, body.bottom),
            Offset(0, body.bottom - 64),
            [
              const Color(0xFF000000).withValues(alpha: 0.07 * i),
              const Color(0x00000000),
            ],
          ),
      );
      canvas.restore();
    }

    // The door: an opening in the right (kerb-side) wall beside the cab.
    Rect? door;
    if (cab != null) {
      door = Rect.fromLTRB(
        body.right - 5,
        cab.top - 4,
        body.right + 5,
        cab.bottom + 12,
      );
    }
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = p.hull;
    canvas.save();
    if (door != null) canvas.clipRect(door, clipOp: ui.ClipOp.difference);
    canvas.drawRRect(hull, outline);
    canvas.restore();

    // Windshield, with a glint, and the dashboard under it.
    final glassRect = Rect.fromLTRB(
      body.left + 12,
      body.top + 9,
      body.right - 12,
      body.top + 32,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        glassRect,
        topLeft: Radius.circular(nose - 10),
        topRight: Radius.circular(nose - 10),
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          glassRect.topCenter,
          glassRect.bottomCenter,
          [p.glass, Color.lerp(p.glass, p.body, 0.45)!],
        ),
    );
    canvas.drawLine(
      Offset(glassRect.left + glassRect.width * 0.16, glassRect.bottom - 5),
      Offset(glassRect.left + glassRect.width * 0.24, glassRect.top + 5),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(body.left + 18, body.top + 40),
      Offset(body.right - 18, body.top + 40),
      Paint()
        ..color = p.hull.withValues(alpha: 0.55)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Rear window and tail lights.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          body.left + 26,
          body.bottom - 13,
          body.right - 26,
          body.bottom - 8,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = p.glass.withValues(alpha: 0.8),
    );
    final tail = Paint()..color = p.tail.withValues(alpha: 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.left + 7, body.bottom - 8, 14, 4),
        const Radius.circular(2),
      ),
      tail,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.right - 21, body.bottom - 8, 14, 4),
        const Radius.circular(2),
      ),
      tail,
    );

    // Bulkhead between the cab and the passengers.
    if (cab != null) {
      final y = cab.bottom + 27;
      final dash = Paint()
        ..color = p.hull.withValues(alpha: 0.6)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (var x = body.left + 14; x < body.right - 14; x += 9) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4.5, body.right - 14), y),
          dash,
        );
      }
    }

    if (door != null) {
      final jamb = Paint()
        ..color = p.hull
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(body.right - 6, door.top),
        Offset(body.right + 3, door.top),
        jamb,
      );
      canvas.drawLine(
        Offset(body.right - 6, door.bottom),
        Offset(body.right + 3, door.bottom),
        jamb,
      );
      canvas.drawLine(
        Offset(body.right + 0.5, door.top + 6),
        Offset(body.right + 0.5, door.bottom - 6),
        Paint()
          ..color = p.accent.withValues(alpha: 0.9)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: 'DOOR',
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 7.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: p.accent,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(body.right - 9, door.center.dy);
      canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      tp.dispose();
    }

    // Seats.
    for (final r in geometry.deckRects[currentDeck] ?? const <SlotRect>[]) {
      final slot = r.slot;
      if (slot.isCrew) {
        _paintCrew(canvas, r, p);
        continue;
      }
      if (!slot.isSeat) continue;
      final selected = selectedSeats.contains(slot.seatId);
      if (cabinLighting != null && selected) {
        _drawSelectionBloom(canvas, r.visualRect);
      }
      final look = selected
          ? SeatLook.mine
          : switch (slot.status) {
              SeatBookStatus.available => SeatLook.open,
              SeatBookStatus.booked => SeatLook.taken,
              SeatBookStatus.blocked ||
              SeatBookStatus.reserved => SeatLook.notForSale,
            };
      paintSeatGlyph(
        canvas,
        r.visualRect.deflate(2),
        p,
        look,
        label: slot.seatLabel ?? slot.seatId,
        vip: slot.tier != SeatTier.standard,
        fontFamily: fontFamily,
      );
      if (selected) _drawSelectionRing(canvas, r.visualRect);
    }
  }

  void _paintCrew(Canvas canvas, SlotRect r, SeatPalette p) {
    final rect = r.visualRect;
    final isDriver = r.slot.type == SlotType.driver;
    paintSeatGlyph(
      canvas,
      isDriver
          ? Rect.fromLTRB(
              rect.left + 3,
              rect.top + 12,
              rect.right - 3,
              rect.bottom,
            )
          : rect.deflate(3),
      p,
      SeatLook.crew,
      fontFamily: fontFamily,
    );
    if (isDriver) {
      // The wheel, in front of the driver, with a halo so it reads over
      // the seat.
      final c = Offset(rect.center.dx, rect.top + 5);
      canvas.drawCircle(
        c,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = p.body,
      );
      canvas.drawCircle(
        c,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = p.crew,
      );
      final spoke = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = p.crew;
      for (final a in const [0.0, math.pi, math.pi / 2]) {
        canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * 9, spoke);
      }
      canvas.drawCircle(c, 3, Paint()..color = p.crew);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: r.slot.seatLabel ?? (isDriver ? 'Driver' : 'Mate'),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: p.caption,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width + 24);
    tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.bottom + 3));
    tp.dispose();
  }

  void _drawSeatLabel(
    Canvas canvas,
    Rect seatRect,
    GridSlot slot,
    bool isSelected,
  ) {
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
        canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
        x += dashWidth + dashGap;
      }
    }
  }

  void _drawVipBadge(Canvas canvas, Rect seatRect) {
    const badgeSize = 18.0;
    final center = Offset(
      seatRect.left + badgeSize / 2 + 2,
      seatRect.top + badgeSize / 2 + 2,
    );
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
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(hullStyle.borderRadius)),
    );

    // Aisle-centred light pool — the aisle is the vehicle's horizontal
    // centre, so a radial pool centred on the hull middle reads as cabin
    // light regardless of the layout's column geometry.
    final center = bounds.center;
    final radius = math.max(bounds.width, bounds.height) * 0.55;
    final lightPaint = Paint()
      ..shader = ui.Gradient.radial(center, radius, [
        const Color(0xFFFFFFFF).withValues(alpha: 0.10 * light.intensity),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
      ]);
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

  void _drawFallbackSeat(
    Canvas canvas,
    Rect rect,
    GridSlot slot,
    bool isSelected,
  ) {
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
        oldDelegate.cabinLighting != cabinLighting ||
        oldDelegate.palette != palette;
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
