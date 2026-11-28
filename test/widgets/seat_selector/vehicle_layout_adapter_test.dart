// The vehicle a passenger sees, built from the operator's seat map: real
// columns, walkways, NONE cells, the cab (driver front-left, mate beside the
// door), and the drawn-vehicle palette.
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_booking_models.dart' as booking;
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';
import 'package:azaman/widgets/seat_selector/seat_canvas_painter.dart';
import 'package:azaman/widgets/seat_selector/seat_geometry_solver.dart';
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';

booking.TransitSeat _s(String id, int row, int col, {String? type}) =>
    booking.TransitSeat.fromJson({
      'seatId': id,
      'row': row,
      'col': col,
      'type': type ?? 'WINDOW',
      'status': 'AVAILABLE',
      'tier': 'ECONOMY',
      'fare': 2,
    });

String _id(int r, int c) => '$r${String.fromCharCode(64 + c)}';

List<SlotType> _types(List<GridSlot> row) => row.map((s) => s.type).toList();

void main() {
  group('NONE cells', () {
    test('parse as space and never become seats', () {
      final none = _s('1C', 1, 3, type: 'NONE');
      expect(none.isSpace, isTrue);
      final layout = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: [_s('1A', 1, 1), _s('1B', 1, 2), none, _s('1D', 1, 4)],
        withCab: false,
      );
      expect(layout.allSeats.map((s) => s.seatId), ['1A', '1B', '1D']);
    });

    test('a column NONE in every row is the walkway', () {
      final seats = [
        for (var r = 1; r <= 3; r++) ...[
          _s(_id(r, 1), r, 1),
          _s(_id(r, 2), r, 2),
          _s(_id(r, 3), r, 3, type: 'NONE'),
          _s(_id(r, 4), r, 4),
        ],
      ];
      final layout = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: seats,
        withCab: false,
      );
      for (final row in layout.decks.single.grid) {
        expect(_types(row), [
          SlotType.seat,
          SlotType.seat,
          SlotType.aisle,
          SlotType.seat,
        ]);
      }
    });
  });

  test(
    'the portal default grid (no walkway drawn) gets one between the halves',
    () {
      final seats = [
        for (var r = 1; r <= 2; r++)
          for (var c = 1; c <= 4; c++) _s(_id(r, c), r, c),
      ];
      final layout = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: seats,
        withCab: false,
      );
      for (final row in layout.decks.single.grid) {
        expect(_types(row), [
          SlotType.seat,
          SlotType.seat,
          SlotType.aisle,
          SlotType.seat,
          SlotType.seat,
        ]);
      }
    },
  );

  test(
    'a back bench across the walkway keeps the walkway seat-wide, with no extra aisle',
    () {
      final seats = <booking.TransitSeat>[
        for (var r = 1; r <= 3; r++) ...[
          _s(_id(r, 1), r, 1),
          _s(_id(r, 2), r, 2),
          _s(_id(r, 3), r, 3, type: 'NONE'),
          _s(_id(r, 4), r, 4),
        ],
        for (var c = 1; c <= 4; c++) _s(_id(4, c), 4, c),
      ];
      final grid = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: seats,
        withCab: false,
      ).decks.single.grid;
      expect(_types(grid.first), [
        SlotType.seat,
        SlotType.seat,
        SlotType.empty,
        SlotType.seat,
      ]);
      expect(_types(grid.last), [
        SlotType.seat,
        SlotType.seat,
        SlotType.seat,
        SlotType.seat,
      ]);
      expect(grid.last[2].seatId, '4C');
    },
  );

  group('the cab', () {
    List<booking.TransitSeat> grid(int rows, int cols) => [
      for (var r = 1; r <= rows; r++)
        for (var c = 1; c <= cols; c++) _s(_id(r, c), r, c),
    ];

    test('leads with the driver front-left and the mate front-right', () {
      final layout = vehicleLayoutFromSeats(layoutId: 'v', seats: grid(4, 4));
      final cab = layout.decks.single.grid.first;
      expect(cab.first.type, SlotType.driver);
      expect(cab.first.seatLabel, 'Driver');
      expect(cab.last.type, SlotType.crew);
      expect(cab.last.seatLabel, 'Mate');
      // The cab never adds bookable seats.
      expect(layout.totalSeats, 16);
      expect(cab.every((s) => !s.isSeat && !s.isTappable), isTrue);
    });

    test('a car (fewer than eight seats) has a driver and no mate', () {
      final cab = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: grid(2, 2),
      ).decks.single.grid.first;
      expect(_types(cab), [SlotType.driver, SlotType.empty]);
    });

    test('the operator\'s mate name labels the mate', () {
      final cab = vehicleLayoutFromSeats(
        layoutId: 'v',
        seats: grid(4, 4),
        mateLabel: 'Kojo',
      ).decks.single.grid.first;
      expect(cab.last.seatLabel, 'Kojo');
    });

    test(
      'geometry: crew rects form the cab band and are never hit as seats',
      () {
        final layout = vehicleLayoutFromSeats(layoutId: 'v', seats: grid(3, 4));
        final g = const SeatGeometrySolver().compute(layout);
        expect(g.crewRects, hasLength(2));
        expect(g.cabBand, isNotNull);
        expect(g.seatRects.every((r) => r.slot.isSeat), isTrue);
        final driver = g.crewRects.firstWhere(
          (r) => r.slot.type == SlotType.driver,
        );
        expect(
          const SeatGeometrySolver().hitTestLocal(g, driver.visualRect.center),
          isNull,
        );
        // The first passenger row clears the cab by the cab gap.
        final firstSeat = g.seatRects.first.visualRect;
        expect(
          firstSeat.top - g.cabBand!.bottom,
          greaterThanOrEqualTo(
            const SeatGeometryConfig().rowGap +
                const SeatGeometryConfig().cabGap,
          ),
        );
      },
    );
  });

  test('margins are symmetric left and right', () {
    final layout = vehicleLayoutFromSeats(
      layoutId: 'v',
      seats: [for (var c = 1; c <= 4; c++) _s(_id(1, c), 1, c)],
      withCab: false,
    );
    final g = const SeatGeometrySolver().compute(layout);
    final left = g.seatRects
        .map((r) => r.visualRect.left)
        .reduce((a, b) => a < b ? a : b);
    final right = g.seatRects
        .map((r) => r.visualRect.right)
        .reduce((a, b) => a > b ? a : b);
    expect(
      g.totalBounds.right - right,
      closeTo(left - g.totalBounds.left, 0.001),
    );
  });

  group('SeatPalette', () {
    for (final dark in [false, true]) {
      test(
        'open, taken, crew and your seat are distinct (${dark ? 'dark' : 'light'})',
        () {
          final p = SeatPalette.fromTheme(
            accent: const Color(0xFF1D4ED8),
            surface: dark ? const Color(0xFF16181D) : const Color(0xFFFFFFFF),
            divider: dark ? const Color(0xFF2A2E36) : const Color(0xFFE4E4E7),
            textPrimary: dark
                ? const Color(0xFFF4F4F5)
                : const Color(0xFF111114),
            textSecondary: dark
                ? const Color(0xFFA1A1AA)
                : const Color(0xFF52525B),
            textTertiary: dark
                ? const Color(0xFF71717A)
                : const Color(0xFFA1A1AA),
            background: dark
                ? const Color(0xFF0B0C0F)
                : const Color(0xFFF4F4F5),
            danger: const Color(0xFFEF4444),
          );
          final fills = {p.seat, p.taken, p.crew, p.accent};
          expect(fills, hasLength(4));
          // Ink on your seat reads against the accent.
          expect(p.onAccent, const Color(0xFFFFFFFF));
        },
      );
    }
  });

  test('a trip with no seat map yet paints nothing and does not throw', () {
    final layout = vehicleLayoutFromSeats(layoutId: 'v', seats: const []);
    final g = const SeatGeometrySolver().compute(layout);
    final recorder = PictureRecorder();
    SeatCanvasPainter(
      geometry: g,
      iconCache: const SeatIconCache(),
      selectedSeats: const {},
      hullStyle: const HullStyle(
        bodyColor: Color(0xFF888888),
        borderColor: Color(0xFF444444),
      ),
      accentColor: const Color(0xFF1D4ED8),
      palette: SeatPalette.fromTheme(
        accent: const Color(0xFF1D4ED8),
        surface: const Color(0xFFFFFFFF),
        divider: const Color(0xFFE4E4E7),
        textPrimary: const Color(0xFF111114),
        textSecondary: const Color(0xFF52525B),
        textTertiary: const Color(0xFFA1A1AA),
        background: const Color(0xFFF4F4F5),
        danger: const Color(0xFFEF4444),
      ),
    ).paint(Canvas(recorder), g.totalBounds.size);
    recorder.endRecording().dispose();
  });
}
