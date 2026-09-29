// =============================================================================
// AZAMAN — DEMO TRANSIT HOLD GATEWAY (TASK-014)
//
// Screen-local stand-in for the backend seat-hold endpoint. The hold contract
// (TransitHoldGateway) exists in the experience models; this gateway returns
// an immediate 5-minute success so the seat-selection screen can show the
// draining hold ring today.
//
// Two constraints shape this file:
//   1. It must be timer-free. A Future.delayed or Timer here would leak a
//      pending timer into widget tests (the framework fails the test).
//      Future.value completes on a microtask — nothing pending.
//   2. It must never throw. The in-app UX treats a hold failure as a
//      selection-side concern (snackbar + retry on the next selection
//      change), so the demo gateway always succeeds.
//
// Backend integration (a real HTTP hold + release) is a follow-up: the
// gateway contract has no release(), and wiring one belongs to the services
// layer, which this programme does not touch.
// =============================================================================

import 'package:azaman/marketplace/experiences/transit/transit_experience.dart';
// Re-export the hold contract so callers importing this gateway get the
// result types (TransitSeatSelection, TransitHoldSuccess, ...) in one import.
export 'package:azaman/marketplace/experiences/transit/transit_experience.dart';
import 'package:azaman/models/marketplace_booking_models.dart' as booking;

/// The full hold window the demo gateway grants and the hold ring renders.
const Duration transitHoldWindow = Duration(minutes: 5);

/// Timer-free demo hold gateway. See file header.
class DemoTransitHoldGateway implements TransitHoldGateway {
  const DemoTransitHoldGateway();

  @override
  Future<TransitHoldResult> hold(TransitSeatSelection selection) {
    return Future<TransitHoldResult>.value(
      TransitHoldSuccess(
        holdId: 'demo-${selection.trip.id}-${selection.seatIds.length}',
        expiresAt: DateTime.now().add(transitHoldWindow),
      ),
    );
  }
}

/// Adapts the booking-flow [booking.TransitTrip] to the experience-model
/// [TransitExperienceTrip] the hold/boarding contracts speak.
///
/// The booking model's `arrivalAt` is nullable; the experience model requires
/// an arrival strictly after departure (the hold controller validates this).
/// When the backend omits an arrival, fall back to a 3-hour leg — a
/// conservative default for Ghanaian inter-city coaches. The booking model
/// has no operator field; the driver name is the closest semantic match.
TransitExperienceTrip transitExperienceTripFromBooking(
  booking.TransitTrip trip,
) {
  return TransitExperienceTrip(
    id: trip.id,
    origin: trip.origin,
    destination: trip.destination,
    departure: trip.departureAt,
    arrival: trip.arrivalAt ?? trip.departureAt.add(const Duration(hours: 3)),
    operatorName: trip.driverName,
    vehicleType: trip.vehicleType,
    fare: trip.fareUsdc,
    currency: 'USDC',
    availableSeats: trip.availableSeats,
  );
}
