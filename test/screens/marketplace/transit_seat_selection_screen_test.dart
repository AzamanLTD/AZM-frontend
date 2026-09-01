import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';

TransitTrip _trip() => TransitTrip(
      id: 'trip-1',
      businessProfileId: 'business-1',
      vehicleId: 'vehicle-1',
      routeName: 'Accra - Kumasi',
      origin: 'Accra',
      destination: 'Kumasi',
      departureAt: DateTime(2026, 9, 1, 8),
      arrivalAt: DateTime(2026, 9, 1, 11),
      fareUsdc: 18,
      availableSeats: 2,
      status: TripStatus.scheduled,
      vehicleType: 'Coach',
    );

SeatAvailability _availability() => const SeatAvailability(
      tripId: 'trip-1',
      seats: [
        TransitSeat(
          seatId: 'A1',
          row: 1,
          col: 1,
          type: SeatType.window,
          status: SeatStatus.available,
          tier: SeatTier.standard,
          fare: 18,
        ),
        TransitSeat(
          seatId: 'B1',
          row: 1,
          col: 2,
          type: SeatType.aisle,
          status: SeatStatus.occupied,
          tier: SeatTier.standard,
          fare: 18,
        ),
      ],
      availableCount: 1,
      totalSeats: 2,
      tripStatus: 'SCHEDULED',
      fareUsdc: 18,
    );

Future<void> _pump(
  WidgetTester tester, {
  required String tripId,
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: TransitSeatSelectionScreen(tripId: tripId),
      ),
    ),
  );
  // BusSeatSelector intentionally keeps a repeating pulse animation alive,
  // so pumpAndSettle() can never observe a settled frame here. Advance time
  // deterministically instead.
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('uses the canonical seat selector and bridges selection state',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        tripDetailProvider('trip-1').overrideWith((ref) async => _trip()),
        seatAvailabilityProvider('trip-1')
            .overrideWith((ref) async => _availability()),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, tripId: 'trip-1', container: container);

    expect(find.byType(BusSeatSelector), findsOneWidget);
    expect(find.text('Accra → Kumasi'), findsOneWidget);
    expect(find.text('Choose your seats'), findsOneWidget);
    expect(find.text('\$18/seat'), findsOneWidget);

    final selectable = find.bySemanticsLabel(RegExp(r'A1'));
    expect(selectable, findsOneWidget);
    await tester.tap(selectable);
    await tester.pump();

    expect(container.read(selectedSeatsProvider), contains('A1'));
  });

  testWidgets('clears stale selection when a fresh trip screen mounts',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        tripDetailProvider('trip-1').overrideWith((ref) async => _trip()),
        seatAvailabilityProvider('trip-1')
            .overrideWith((ref) async => _availability()),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectedSeatsProvider.notifier).state = {'A1'};

    expect(container.read(selectedSeatsProvider), contains('A1'));
    await _pump(tester, tripId: 'trip-1', container: container);

    expect(container.read(selectedSeatsProvider), isEmpty);
  });

  testWidgets('renders the screen retry state when seat availability fails',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        seatAvailabilityProvider('trip-error').overrideWith(
          (ref) async => throw Exception('seat service unavailable'),
        ),
        tripDetailProvider('trip-error').overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, tripId: 'trip-error', container: container);

    expect(find.text('Retry seat availability'), findsOneWidget);
    expect(find.byIcon(Icons.event_seat_outlined), findsOneWidget);
  });
}
