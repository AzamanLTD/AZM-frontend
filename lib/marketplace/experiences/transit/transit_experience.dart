class TransitTrip {
  final String id;
  final String origin;
  final String destination;
  final DateTime departure;
  final DateTime arrival;
  final String? operatorName;
  final String? vehicleType;
  final double? fare;
  final String? currency;
  final int availableSeats;

  const TransitTrip({
    required this.id,
    required this.origin,
    required this.destination,
    required this.departure,
    required this.arrival,
    this.operatorName,
    this.vehicleType,
    this.fare,
    this.currency,
    this.availableSeats = 0,
  });

  factory TransitTrip.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) => DateTime.tryParse(value?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return TransitTrip(
      id: (json['id'] ?? json['tripId'] ?? '').toString(),
      origin: (json['origin'] ?? json['from'] ?? '').toString(),
      destination: (json['destination'] ?? json['to'] ?? '').toString(),
      departure: parseDate(json['departure']),
      arrival: parseDate(json['arrival']),
      operatorName: json['operatorName']?.toString(),
      vehicleType: json['vehicleType']?.toString(),
      fare: json['fare'] is num ? (json['fare'] as num).toDouble() : double.tryParse('${json['fare'] ?? ''}'),
      currency: json['currency']?.toString(),
      availableSeats: int.tryParse('${json['availableSeats'] ?? 0}') ?? 0,
    );
  }
}

class TransitSeatSelection {
  final TransitTrip trip;
  final List<String> seatIds;

  const TransitSeatSelection({required this.trip, required this.seatIds});
}

abstract class TransitHoldGateway {
  Future<TransitHoldResult> hold(TransitSeatSelection selection);
}

sealed class TransitHoldResult { const TransitHoldResult(); }

class TransitHoldSuccess extends TransitHoldResult {
  final String holdId;
  final DateTime expiresAt;
  const TransitHoldSuccess({required this.holdId, required this.expiresAt});
}

class TransitHoldFailure extends TransitHoldResult {
  final String message;
  final bool retryable;
  const TransitHoldFailure({required this.message, this.retryable = true});
}

class TransitHoldController {
  final TransitHoldGateway gateway;
  const TransitHoldController(this.gateway);

  Future<TransitHoldResult> hold(TransitSeatSelection selection) async {
    if (selection.trip.id.isEmpty) {
      return const TransitHoldFailure(message: 'Trip information is missing.', retryable: false);
    }
    if (selection.seatIds.isEmpty) {
      return const TransitHoldFailure(message: 'Select at least one seat.', retryable: false);
    }
    if (selection.seatIds.length > selection.trip.availableSeats) {
      return const TransitHoldFailure(message: 'Not enough seats are available.', retryable: false);
    }
    if (!selection.trip.arrival.isAfter(selection.trip.departure)) {
      return const TransitHoldFailure(message: 'This trip has invalid schedule data.', retryable: false);
    }
    return gateway.hold(selection);
  }
}
