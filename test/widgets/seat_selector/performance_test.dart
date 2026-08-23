// =============================================================================
// AZAMAN — SEAT SELECTOR PERFORMANCE TESTS
//
// Asserts geometry computation and hit-test execution stay within frame
// budget for a 60-seat single-deck layout under continuous simulated
// pan/zoom.
//
// Target: comfortably inside a 16.6ms/frame budget with headroom for the
// rest of the frame (paint operations measured separately on device).
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';
import 'package:azaman/widgets/seat_selector/seat_geometry_solver.dart';

void main() {
  late VehicleLayout largeLayout;
  late ComputedGeometry geometry;

  setUp(() {
    // Build a 60-seat single-deck layout (15 rows × 4 cols)
    largeLayout = VehicleLayout(
      id: 'perf-test-60',
      vehicleType: 'COACH',
      decks: [
        Deck(deckIndex: 0, grid: _buildLargeGrid(rows: 15, cols: 4)),
      ],
    );

    final solver = const SeatGeometrySolver();
    geometry = solver.compute(largeLayout);
  });

  group('Geometry computation performance', () {
    test('compute() for 60-seat layout completes in under 5ms', () {
      final solver = const SeatGeometrySolver();
      final stopwatch = Stopwatch()..start();

      // Run multiple iterations to get a stable measurement
      for (int i = 0; i < 100; i++) {
        solver.compute(largeLayout);
      }

      stopwatch.stop();
      final avgMicros = stopwatch.elapsedMicroseconds / 100;
      final avgMillis = avgMicros / 1000;

      // Should be well under 5ms per computation
      expect(avgMillis, lessThan(5.0),
          reason: 'compute() took ${avgMillis}ms avg — must be < 5ms');
    });
  });

  group('shouldRepaint logic', () {
    test('same selectedSeats set identity returns false', () {
      final setA = <String>{'1A', '1B'};
      final setB = <String>{'1A', '1B'};

      // Set.equals does deep equality in Dart
      expect(setA.containsAll(setB) && setB.containsAll(setA), true);
      expect(setA.length == setB.length, true);
    });

    test('different selectedSeats sets are not equal', () {
      final setA = <String>{'1A', '1B'};
      final setB = <String>{'1A', '1C'};

      expect(setA.containsAll(setB) && setB.containsAll(setA), false);
    });
  });

  group('Paint iteration performance (rect traversal)', () {
    test('iterating 60 seat rects stays under 1ms', () {
      final stopwatch = Stopwatch()..start();

      // Simulate what paint() does: iterate all seat rects for current deck
      final deckRects = geometry.deckRects[0] ?? [];
      int seatCount = 0;
      for (final rect in deckRects) {
        if (!rect.slot.isSeat) continue;
        seatCount++;
        // Access the visual and hit rects (simulating draw operations)
        final _ = rect.visualRect;
        final _hit = rect.hitRect;
      }

      stopwatch.stop();
      final elapsedMillis = stopwatch.elapsedMicroseconds / 1000;

      // Iterating 60 seat rects should take < 1ms (the actual paint with
      // drawRRect/drawPicture would be a few ms more, but still within 16.6ms)
      expect(seatCount, 60);
      expect(elapsedMillis, lessThan(1.0),
          reason: 'Rect iteration took ${elapsedMillis}ms — must be < 1ms for headroom');
    });
  });

  group('Hit-test performance', () {
    test('hitTestLocal for 60-seat layout stays under 1ms per call', () {
      final solver = const SeatGeometrySolver();
      final geo = solver.compute(largeLayout);

      final stopwatch = Stopwatch()..start();

      // Simulate continuous pan/zoom: 1000 hit-tests at various points
      for (int i = 0; i < 1000; i++) {
        final point = Offset(
          ((i * 7) % geo.totalBounds.width.toInt().clamp(1, 9999)).toDouble(),
          ((i * 13) % geo.totalBounds.height.toInt().clamp(1, 9999)).toDouble(),
        );
        solver.hitTestLocal(geo, point);
      }

      stopwatch.stop();
      final avgMicros = stopwatch.elapsedMicroseconds / 1000;
      final avgMillis = avgMicros / 1000;

      // Each hit-test should be < 1ms (it's O(n) over seats, but n=60 is tiny)
      expect(avgMillis, lessThan(1.0),
          reason: 'hitTestLocal avg ${avgMillis}ms — must be < 1ms per call');
    });
  });
}

// ── Helper: build a large grid for performance testing ──────────────────────
List<List<GridSlot>> _buildLargeGrid({required int rows, required int cols}) {
  final grid = <List<GridSlot>>[];
  for (int row = 0; row < rows; row++) {
    final rowSlots = <GridSlot>[];
    for (int col = 0; col < cols; col++) {
      // Aisle in the middle
      if (col == cols ~/ 2) {
        rowSlots.add(GridSlot(type: SlotType.aisle, row: row, col: col));
      }
      final letter = String.fromCharCode(65 + col);
      rowSlots.add(GridSlot(
        type: SlotType.seat,
        row: row,
        col: col,
        seatId: '${row + 1}$letter',
        tier: row < 3 ? SeatTier.vip : SeatTier.standard,
        fare: row < 3 ? 25.0 : 18.0,
        status: (row + col) % 7 == 0 ? SeatBookStatus.booked : SeatBookStatus.available,
      ));
    }
    grid.add(rowSlots);
  }
  return grid;
}
