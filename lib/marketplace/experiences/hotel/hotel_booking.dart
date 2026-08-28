import 'hotel_experience.dart';

class HotelStay {
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final HotelRoom room;

  const HotelStay({
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.room,
  });

  int get nights => checkOut.difference(checkIn).inDays;
}

abstract class HotelBookingGateway {
  Future<HotelBookingResult> book(HotelStay stay);
}

sealed class HotelBookingResult {
  const HotelBookingResult();
}

class HotelBookingSuccess extends HotelBookingResult {
  final String reservationId;
  final String? confirmationMessage;

  const HotelBookingSuccess({
    required this.reservationId,
    this.confirmationMessage,
  });
}

class HotelBookingFailure extends HotelBookingResult {
  final String message;
  final bool retryable;

  const HotelBookingFailure({required this.message, this.retryable = true});
}

class HotelBookingController {
  final HotelBookingGateway gateway;

  const HotelBookingController(this.gateway);

  Future<HotelBookingResult> submit(HotelStay stay) async {
    if (!stay.checkOut.isAfter(stay.checkIn)) {
      return const HotelBookingFailure(
        message: 'Check-out must be after check-in.',
        retryable: false,
      );
    }
    if (stay.guests < 1) {
      return const HotelBookingFailure(
        message: 'At least one guest is required.',
        retryable: false,
      );
    }
    if (!stay.room.available) {
      return const HotelBookingFailure(
        message: 'This room is no longer available.',
        retryable: false,
      );
    }
    if (stay.room.capacity != null && stay.guests > stay.room.capacity!) {
      return const HotelBookingFailure(
        message: 'This room cannot accommodate the selected guests.',
        retryable: false,
      );
    }
    return gateway.book(stay);
  }
}
