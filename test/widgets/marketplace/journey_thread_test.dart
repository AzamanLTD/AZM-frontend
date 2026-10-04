import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/marketplace/transit/journey_thread.dart';

TransitTrip _trip() => TransitTrip(
      id: 't1',
      businessProfileId: 'bp-1',
      vehicleId: 'v1',
      routeName: 'Accra – Kumasi',
      origin: 'Accra',
      destination: 'Kumasi',
      departureAt: DateTime(2026, 10, 6, 7),
      fareUsdc: 12,
      availableSeats: 20,
      status: TripStatus.scheduled,
    );

void main() {
  test('model progress walks 0 → 1 across stages', () {
    expect(JourneyThreadModel.searching().progress, 0);
    expect(JourneyThreadModel.fromTrip(_trip(), stage: JourneyStage.boarded).progress, 1);
    expect(JourneyThreadModel.fromTrip(_trip()).toLabel, 'Kumasi');
    expect(journeySeatLabel(const []), isNull);
    expect(journeySeatLabel(['12A', '12B']), '12A · 12B');
  });

  testWidgets('renders route and seat and keys by stage', (tester) async {
    final model = JourneyThreadModel.fromTrip(_trip(), stage: JourneyStage.booking, seatLabel: '4C');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: JourneyThread(model: model))),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('journey_thread_booking')), findsOneWidget);
    expect(find.text('Accra'), findsOneWidget);
    expect(find.text('Kumasi'), findsOneWidget);
    expect(find.text('Seat 4C'), findsOneWidget);
  });

  testWidgets('honours reduced motion (no pending animation)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: JourneyThread(model: JourneyThreadModel.fromTrip(_trip(), stage: JourneyStage.seat))),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}