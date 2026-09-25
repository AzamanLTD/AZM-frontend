import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/transit/transit_boarding.dart';
import 'package:azaman/marketplace/experiences/transit/transit_experience.dart';

void main() {
  test('boarding pass exposes confirmed status before departure', () {
    final now = DateTime.now();
    final trip = TransitExperienceTrip(
      id: 't1',
      origin: 'Kumasi',
      destination: 'Accra',
      departure: now.add(const Duration(hours: 2)),
      arrival: now.add(const Duration(hours: 5)),
      availableSeats: 10,
    );
    final pass = TransitBoardingPass(
      bookingId: 'b1',
      trip: trip,
      seatIds: const ['A1'],
    );

    expect(TransitBoardingStatus.fromPass(pass).label, 'Confirmed');
  });

  test('boarding pass changes to boarding soon inside thirty minutes', () {
    final now = DateTime.now();
    final trip = TransitExperienceTrip(
      id: 't1',
      origin: 'Kumasi',
      destination: 'Accra',
      departure: now.add(const Duration(minutes: 20)),
      arrival: now.add(const Duration(hours: 3)),
      availableSeats: 10,
    );
    final pass = TransitBoardingPass(
      bookingId: 'b1',
      trip: trip,
      seatIds: const ['A1'],
    );

    expect(TransitBoardingStatus.fromPass(pass).label, 'Boarding soon');
  });
}
