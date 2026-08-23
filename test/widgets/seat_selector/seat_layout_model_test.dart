// =============================================================================
// AZAMAN — SEAT LAYOUT MODEL TESTS
//
// Tests serialization round-trips for:
//   - Vans (12-14 seats, single deck)
//   - Single-deck coaches (30+ seats)
//   - Double-decker coaches (50+ seats, 2 decks)
//   - Mixed tier layouts
//   - Seats with combined tier+status (VIP+Selected, VIP+Reserved)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';

void main() {
  group('GridSlot', () {
    test('seat slot serializes and deserializes correctly', () {
      final slot = const GridSlot(
        type: SlotType.seat,
        row: 0,
        col: 1,
        seatId: '1B',
        seatLabel: '1B',
        tier: SeatTier.vip,
        status: SeatBookStatus.available,
        fare: 25.0,
      );

      final json = slot.toJson();
      final restored = GridSlot.fromJson(json);

      expect(restored.type, SlotType.seat);
      expect(restored.row, 0);
      expect(restored.col, 1);
      expect(restored.seatId, '1B');
      expect(restored.seatLabel, '1B');
      expect(restored.tier, SeatTier.vip);
      expect(restored.status, SeatBookStatus.available);
      expect(restored.fare, 25.0);
      expect(restored.isSeat, true);
      expect(restored.isTappable, true);
    });

    test('non-seat slot has isSeat false', () {
      const slot = GridSlot(type: SlotType.aisle, row: 0, col: 2);
      expect(slot.isSeat, false);
      expect(slot.isTappable, false);
    });

    test('booked seat is not tappable', () {
      const slot = GridSlot(
        type: SlotType.seat,
        row: 1,
        col: 0,
        seatId: '2A',
        status: SeatBookStatus.booked,
      );
      expect(slot.isTappable, false);
    });

    test('VIP + Available seat has both tier and status independently', () {
      const slot = GridSlot(
        type: SlotType.seat,
        row: 0,
        col: 0,
        seatId: '1A',
        tier: SeatTier.vip,
        status: SeatBookStatus.available,
      );
      expect(slot.tier, SeatTier.vip);
      expect(slot.status, SeatBookStatus.available);
      expect(slot.isTappable, true);
    });

    test('VIP + Reserved seat: tier and status are orthogonal', () {
      const slot = GridSlot(
        type: SlotType.seat,
        row: 0,
        col: 0,
        seatId: '1A',
        tier: SeatTier.vip,
        status: SeatBookStatus.reserved,
      );
      expect(slot.tier, SeatTier.vip);
      expect(slot.status, SeatBookStatus.reserved);
      expect(slot.isTappable, false);
    });

    test('VIP + Selected (local UI state): status stays available, selection is UI', () {
      const slot = GridSlot(
        type: SlotType.seat,
        row: 0,
        col: 0,
        seatId: '1A',
        tier: SeatTier.vip,
        status: SeatBookStatus.available,
      );
      // Backend status is still 'available' — selection is local UI state
      expect(slot.tier, SeatTier.vip);
      expect(slot.status, SeatBookStatus.available);
      expect(slot.isTappable, true);
    });
  });

  group('SeatTier', () {
    test('fromJson handles all variants', () {
      expect(SeatTier.fromJson('VIP'), SeatTier.vip);
      expect(SeatTier.fromJson('vip'), SeatTier.vip);
      expect(SeatTier.fromJson('EXECUTIVE'), SeatTier.executive);
      expect(SeatTier.fromJson('STANDARD'), SeatTier.standard);
      expect(SeatTier.fromJson(null), SeatTier.standard);
      expect(SeatTier.fromJson(''), SeatTier.standard);
    });

    test('toJson round-trips', () {
      expect(SeatTier.vip.toJson(), 'VIP');
      expect(SeatTier.standard.toJson(), 'STANDARD');
      expect(SeatTier.executive.toJson(), 'EXECUTIVE');
    });
  });

  group('SeatBookStatus', () {
    test('fromJson maps BOOKED and OCCUPIED to booked', () {
      expect(SeatBookStatus.fromJson('BOOKED'), SeatBookStatus.booked);
      expect(SeatBookStatus.fromJson('OCCUPIED'), SeatBookStatus.booked);
      expect(SeatBookStatus.fromJson('BLOCKED'), SeatBookStatus.blocked);
      expect(SeatBookStatus.fromJson('RESERVED'), SeatBookStatus.reserved);
      expect(SeatBookStatus.fromJson('AVAILABLE'), SeatBookStatus.available);
      expect(SeatBookStatus.fromJson(null), SeatBookStatus.available);
    });

    test('isTappable only for available', () {
      expect(SeatBookStatus.available.isTappable, true);
      expect(SeatBookStatus.booked.isTappable, false);
      expect(SeatBookStatus.blocked.isTappable, false);
      expect(SeatBookStatus.reserved.isTappable, false);
    });
  });

  group('Van layout (14-seat single deck)', () {
    test('serializes round-trip correctly', () {
      final layout = VehicleLayout(
        id: 'van-001',
        vehicleType: 'VAN',
        vehicleMake: 'Toyota',
        vehicleModel: 'HiAce',
        decks: [
          Deck(
            deckIndex: 0,
            label: 'Main',
            grid: _buildVanGrid(),
          ),
        ],
      );

      final json = layout.toJson();
      final restored = VehicleLayout.fromJson(json);

      expect(restored.id, 'van-001');
      expect(restored.vehicleMake, 'Toyota');
      expect(restored.decks.length, 1);
      expect(restored.isMultiDeck, false);
      expect(restored.totalSeats, 14);
    });
  });

  group('Single-deck coach (30 seats)', () {
    test('serializes round-trip correctly', () {
      final layout = VehicleLayout(
        id: 'coach-001',
        vehicleType: 'COACH',
        vehicleMake: 'Mercedes-Benz',
        vehicleModel: 'Sprinter 450',
        decks: [
          Deck(
            deckIndex: 0,
            grid: _buildCoachGrid(rows: 10, cols: 4),
          ),
        ],
      );

      final json = layout.toJson();
      final restored = VehicleLayout.fromJson(json);

      expect(restored.decks.length, 1);
      expect(restored.totalSeats, 40);
      expect(restored.decks[0].rowCount, 10);
    });
  });

  group('Double-decker coach (50+ seats)', () {
    test('serializes round-trip with two decks', () {
      final layout = VehicleLayout(
        id: 'double-decker-001',
        vehicleType: 'DOUBLE_DECKER',
        vehicleMake: 'Scania',
        vehicleModel: 'K410',
        decks: [
          Deck(
            deckIndex: 0,
            label: 'Lower',
            grid: _buildCoachGrid(rows: 13, cols: 4),
          ),
          Deck(
            deckIndex: 1,
            label: 'Upper',
            grid: _buildCoachGrid(rows: 13, cols: 4),
          ),
        ],
      );

      final json = layout.toJson();
      final restored = VehicleLayout.fromJson(json);

      expect(restored.isMultiDeck, true);
      expect(restored.decks.length, 2);
      expect(restored.decks[0].label, 'Lower');
      expect(restored.decks[1].label, 'Upper');
      expect(restored.totalSeats, 104);
    });

    test('findSeat searches across all decks', () {
      final layout = VehicleLayout(
        id: 'dd-002',
        decks: [
          Deck(deckIndex: 0, grid: [
            [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'L1A')],
          ]),
          Deck(deckIndex: 1, grid: [
            [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'U1A')],
          ]),
        ],
      );

      expect(layout.findSeat('L1A')?.seatId, 'L1A');
      expect(layout.findSeat('U1A')?.seatId, 'U1A');
      expect(layout.findSeat('X1A'), isNull);
    });

    test('deckIndexForSeat returns correct deck', () {
      final layout = VehicleLayout(
        id: 'dd-003',
        decks: [
          Deck(deckIndex: 0, grid: [
            [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'L1A')],
          ]),
          Deck(deckIndex: 1, grid: [
            [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'U1A')],
          ]),
        ],
      );

      expect(layout.deckIndexForSeat('L1A'), 0);
      expect(layout.deckIndexForSeat('U1A'), 1);
      expect(layout.deckIndexForSeat('X1A'), isNull);
    });
  });

  group('Mixed tier layouts', () {
    test('layout with VIP, Standard, and Executive tiers', () {
      final layout = VehicleLayout(
        id: 'mixed-001',
        decks: [
          Deck(deckIndex: 0, grid: [
            [
              const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: '1A', tier: SeatTier.vip, fare: 30),
              const GridSlot(type: SlotType.seat, row: 0, col: 1, seatId: '1B', tier: SeatTier.vip, fare: 30),
              const GridSlot(type: SlotType.aisle, row: 0, col: 2),
              const GridSlot(type: SlotType.seat, row: 0, col: 3, seatId: '1C', tier: SeatTier.standard, fare: 18),
              const GridSlot(type: SlotType.seat, row: 0, col: 4, seatId: '1D', tier: SeatTier.standard, fare: 18),
            ],
            [
              const GridSlot(type: SlotType.seat, row: 1, col: 0, seatId: '2A', tier: SeatTier.executive, fare: 22),
              const GridSlot(type: SlotType.seat, row: 1, col: 1, seatId: '2B', tier: SeatTier.standard, fare: 18),
            ],
          ]),
        ],
      );

      final json = layout.toJson();
      final restored = VehicleLayout.fromJson(json);

      final seats = restored.allSeats;
      expect(seats.where((s) => s.tier == SeatTier.vip).length, 2);
      expect(seats.where((s) => s.tier == SeatTier.standard).length, 3);
      expect(seats.where((s) => s.tier == SeatTier.executive).length, 1);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<List<GridSlot>> _buildVanGrid() {
  // 14-seat van: 7 rows × 2 cols
  final grid = <List<GridSlot>>[];
  for (int row = 0; row < 7; row++) {
    grid.add([
      GridSlot(type: SlotType.seat, row: row, col: 0, seatId: '${row + 1}A'),
      GridSlot(type: SlotType.aisle, row: row, col: 1),
      GridSlot(type: SlotType.seat, row: row, col: 2, seatId: '${row + 1}B'),
    ]);
  }
  return grid;
}

List<List<GridSlot>> _buildCoachGrid({required int rows, required int cols}) {
  final grid = <List<GridSlot>>[];
  for (int row = 0; row < rows; row++) {
    final rowSlots = <GridSlot>[];
    for (int col = 0; col < cols; col++) {
      // Aisle after col 1
      if (col == 2) {
        rowSlots.add(GridSlot(type: SlotType.aisle, row: row, col: col));
      }
      final letter = String.fromCharCode(65 + col);
      rowSlots.add(GridSlot(
        type: SlotType.seat,
        row: row,
        col: col,
        seatId: '${row + 1}$letter',
        tier: row < 2 ? SeatTier.vip : SeatTier.standard,
        fare: row < 2 ? 25.0 : 18.0,
      ));
    }
    grid.add(rowSlots);
  }
  return grid;
}
