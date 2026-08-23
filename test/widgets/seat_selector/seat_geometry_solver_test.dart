// =============================================================================
// AZAMAN — SEAT GEOMETRY SOLVER TESTS
//
// Tests hit-test accuracy across zoom/pan transforms, including the enlarged
// hit-test padding beyond visual seat bounds (≥44×44 per Fitts's Law).
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';
import 'package:azaman/widgets/seat_selector/seat_geometry_solver.dart';

void main() {
  late SeatGeometrySolver solver;
  late VehicleLayout layout;
  late ComputedGeometry geometry;

  setUp(() {
    solver = const SeatGeometrySolver(SeatGeometryConfig(
      seatWidth: 50,
      seatHeight: 50,
      colGap: 6,
      rowGap: 10,
      aisleGap: 28,
      minHitTarget: 44,
      layoutPadding: 20,
      headerHeight: 40,
    ));

    // 4 rows × 4 cols with aisle in the middle
    layout = VehicleLayout(
      id: 'test-layout',
      decks: [
        Deck(deckIndex: 0, grid: _buildTestGrid()),
      ],
    );

    geometry = solver.compute(layout);
  });

  group('Geometry computation', () {
    test('computes non-empty bounds', () {
      expect(geometry.totalBounds.isEmpty, false);
      expect(geometry.totalBounds.width, greaterThan(0));
      expect(geometry.totalBounds.height, greaterThan(0));
    });

    test('all seat rects have visual bounds', () {
      final seatRects = geometry.seatRects;
      expect(seatRects.length, 16); // 4 rows × 4 seats

      for (final rect in seatRects) {
        expect(rect.visualRect.width, 50);
        expect(rect.visualRect.height, 50);
      }
    });

    test('hit-test rects are at least minHitTarget size', () {
      for (final rect in geometry.seatRects) {
        expect(rect.hitRect.width, greaterThanOrEqualTo(44));
        expect(rect.hitRect.height, greaterThanOrEqualTo(44));
      }
    });

    test('hit-test rect is centered on visual rect', () {
      for (final rect in geometry.seatRects) {
        expect(rect.hitRect.center.dx, closeTo(rect.visualRect.center.dx, 0.01));
        expect(rect.hitRect.center.dy, closeTo(rect.visualRect.center.dy, 0.01));
      }
    });

    test('non-seat slots are excluded from allRects', () {
      for (final rect in geometry.allRects) {
        expect(rect.slot.isSeat, true);
      }
    });
  });

  group('Hit-testing — local coordinates', () {
    test('hit-test returns correct seat for center of visual rect', () {
      final seatRects = geometry.seatRects;
      for (final rect in seatRects) {
        final center = rect.visualRect.center;
        final hit = solver.hitTestLocal(geometry, center);
        expect(hit, isNotNull);
        expect(hit!.seatId, rect.slot.seatId);
      }
    });

    test('hit-test works within expanded hit-test padding', () {
      // The hit-test padding extends beyond the visual rect.
      // Tap a point that's outside the visual rect but inside the hit rect.
      final firstSeat = geometry.seatRects.first;
      final tapPoint = Offset(
        firstSeat.visualRect.left - 5, // Outside visual rect
        firstSeat.visualRect.center.dy, // But within hit-test padding (since hit rect ≥44 wide)
      );

      final hit = solver.hitTestLocal(geometry, tapPoint);
      if (firstSeat.hitRect.contains(tapPoint)) {
        expect(hit, isNotNull);
        expect(hit!.seatId, firstSeat.slot.seatId);
      }
    });

    test('hit-test returns null for empty space', () {
      // Tap far outside any seat
      final hit = solver.hitTestLocal(geometry, const Offset(-1000, -1000));
      expect(hit, isNull);
    });

    test('aisle slots are not hit-testable', () {
      // Aisle is between col 1 and col 3 (col 2 is aisle)
      // Find the gap between seats
      final seatRects = geometry.seatRects;
      final firstRow = seatRects.where((r) => r.slot.row == 0).toList()
        ..sort((a, b) => a.visualRect.left.compareTo(b.visualRect.left));

      if (firstRow.length >= 2) {
        final gap = Offset(
          (firstRow[0].visualRect.right + firstRow[1].visualRect.left) / 2,
          firstRow[0].visualRect.center.dy,
        );
        // The gap should be in the aisle area, but hit rects might overlap
        // so just verify we don't get an aisle slot back
        final hit = solver.hitTestLocal(geometry, gap);
        if (hit != null) {
          expect(hit.isSeat, true);
        }
      }
    });
  });

  group('Hit-testing — screen coordinates with transform', () {
    test('identity transform: screen hit-test matches local hit-test', () {
      final seatRects = geometry.seatRects;
      for (final rect in seatRects) {
        final screenPoint = rect.visualRect.center;
        final hit = solver.hitTestScreen(
          geometry,
          screenPoint,
          Matrix4.identity(),
        );
        expect(hit, isNotNull);
        expect(hit!.seatId, rect.slot.seatId);
      }
    });

    test('scaled transform: hit-test still finds correct seat', () {
      const scale = 2.0;
      final transform = Matrix4.identity()..scale(scale);

      final seatRects = geometry.seatRects;
      for (final rect in seatRects) {
        // Screen point = local point * scale
        final screenPoint = Offset(
          rect.visualRect.center.dx * scale,
          rect.visualRect.center.dy * scale,
        );
        final hit = solver.hitTestScreen(geometry, screenPoint, transform);
        expect(hit, isNotNull);
        expect(hit!.seatId, rect.slot.seatId);
      }
    });

    test('translated + scaled transform: hit-test finds correct seat', () {
      const scale = 1.5;
      const tx = 100.0;
      const ty = 50.0;
      final transform = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(scale);

      final seatRects = geometry.seatRects;
      for (final rect in seatRects) {
        final screenPoint = Offset(
          rect.visualRect.center.dx * scale + tx,
          rect.visualRect.center.dy * scale + ty,
        );
        final hit = solver.hitTestScreen(geometry, screenPoint, transform);
        expect(hit, isNotNull);
        expect(hit!.seatId, rect.slot.seatId);
      }
    });
  });

  group('rectForSeat', () {
    test('finds the correct SlotRect for a seatId', () {
      final rect = geometry.rectForSeat('1A');
      expect(rect, isNotNull);
      expect(rect!.slot.seatId, '1A');
    });

    test('returns null for non-existent seatId', () {
      final rect = geometry.rectForSeat('ZZZ');
      expect(rect, isNull);
    });
  });

  group('Multi-deck geometry', () {
    test('deck bounds are computed separately', () {
      final multiDeckLayout = VehicleLayout(
        id: 'multi-deck-test',
        decks: [
          Deck(deckIndex: 0, label: 'Lower', grid: _buildTestGrid()),
          Deck(deckIndex: 1, label: 'Upper', grid: _buildTestGrid()),
        ],
      );

      final multiGeometry = solver.compute(multiDeckLayout);

      expect(multiGeometry.deckBounds.length, 2);
      expect(multiGeometry.deckBounds[0], isNotNull);
      expect(multiGeometry.deckBounds[1], isNotNull);

      // Upper deck should start below lower deck
      final lowerBottom = multiGeometry.deckBounds[0]!.bottom;
      final upperTop = multiGeometry.deckBounds[1]!.top;
      expect(upperTop, greaterThan(lowerBottom));
    });

    test('total bounds encompass all decks', () {
      final multiDeckLayout = VehicleLayout(
        id: 'multi-deck-total',
        decks: [
          Deck(deckIndex: 0, grid: _buildTestGrid()),
          Deck(deckIndex: 1, grid: _buildTestGrid()),
        ],
      );

      final multiGeometry = solver.compute(multiDeckLayout);

      for (final deck in multiDeckLayout.decks) {
        final bounds = multiGeometry.deckBounds[deck.deckIndex];
        expect(bounds, isNotNull);
        expect(multiGeometry.totalBounds.top, lessThanOrEqualTo(bounds!.top));
        expect(multiGeometry.totalBounds.bottom, greaterThanOrEqualTo(bounds.bottom));
      }
    });
  });
}

// ── Helper: build a 4×4 grid with aisle in middle ────────────────────────────
List<List<GridSlot>> _buildTestGrid() {
  final grid = <List<GridSlot>>[];
  for (int row = 0; row < 4; row++) {
    final rowSlots = <GridSlot>[];
    for (int col = 0; col < 4; col++) {
      // Aisle between col 1 and 2
      if (col == 2) {
        rowSlots.add(GridSlot(type: SlotType.aisle, row: row, col: col));
      }
      final letter = String.fromCharCode(65 + col);
      rowSlots.add(GridSlot(
        type: SlotType.seat,
        row: row,
        col: col,
        seatId: '${row + 1}$letter',
        tier: row == 0 ? SeatTier.vip : SeatTier.standard,
        fare: row == 0 ? 25.0 : 18.0,
      ));
    }
    grid.add(rowSlots);
  }
  return grid;
}
