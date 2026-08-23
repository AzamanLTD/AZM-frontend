// =============================================================================
// AZAMAN — SEAT GEOMETRY SOLVER
//
// Pure-Dart geometry engine. Maps (deck, row, col) grid coordinates to
// screen-space Rects, precomputed ONCE per layout load or viewport resize
// and cached — never recomputed inside paint() or during gesture callbacks.
//
// Also does inverse hit-testing: given a tap point + current transform matrix,
// return the tapped GridSlot (or null), with a generous hit-test padding
// around each seat's visual bounds (≥44×44 logical px per Fitts's Law).
// =============================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4, MatrixUtils;

import 'seat_layout_models.dart';

/// Configuration for the geometry solver — all sizes in logical pixels.
class SeatGeometryConfig {
  /// Width of a single seat icon cell.
  final double seatWidth;

  /// Height of a single seat icon cell.
  final double seatHeight;

  /// Horizontal gap between adjacent seats in a row.
  final double colGap;

  /// Vertical gap between seat rows.
  final double rowGap;

  /// Aisle gap width (inserted where aisle slots appear).
  final double aisleGap;

  /// Padding around the entire layout (inside the vehicle hull).
  final double layoutPadding;

  /// Minimum hit-test target size (Fitts's Law / accessibility).
  final double minHitTarget;

  /// Height of the windshield/front-of-vehicle header area.
  final double headerHeight;

  /// Gap between decks in a multi-deck vehicle.
  final double deckGap;

  const SeatGeometryConfig({
    this.seatWidth = 50,
    this.seatHeight = 50,
    this.colGap = 6,
    this.rowGap = 10,
    this.aisleGap = 28,
    this.layoutPadding = 20,
    this.minHitTarget = 44,
    this.headerHeight = 40,
    this.deckGap = 24,
  });

  /// Default configuration matching the existing seat widget dimensions.
  static const defaultConfig = SeatGeometryConfig();
}

/// Precomputed Rect for a single slot, with hit-test bounds that are at
/// least [SeatGeometryConfig.minHitTarget] in each dimension, centered on
/// the visual rect.
class SlotRect {
  final GridSlot slot;
  final int deckIndex;

  /// Visual bounds (where the icon is drawn).
  final Rect visualRect;

  /// Hit-test bounds (≥44×44, centered on visualRect).
  final Rect hitRect;

  const SlotRect({
    required this.slot,
    required this.deckIndex,
    required this.visualRect,
    required this.hitRect,
  });

  @override
  String toString() =>
      'SlotRect($deckIndex:(${slot.row},${slot.col}) visual=$visualRect hit=$hitRect)';
}

/// The complete precomputed geometry for a vehicle layout.
class ComputedGeometry {
  final VehicleLayout layout;
  final SeatGeometryConfig config;

  /// All slot rects flattened across decks.
  final List<SlotRect> allRects;

  /// Rects grouped by deck index.
  final Map<int, List<SlotRect>> deckRects;

  /// Total bounding box of the entire layout (all decks).
  final Rect totalBounds;

  /// Bounding box per deck.
  final Map<int, Rect> deckBounds;

  const ComputedGeometry({
    required this.layout,
    required this.config,
    required this.allRects,
    required this.deckRects,
    required this.totalBounds,
    required this.deckBounds,
  });

  /// All seat slot rects (excludes aisles, doors, etc.).
  List<SlotRect> get seatRects =>
      allRects.where((r) => r.slot.isSeat).toList();

  /// Find the SlotRect for a given seatId.
  SlotRect? rectForSeat(String seatId) {
    for (final r in allRects) {
      if (r.slot.seatId == seatId) return r;
    }
    return null;
  }
}

/// The solver — stateless, takes config + layout, produces ComputedGeometry.
class SeatGeometrySolver {
  final SeatGeometryConfig config;

  const SeatGeometrySolver([this.config = SeatGeometryConfig.defaultConfig]);

