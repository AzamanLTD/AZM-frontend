import 'transit_experience.dart';

class TransitBoardingPass {
  final String bookingId;
  final TransitTrip trip;
  final List<String> seatIds;
  final DateTime? boardingTime;

  const TransitBoardingPass({
    required this.bookingId,
    required this.trip,
    required this.seatIds,
    this.boardingTime,
  });

  Duration? get timeToDeparture => trip.departure.difference(DateTime.now());
  bool get departed => !trip.departure.isAfter(DateTime.now());
}

class TransitBoardingStatus {
  final String label;
  final bool actionable;
  const TransitBoardingStatus(this.label, this.actionable);

  factory TransitBoardingStatus.fromPass(TransitBoardingPass pass) {
    final remaining = pass.timeToDeparture;
    if (remaining == null || remaining.isNegative) {
      return const TransitBoardingStatus('Departed', false);
    }
    if (remaining.inMinutes <= 30) {
      return const TransitBoardingStatus('Boarding soon', true);
    }
    return const TransitBoardingStatus('Confirmed', true);
  }
}
