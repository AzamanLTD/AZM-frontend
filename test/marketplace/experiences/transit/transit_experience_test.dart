import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/transit/transit_experience.dart';

class _Gateway implements TransitHoldGateway {
  TransitSeatSelection? received;
  @override
  Future<TransitHoldResult> hold(TransitSeatSelection selection) async {
    received = selection;
    return TransitHoldSuccess(
      holdId: 'h1',
      expiresAt: DateTime(2026, 9, 1, 10),
    );
  }
}

void main() {
  final trip = TransitTrip(
    id: 't1',
    origin: 'Kumasi',
    destination: 'Accra',
    departure: DateTime(2026, 9, 1, 8),
    arrival: DateTime(2026, 9, 1, 11),
    availableSeats: 3,
  );

  test('rejects empty seat selection', () async {
    final gateway = _Gateway();
    final result = await TransitHoldController(gateway).hold(
      TransitSeatSelection(trip: trip, seatIds: const []),
    );
    expect(result, isA<TransitHoldFailure>());
    expect(gateway.received, isNull);
  });

  test('rejects selection larger than availability', () async {
    final gateway = _Gateway();
    final result = await TransitHoldController(gateway).hold(
      TransitSeatSelection(trip: trip, seatIds: const ['1', '2', '3', '4']),
    );
    expect(result, isA<TransitHoldFailure>());
  });

  test('passes valid seats to gateway', () async {
    final gateway = _Gateway();
    final result = await TransitHoldController(gateway).hold(
      TransitSeatSelection(trip: trip, seatIds: const ['1', '2']),
    );
    expect(result, isA<TransitHoldSuccess>());
    expect(gateway.received?.seatIds, ['1', '2']);
  });
}
