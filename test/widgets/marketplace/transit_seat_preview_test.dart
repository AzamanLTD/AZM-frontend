import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/transit_seat_preview.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

void main() {
  testWidgets('shows journey-specific transit context above the seat map',
      (tester) async {
    final trip = TransitTrip(
      id: 'trip-1',
      businessProfileId: 'business-internal-1',
      vehicleId: 'vehicle-1',
      routeName: 'Accra - Kumasi',
      origin: 'Accra',
      destination: 'Kumasi',
      departureAt: DateTime(2026, 9, 1, 7, 30),
      arrivalAt: DateTime(2026, 9, 1, 11, 45),
      fareUsdc: 18.5,
      availableSeats: 7,
      status: TripStatus.scheduled,
      vehicleType: 'Coach',
      vehicleMake: 'Yutong',
      vehicleModel: 'ZK6122',
      driverName: 'Kwame Mensah',
      plateNumber: 'GR-1234-24',
    );

    const availability = SeatAvailability(
      tripId: 'trip-1',
      seats: <TransitSeat>[],
      availableCount: 7,
      totalSeats: 40,
      tripStatus: 'SCHEDULED',
      fareUsdc: 18.5,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transitTripsProvider('business-internal-1')
              .overrideWith((ref) async => [trip]),
          seatAvailabilityProvider('trip-1')
              .overrideWith((ref) async => availability),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TransitSeatPreview(
              businessProfileId: 'business-internal-1',
              colors: _colors,
              onOpenTrips: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Accra → Kumasi'), findsOneWidget);
    expect(find.text('Tue, Sep 1'), findsOneWidget);
    expect(find.text('7:30 AM'), findsOneWidget);
    expect(find.text('4h 15m'), findsOneWidget);
    expect(find.text('18.50 USDC'), findsOneWidget);
    expect(find.text('7 seats'), findsOneWidget);
    expect(
      find.text('Yutong ZK6122 · GR-1234-24 · Driver: Kwame Mensah'),
      findsOneWidget,
    );
  });
}
