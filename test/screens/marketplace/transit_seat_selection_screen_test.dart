import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';

void main() {
  testWidgets('uses the canonical seat selector and bridges selection state',
      (tester) async {
    final trip = TransitTrip(
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
    final availability = SeatAvailability(
      tripId: 'trip-1',
      seats: const [
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripDetailProvider('trip-1').overrideWith((ref) async => trip),
          seatAvailabilityProvider('trip-1')
              .overrideWith((ref) async => availability),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const TransitSeatSelectionScreen(tripId: 'trip-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(BusSeatSelector), findsOneWidget);
    expect(find.text('Accra → Kumasi'), findsOneWidget);
    expect(find.text('Choose your seats'), findsOneWidget);
    expect(find.text('1 seat'), findsNothing);
    expect(find.text('0.00'), findsNothing);

    final selectable = find.bySemanticsLabel(RegExp(r'A1'));
    expect(selectable, findsOneWidget);
    await tester.tap(selectable);
    await tester.pump();

    final selected = ProviderScope.containerOf(
      tester.element(find.byType(BusSeatSelector)),
    ).read(selectedSeatsProvider);
    expect(selected, contains('A1'));
  });

  testWidgets('renders the screen retry state when seat availability fails',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seatAvailabilityProvider('trip-error').overrideWith(
            (ref) async => throw Exception('seat service unavailable'),
          ),
          tripDetailProvider('trip-error').overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: const TransitSeatSelectionScreen(tripId: 'trip-error'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Retry seat availability'), findsOneWidget);
    expect(find.byIcon(Icons.event_seat_outlined), findsOneWidget);
  });
}
