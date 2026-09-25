import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/hotel/hotel_booking.dart';
import 'package:azaman/marketplace/experiences/hotel/hotel_experience.dart';

class _Gateway implements HotelBookingGateway {
  HotelStay? received;
  @override
  Future<HotelBookingResult> book(HotelStay stay) async {
    received = stay;
    return const HotelBookingSuccess(reservationId: 'r1');
  }
}

void main() {
  final room = HotelRoom(
    id: '101',
    name: 'Deluxe Room',
    nightlyRate: 500,
    currency: 'GHS',
    capacity: 2,
  );

  test('rejects invalid date range', () async {
    final gateway = _Gateway();
    final result = await HotelBookingController(gateway).submit(HotelStay(
      checkIn: DateTime(2026, 9, 10),
      checkOut: DateTime(2026, 9, 10),
      guests: 1,
      room: room,
    ));
    expect(result, isA<HotelBookingFailure>());
    expect(gateway.received, isNull);
  });

  test('rejects capacity overflow', () async {
    final gateway = _Gateway();
    final result = await HotelBookingController(gateway).submit(HotelStay(
      checkIn: DateTime(2026, 9, 10),
      checkOut: DateTime(2026, 9, 12),
      guests: 3,
      room: room,
    ));
    expect(result, isA<HotelBookingFailure>());
    expect(gateway.received, isNull);
  });

  test('passes valid stay to booking gateway', () async {
    final gateway = _Gateway();
    final stay = HotelStay(
      checkIn: DateTime(2026, 9, 10),
      checkOut: DateTime(2026, 9, 12),
      guests: 2,
      room: room,
    );
    final result = await HotelBookingController(gateway).submit(stay);
    expect(result, isA<HotelBookingSuccess>());
    expect(gateway.received?.nights, 2);
  });
}