  /// Compute the full geometry for a [VehicleLayout].
  /// Call once on layout load or viewport resize, cache the result.
  ComputedGeometry compute(VehicleLayout layout) {
    final allRects = <SlotRect>[];
    final deckRects = <int, List<SlotRect>>{};
    final deckBounds = <int, Rect>{};

    double yOffset = config.layoutPadding;

    for (final deck in layout.decks) {
      // Add header for first deck only
      final deckStartY =
          deck.deckIndex == 0 ? yOffset + config.headerHeight : yOffset;
      if (deck.deckIndex == 0) {
        yOffset += config.headerHeight;
      }

      final rectList = <SlotRect>[];
      double maxX = 0;
      double maxY = deckStartY;

      double rowY = deckStartY;
      for (int rowIdx = 0; rowIdx < deck.rowCount; rowIdx++) {
        final row = deck.grid[rowIdx];
        double colX = config.layoutPadding;

        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          final slot = row[colIdx];

          // Determine cell width (aisle gets extra gap, non-seat cells may be smaller)
          final double cellW;
          final double cellH;

          if (slot.type == SlotType.aisle || slot.type == SlotType.empty) {
            // Aisle/empty: advance by aisle gap, no visible rect
            colX += config.aisleGap;
            continue;
          }

          cellW = config.seatWidth;
          cellH = config.seatHeight;

          final visualRect = Rect.fromLTWH(colX, rowY, cellW, cellH);

          // Expand hit rect to minimum target size, centered on visual
          final hitW = math.max(cellW, config.minHitTarget);
          final hitH = math.max(cellH, config.minHitTarget);
          final hitRect = Rect.fromCenter(
            center: visualRect.center,
            width: hitW,
            height: hitH,
          );

          final slotRect = SlotRect(
            slot: slot,
            deckIndex: deck.deckIndex,
            visualRect: visualRect,
            hitRect: hitRect,
          );

          rectList.add(slotRect);
          allRects.add(slotRect);

          colX += cellW + config.colGap;
          if (colX > maxX) maxX = colX;
        }

        rowY += config.seatHeight + config.rowGap;
        if (rowY > maxY) maxY = rowY;
      }

      // Compute deck bounds
      // For the first deck, top starts at layoutPadding (includes header area).
      // For subsequent decks, top is deckStartY (no padding subtraction —
      // the deckGap already separates them visually).
      final dBounds = Rect.fromLTRB(
        0,
        deck.deckIndex == 0 ? 0 : deckStartY,
        maxX + config.layoutPadding,
        maxY + config.layoutPadding,
      );
      deckBounds[deck.deckIndex] = dBounds;
      deckRects[deck.deckIndex] = rectList;

      yOffset = maxY + config.deckGap;
    }

    // Total bounds across all decks
    final totalBounds = Rect.fromLTRB(
      0,
      0,
      deckBounds.values.map((r) => r.right).reduce(math.max),
      yOffset,
    );

    return ComputedGeometry(
      layout: layout,
      config: config,
      allRects: allRects,
      deckRects: deckRects,
      totalBounds: totalBounds,
      deckBounds: deckBounds,
    );
  }

  /// Inverse hit-test: given a [tapPoint] in layout-local coordinates and
  /// the current [transform] matrix, return the tapped SlotRect or null.
  ///
  /// The tapPoint should already be in the layout's local coordinate space
  /// (i.e. transformed by the inverse of the InteractiveViewer's matrix).
  /// If you pass a screen-space point, call [hitTestScreen] instead.
  GridSlot? hitTestLocal(ComputedGeometry geometry, Offset tapPoint) {
    for (final rect in geometry.allRects) {
      if (!rect.slot.isSeat) continue;
      if (rect.hitRect.contains(tapPoint)) {
        return rect.slot;
      }
    }
    return null;
  }

  /// Hit-test using a screen-space point and the current transform matrix.
  /// Transforms the screen point into layout-local space, then hit-tests.
  GridSlot? hitTestScreen(
    ComputedGeometry geometry,
    Offset screenPoint,
    Matrix4 transform,
  ) {
    // Invert the transform to go from screen → local
    final inverse = Matrix4.inverted(transform);
    final localPoint = MatrixUtils.transformPoint(inverse, screenPoint);
    return hitTestLocal(geometry, localPoint);
  }
}
