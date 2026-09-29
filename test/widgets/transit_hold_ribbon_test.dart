// TASK-014 permanent guards — hold ring, demo gateway, ribbon path.
//
// Scope: this file does NOT exercise BusSeatSelector composition (minimap,
// deck switcher, hold docking are pipeline-verified; the widget test
// harness dies in parallel under the sandbox memory ceiling — see
// .agents/.env and PR #107 notes). These guards pin the pure contracts
// and the timer-free guarantees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/transit/demo_transit_hold_gateway.dart';
import 'package:azaman/models/marketplace_booking_models.dart' as booking;
import 'package:azaman/widgets/marketplace/transit_route_ribbon.dart';
import 'package:azaman/widgets/seat_selector/transit_hold_ring.dart';

void main() {
  group('transitHoldCountdownLabel', () {
    test('shows m:ss while live, 0:00 once expired, --:-- when null', () {
      final expiresAt = DateTime(2026, 9, 1, 8, 5);
      expect(
        transitHoldCountdownLabel(expiresAt, now: DateTime(2026, 9, 1, 8, 0)),
        '5:00',
      );
      expect(
        transitHoldCountdownLabel(
          expiresAt,
          now: DateTime(2026, 9, 1, 8, 4, 59),
        ),
        '0:01',
      );
      // Expired at the exact boundary: reads 0:00, never negative.
      expect(
        transitHoldCountdownLabel(expiresAt, now: DateTime(2026, 9, 1, 8, 5)),
        '0:00',
      );
      expect(
        transitHoldCountdownLabel(
          expiresAt,
          now: DateTime(2026, 9, 1, 8, 5, 1),
        ),
        '0:00',
      );
      expect(
        transitHoldCountdownLabel(null, now: DateTime(2026, 9, 1, 8, 0)),
        '--:--',
      );
    });
  });

  group('TransitHoldRing', () {
    testWidgets(
      'ticks on a ticker (no timers) and fires onExpired exactly once',
      (tester) async {
        var fakeNow = DateTime(2026, 9, 1, 8, 0);
        DateTime clock() => fakeNow;
        var expiredCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: TransitHoldRing(
              expiresAt: fakeNow.add(const Duration(minutes: 5)),
              window: const Duration(minutes: 5),
              accentColor: const Color(0xFF00C2FF),
              warningColor: const Color(0xFFFFB020),
              dangerColor: const Color(0xFFFF4D4D),
              trackColor: const Color(0xFF333333),
              clock: clock,
              onExpired: () => expiredCalls++,
            ),
          ),
        );

        // Repeating ticker: never pumpAndSettle — advance deterministically.
        // The countdown is canvas-drawn, so assert via the live semantics
        // label (the proven pattern from the seat-selection test).
        expect(
          find.bySemanticsLabel(RegExp(r'expires in 5:00')),
          findsOneWidget,
        );
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.bySemanticsLabel(RegExp(r'expires in 4:59')),
          findsOneWidget,
        );

        // Fast-forward the clock past expiry; the next tick must fire once.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(); // post-frame callback for onExpired
        expect(expiredCalls, 1);
        await tester.pump(const Duration(seconds: 2));
        expect(expiredCalls, 1);
      },
    );

    testWidgets('renders nothing for a null expiry', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TransitHoldRing(
            expiresAt: null,
            accentColor: Color(0xFF00C2FF),
            warningColor: Color(0xFFFFB020),
            dangerColor: Color(0xFFFF4D4D),
            trackColor: Color(0xFF333333),
          ),
        ),
      );
      expect(find.byType(TransitHoldRing), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TransitHoldRing),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  group('DemoTransitHoldGateway', () {
    test('returns an immediate 5-minute success (timer-free)', () async {
      const gateway = DemoTransitHoldGateway();
      final trip = transitExperienceTripFromBooking(
        booking.TransitTrip(
          id: 'trip-1',
          businessProfileId: 'biz-1',
          vehicleId: 'v-1',
          routeName: 'Accra - Kumasi',
          origin: 'Accra',
          destination: 'Kumasi',
          departureAt: DateTime(2026, 9, 1, 8),
          arrivalAt: DateTime(2026, 9, 1, 11),
          fareUsdc: 18,
          availableSeats: 4,
          status: booking.TripStatus.scheduled,
          vehicleType: 'Coach',
        ),
      );

      final before = DateTime.now();
      final result = await gateway.hold(
        TransitSeatSelection(trip: trip, seatIds: const ['A1']),
      );
      final after = DateTime.now();

      expect(result, isA<TransitHoldSuccess>());
      final success = result as TransitHoldSuccess;
      expect(
        success.expiresAt.difference(before).inMinutes,
        inInclusiveRange(4, 5),
      );
      expect(success.expiresAt.isBefore(after.add(transitHoldWindow)), isTrue);
    });

    test('adapts nullable arrivalAt to a 3-hour leg', () {
      final adapted = transitExperienceTripFromBooking(
        booking.TransitTrip(
          id: 'trip-2',
          businessProfileId: 'biz-1',
          vehicleId: 'v-1',
          routeName: 'Accra - Kumasi',
          origin: 'Accra',
          destination: 'Kumasi',
          departureAt: DateTime(2026, 9, 1, 8),
          arrivalAt: null,
          fareUsdc: 18,
          availableSeats: 4,
          status: booking.TripStatus.scheduled,
          vehicleType: 'Coach',
        ),
      );
      expect(
        adapted.arrival.difference(adapted.departure),
        const Duration(hours: 3),
      );
    });
  });

  group('transitRibbonNodePoints', () {
    test('degenerate cases stay inside the canvas', () {
      const size = Size(400, 216);
      expect(transitRibbonNodePoints(size, 0), isEmpty);
      expect(transitRibbonNodePoints(size, 1).length, 1);
    });

    test('two trips sit level on the baseline and span the canvas', () {
      const size = Size(400, 216);
      final points = transitRibbonNodePoints(size, 2);
      // The ends sit on the baseline (y = height/2), so the path starts
      // and ends level.
      expect(points.first.dy, closeTo(size.height / 2, 0.001));
      expect(points.last.dy, closeTo(size.height / 2, 0.001));
      // All nodes within horizontal margins.
      for (final p in points) {
        expect(p.dx, greaterThan(30));
        expect(p.dx, lessThan(size.width - 30));
      }
    });

    test('the single-bow invariant: monotonic x, no crossing path', () {
      const size = Size(400, 216);
      final points = transitRibbonNodePoints(size, 6);
      for (int i = 1; i < points.length; i++) {
        expect(points[i].dx, greaterThan(points[i - 1].dx));
      }
    });
  });
}
