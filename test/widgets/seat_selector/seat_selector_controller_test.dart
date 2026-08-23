// =============================================================================
// AZAMAN — SEAT SELECTOR CONTROLLER TESTS
//
// Tests selection limits, pricing, and multi-deck state management.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';
import 'package:azaman/widgets/seat_selector/seat_selector_controller.dart';

void main() {
  late VehicleLayout singleDeckLayout;
  late VehicleLayout multiDeckLayout;

  setUp(() {
    singleDeckLayout = VehicleLayout(
      id: 'test-single',
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
            const GridSlot(type: SlotType.seat, row: 1, col: 0, seatId: '2A', status: SeatBookStatus.booked, fare: 18),
            const GridSlot(type: SlotType.seat, row: 1, col: 1, seatId: '2B', fare: 18),
            const GridSlot(type: SlotType.aisle, row: 1, col: 2),
            const GridSlot(type: SlotType.seat, row: 1, col: 3, seatId: '2C', status: SeatBookStatus.blocked, fare: 18),
            const GridSlot(type: SlotType.seat, row: 1, col: 4, seatId: '2D', fare: 18),
          ],
        ]),
      ],
    );

    multiDeckLayout = VehicleLayout(
      id: 'test-multi',
      decks: [
        Deck(deckIndex: 0, label: 'Lower', grid: [
          [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'L1A', fare: 20)],
          [const GridSlot(type: SlotType.seat, row: 1, col: 0, seatId: 'L2A', fare: 20)],
        ]),
        Deck(deckIndex: 1, label: 'Upper', grid: [
          [const GridSlot(type: SlotType.seat, row: 0, col: 0, seatId: 'U1A', fare: 25)],
          [const GridSlot(type: SlotType.seat, row: 1, col: 0, seatId: 'U2A', fare: 25)],
        ]),
      ],
    );
  });

  group('Loading layout', () {
    test('loadLayout computes geometry and fare map', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      expect(controller.layout, isNotNull);
      expect(controller.geometry, isNotNull);
      expect(controller.selectedSeats, isEmpty);
      expect(controller.totalFare, 0);
    });

    test('loadLayout resets deck if out of range', () {
      final controller = SeatSelectorController();
      controller.loadLayout(multiDeckLayout);
      controller.setDeck(1);
      expect(controller.currentDeck, 1);

      // Load a single-deck layout
      controller.loadLayout(singleDeckLayout);
      expect(controller.currentDeck, 0);
    });
  });

  group('Selection', () {
    test('toggleSeat selects an available seat', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      final result = controller.toggleSeat('1A');
      expect(result, true);
      expect(controller.selectedSeats, contains('1A'));
      expect(controller.isSelected('1A'), true);
    });

    test('toggleSeat deselects a selected seat', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      expect(controller.selectedSeats, contains('1A'));

      final result = controller.toggleSeat('1A');
      expect(result, true);
      expect(controller.selectedSeats, isNot(contains('1A')));
    });

    test('cannot select a booked seat', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      final result = controller.toggleSeat('2A');
      expect(result, false);
      expect(controller.selectedSeats, isNot(contains('2A')));
    });

    test('cannot select a blocked seat', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      final result = controller.toggleSeat('2C');
      expect(result, false);
      expect(controller.selectedSeats, isNot(contains('2C')));
    });

    test('selectSeat does not toggle off if already selected', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      expect(controller.isSelected('1A'), true);

      // selectSeat should keep it selected
      controller.selectSeat('1A');
      expect(controller.isSelected('1A'), true);
    });

    test('deselectSeat removes without toggling', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');

      controller.deselectSeat('1A');
      expect(controller.isSelected('1A'), false);
      expect(controller.isSelected('1B'), true);
    });

    test('clearSelection removes all', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');
      controller.toggleSeat('1C');

      controller.clearSelection();
      expect(controller.selectedSeats, isEmpty);
    });
  });

  group('Selection limits', () {
    test('respects selection limit', () {
      final controller = SeatSelectorController(selectionLimit: 2);
      controller.loadLayout(singleDeckLayout);

      expect(controller.toggleSeat('1A'), true);
      expect(controller.toggleSeat('1B'), true);
      // Limit reached
      expect(controller.toggleSeat('1C'), false);
      expect(controller.selectedSeats.length, 2);
    });

    test('deselection frees up a slot under limit', () {
      final controller = SeatSelectorController(selectionLimit: 2);
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');

      // Deselect one
      controller.toggleSeat('1A');
      expect(controller.selectedSeats.length, 1);

      // Can now select another
      expect(controller.toggleSeat('1C'), true);
      expect(controller.selectedSeats.length, 2);
    });

    test('reducing limit trims existing selection', () {
      final controller = SeatSelectorController(selectionLimit: 5);
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');
      controller.toggleSeat('1C');
      controller.toggleSeat('1D');

      // Reduce limit to 2
      controller.selectionLimit = 2;
      expect(controller.selectedSeats.length, 2);
    });

    test('zero limit means unlimited', () {
      final controller = SeatSelectorController(selectionLimit: 0);
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');
      controller.toggleSeat('1C');
      controller.toggleSeat('1D');
      expect(controller.selectedSeats.length, 4);
    });

    test('CheckoutState.isLimitReached works', () {
      final controller = SeatSelectorController(selectionLimit: 3);
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A');
      controller.toggleSeat('1B');
      expect(controller.checkoutState.isLimitReached, false);

      controller.toggleSeat('1C');
      expect(controller.checkoutState.isLimitReached, true);
      expect(controller.checkoutState.remainingSlots, 0);
    });
  });

  group('Pricing', () {
    test('totalFare sums selected seat fares', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A'); // 30
      controller.toggleSeat('1C'); // 18
      expect(controller.totalFare, 48);

      controller.toggleSeat('1B'); // 30
      expect(controller.totalFare, 78);
    });

    test('totalFare is 0 when nothing selected', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);
      expect(controller.totalFare, 0);
    });

    test('totalFare decreases when deselecting', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      controller.toggleSeat('1A'); // 30
      controller.toggleSeat('1B'); // 30
      expect(controller.totalFare, 60);

      controller.toggleSeat('1A');
      expect(controller.totalFare, 30);
    });
  });

  group('Multi-deck state', () {
    test('setDeck switches deck', () {
      final controller = SeatSelectorController();
      controller.loadLayout(multiDeckLayout);

      expect(controller.currentDeck, 0);
      controller.setDeck(1);
      expect(controller.currentDeck, 1);
    });

    test('setDeck ignores invalid index', () {
      final controller = SeatSelectorController();
      controller.loadLayout(multiDeckLayout);

      controller.setDeck(5);
      expect(controller.currentDeck, 0);

      controller.setDeck(-1);
      expect(controller.currentDeck, 0);
    });

    test('selecting a seat on another deck switches deck', () {
      final controller = SeatSelectorController();
      controller.loadLayout(multiDeckLayout);

      expect(controller.currentDeck, 0);

      // Select a seat on upper deck
      controller.toggleSeat('U1A');
      expect(controller.currentDeck, 1);
      expect(controller.isSelected('U1A'), true);
    });

    test('can select seats across different decks', () {
      final controller = SeatSelectorController();
      controller.loadLayout(multiDeckLayout);

      controller.toggleSeat('L1A'); // Lower deck
      controller.toggleSeat('U1A'); // Upper deck

      expect(controller.selectedSeats.length, 2);
      expect(controller.selectedSeats, containsAll(['L1A', 'U1A']));
      expect(controller.totalFare, 45); // 20 + 25
    });
  });

  group('Notifications', () {
    test('controller notifies listeners on selection change', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.toggleSeat('1A');
      expect(notifyCount, 1);

      controller.toggleSeat('1A');
      expect(notifyCount, 2);
    });

    test('clearSelection notifies listeners', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);
      controller.toggleSeat('1A');

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.clearSelection();
      expect(notifyCount, 1);
    });

    test('deselectSeat on non-selected does not notify', () {
      final controller = SeatSelectorController();
      controller.loadLayout(singleDeckLayout);

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.deselectSeat('1A');
      expect(notifyCount, 0);
    });
  });
}
