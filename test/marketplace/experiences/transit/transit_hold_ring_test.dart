// =============================================================================
// AZAMAN — TASK-014 PERMANENT REGRESSION SUITE
//
// Mandated location: test/marketplace/experiences/transit/transit_hold_ring_test.dart
//
// Covers the full TASK-014 behavioural contract: the hold countdown ring and
// its timer-free ticker, the demo hold gateway, the route ribbon (entrance
// sweep genuinely driven, reduced-motion settlement, inert sold-out nodes,
// small-screen hit-target separation), the boarding-pass tear gesture, the
// deterministic barcode seed, the cabin-lighting painter contract, the
// deck-slice single-viewer invariant, and the hold-generation invalidation
// rules (corrigendum §7) at screen level.
//
// Harness discipline: every mounted ring/selector repeats a ticker or pulse,
// so NO test in this file uses pumpAndSettle — all pumps advance explicit
// durations.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/marketplace/experiences/transit/demo_transit_hold_gateway.dart';
import 'package:azaman/marketplace/experiences/transit/transit_boarding.dart';
import 'package:azaman/models/marketplace_booking_models.dart' as booking;
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/widgets/marketplace/transit_boarding_pass.dart';
import 'package:azaman/widgets/marketplace/transit_route_ribbon.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';
import 'package:azaman/widgets/seat_selector/seat_canvas_painter.dart';
import 'package:azaman/widgets/seat_selector/seat_layout_models.dart';
import 'package:azaman/widgets/seat_selector/seat_geometry_solver.dart';
import 'package:azaman/widgets/seat_selector/transit_hold_ring.dart';

// Brand colors resolved from the real palette (no invented values).
final AzamanColors _testColors = ThemeProvider.getColors(AzamanTheme.dark);

booking.TransitTrip _trip({String id = 'trip-1', int availableSeats = 10}) =>
    booking.TransitTrip(
      id: id,
      businessProfileId: 'biz-1',
      vehicleId: 'v-1',
      routeName: 'Accra - Kumasi',
      origin: 'Accra',
      destination: 'Kumasi',
      departureAt: DateTime(2026, 10, 1, 8),
      arrivalAt: DateTime(2026, 10, 1, 11),
      fareUsdc: 18,
      availableSeats: availableSeats,
      status: booking.TripStatus.scheduled,
      vehicleType: 'Coach',
    );

/// ── Screen-level harness (hold-generation regressions) ─────────────────────

booking.SeatAvailability _availability() => booking.SeatAvailability(
  tripId: 'trip-1',
  seats: List.generate(
    6,
    (i) => booking.TransitSeat(
      seatId: '${i ~/ 2 + 1}${String.fromCharCode(65 + i % 2)}',
      row: i ~/ 2,
      col: i % 2,
      type: booking.SeatType.window,
      status: booking.SeatStatus.available,
      tier: booking.SeatTier.standard,
      fare: 18,
    ),
  ),
  availableCount: 6,
  totalSeats: 6,
  tripStatus: 'scheduled',
  fareUsdc: 18,
  tierFares: const {},
);

/// A hold gateway whose results the test completes by hand: a hold is
/// "in flight" until the test completes it, which is how every stale-result
/// race is constructed deterministically.
class _ScriptedHoldGateway implements TransitHoldGateway {
  final requests = <TransitSeatSelection>[];
  final pending = <Completer<TransitHoldResult>>[];

  @override
  Future<TransitHoldResult> hold(TransitSeatSelection selection) {
    requests.add(selection);
    final completer = Completer<TransitHoldResult>();
    pending.add(completer);
    return completer.future;
  }
}

/// Booking notifier that never touches the network — the test drives state.
class _ScriptedBookingNotifier extends BookingActionNotifier {
  _ScriptedBookingNotifier() : super(MarketplaceBookingService());
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required TransitHoldGateway gateway,
  BookingActionNotifier? bookingNotifier,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final notifier = bookingNotifier ?? _ScriptedBookingNotifier();
  final container = ProviderContainer(
    overrides: [
      tripDetailProvider('trip-1').overrideWith((ref) async => _trip()),
      seatAvailabilityProvider(
        'trip-1',
      ).overrideWith((ref) async => _availability()),
      bookingActionProvider.overrideWith((ref) => notifier),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: TransitSeatSelectionScreen(
          tripId: 'trip-1',
          holdGateway: gateway,
          holdClock: clock,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _tapSeat(WidgetTester tester, String seatId) async {
  await tester.tap(
    find.bySemanticsLabel(RegExp('Seat $seatId')),
    warnIfMissed: false,
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// ── Counting haptics through the real platform channel ──────────────────────

Future<void> _recordPlatformCalls(
  WidgetTester tester,
  Future<void> Function(List<String> calls) record,
) async {
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMessageHandler(SystemChannels.platform.name, (
    ByteData? message,
  ) async {
    if (message != null) {
      try {
        // SystemChannels.platform speaks JSON, not Standard.
        // This SDK sends mediumImpact as 'HapticFeedback.vibrate' with a
        // typed argument, so record method AND args to pin the exact beat.
        final call = SystemChannels.platform.codec.decodeMethodCall(message);
        calls.add('${call.method}:${call.arguments}');
      } catch (_) {
        // Non-method traffic (e.g. Title's null-body updates): ignore.
      }
    }
    return null;
  });
  try {
    await record(calls);
  } finally {
    // Restore the channel: a leaked handler poisons every later test.
    messenger.setMockMessageHandler(SystemChannels.platform.name, null);
  }
}

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
      expect(
        transitHoldCountdownLabel(expiresAt, now: DateTime(2026, 9, 1, 8, 5)),
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
              accentColor: _testColors.accent,
              warningColor: _testColors.warning,
              dangerColor: _testColors.danger,
              trackColor: _testColors.divider,
              clock: clock,
              onExpired: () => expiredCalls++,
            ),
          ),
        );

        // The countdown is canvas-drawn: assert via the live semantics label.
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
        MaterialApp(
          home: TransitHoldRing(
            expiresAt: null,
            accentColor: _testColors.accent,
            warningColor: _testColors.warning,
            dangerColor: _testColors.danger,
            trackColor: _testColors.divider,
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

    testWidgets('threshold haptic fires exactly once at the 25% boundary', (
      tester,
    ) async {
      await _recordPlatformCalls(tester, (calls) async {
        // 5-minute window: urgency beat at 75s remaining (25%).
        var fakeNow = DateTime(2026, 9, 1, 8, 3, 40); // 80s = 26.7%
        DateTime clock() => fakeNow;

        await tester.pumpWidget(
          MaterialApp(
            home: TransitHoldRing(
              expiresAt: DateTime(2026, 9, 1, 8, 5),
              window: const Duration(minutes: 5),
              accentColor: _testColors.accent,
              warningColor: _testColors.warning,
              dangerColor: _testColors.danger,
              trackColor: _testColors.divider,
              clock: clock,
            ),
          ),
        );
        // The first tick runs strictly above the threshold: no beat yet.
        await tester.pump(const Duration(seconds: 1));
        expect(calls.where((m) => m.startsWith('HapticFeedback')), isEmpty);

        // Cross the boundary: 74s remaining = 24.7% < 25%.
        fakeNow = fakeNow.add(const Duration(seconds: 6));
        await tester.pump(const Duration(seconds: 1));
        expect(calls.where((m) => m.contains('mediumImpact')).length, 1);

        // Many more ticks past the boundary: still exactly one beat.
        for (var i = 0; i < 5; i++) {
          fakeNow = fakeNow.add(const Duration(seconds: 10));
          await tester.pump(const Duration(seconds: 10));
        }
        expect(calls.where((m) => m.contains('mediumImpact')).length, 1);
      });
    });
  });

  group('DemoTransitHoldGateway', () {
    test('returns an immediate 5-minute success (timer-free)', () async {
      const gateway = DemoTransitHoldGateway();
      final trip = transitExperienceTripFromBooking(_trip(availableSeats: 4));

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
      expect(points.first.dy, closeTo(size.height / 2, 0.001));
      expect(points.last.dy, closeTo(size.height / 2, 0.001));
      for (final p in points) {
        expect(p.dx, greaterThan(30));
        expect(p.dx, lessThan(size.width - 30));
      }
    });

    test('the single-bow invariant: monotonic x, no crossing path', () {
      const size = Size(400, 216);
      final points = transitRibbonNodePoints(size, 7);
      var previousX = -1.0;
      for (final p in points) {
        expect(p.dx, greaterThan(previousX));
        previousX = p.dx;
        expect(p.dy, greaterThanOrEqualTo(0));
        expect(p.dy, lessThanOrEqualTo(size.height));
      }
    });
  });

  group('TransitRouteRibbon entrance sweep', () {
    List<booking.TransitTrip> trips(int count) => List.generate(
      count,
      (i) => _trip(id: 'trip-$i', availableSeats: i == 1 ? 0 : 12),
    );

    TransitRibbonPathPainter installedPainter(WidgetTester tester) {
      final renderObject = tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(TransitRouteRibbon),
          matching: find.byType(CustomPaint),
        ),
      );
      return renderObject.painter! as TransitRibbonPathPainter;
    }

    testWidgets('the dash sweep is genuinely driven by the controller', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 360,
            child: TransitRouteRibbon(
              trips: trips(3),
              colors: _testColors,
              onTripTap: (_) {},
            ),
          ),
        ),
      );

      final painterBefore = installedPainter(tester);
      final valueAtFirstFrame = painterBefore.dashFlow;
      expect(valueAtFirstFrame, lessThan(1.0));

      // Mid-sweep: the painter's value must have advanced with the ticks.
      await tester.pump(const Duration(milliseconds: 250));
      final midValue = installedPainter(tester).dashFlow;
      expect(midValue, greaterThan(valueAtFirstFrame));

      // The sweep is one-shot: it settles at 1.0 and stops.
      await tester.pump(const Duration(seconds: 2));
      final painterAfter = installedPainter(tester);
      expect(painterAfter.dashFlow, 1.0);

      // No rebuild-per-tick: the ticks repainted the SAME painter through
      // its repaint listenable — a per-build CurvedAnimation would have
      // frozen the value at the first frame instead.
      expect(identical(painterAfter, painterBefore), isTrue);
    });

    testWidgets('reduced motion settles the entrance immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: SizedBox(
              width: 360,
              child: TransitRouteRibbon(
                trips: trips(3),
                colors: _testColors,
                onTripTap: (_) {},
              ),
            ),
          ),
        ),
      );

      // Duration.zero → the controller completes on its first tick.
      expect(installedPainter(tester).dashFlow, 1.0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(installedPainter(tester).dashFlow, 1.0);
    });

    testWidgets('a sold-out route node is inert', (tester) async {
      final allTrips = trips(4);
      // trips[1] is sold out by construction (availableSeats == 0).
      final soldOut = allTrips[1];
      final live = allTrips[0];

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            child: TransitRouteRibbon(
              trips: allTrips,
              colors: _testColors,
              onTripTap: (_) {},
            ),
          ),
        ),
      );

      // Tapping the sold-out node must NOT expand a detail card.
      await tester.tap(find.byKey(ValueKey('ribbon-node-${soldOut.id}')));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Kumasi'), findsNothing);

      // Control: tapping a live node expands it (same gesture, live node).
      await tester.tap(find.byKey(ValueKey('ribbon-node-${live.id}')));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Kumasi'), findsOneWidget);
    });

    testWidgets('six trips on a 360dp screen: node hit boxes never overlap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 360,
            child: TransitRouteRibbon(
              trips: trips(6),
              colors: _testColors,
              onTripTap: (_) {},
            ),
          ),
        ),
      );

      final rects = <Rect>[];
      for (var i = 0; i < 6; i++) {
        rects.add(tester.getRect(find.byKey(ValueKey('ribbon-node-trip-$i'))));
      }
      rects.sort((a, b) => a.left.compareTo(b.left));

      for (var i = 0; i < 5; i++) {
        // Adjacent hit boxes may touch at most; they must not overlap.
        expect(rects[i].right, lessThanOrEqualTo(rects[i + 1].left + 0.01));
        // Every departure keeps a reachable, Material-minimum tap target.
        expect(rects[i].width, greaterThanOrEqualTo(44));
      }
    });
  });

  group('TransitBoardingPassCard keepsake', () {
    TransitBoardingPass pass() => TransitBoardingPass(
      bookingId: 'bk-7f3a',
      trip: transitExperienceTripFromBooking(_trip()),
      seatIds: const ['1A'],
      boardingTime: DateTime(2026, 10, 1, 7, 40),
    );

    Widget host() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: TransitBoardingPassCard(pass: pass(), colors: _testColors),
        ),
      ),
    );

    // The pass runs a live 1-second status ticker: fixed pumps only.
    testWidgets('a short tear snaps back to the closed state', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 50));

      final stubText = find.text('KEEP THIS STUB');
      final closedTop = tester.getTopLeft(stubText);

      // A 30px pull: below the 45px commit point.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('AZAMAN TRANSIT')),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      // Snapped shut: the stub is back where it started, still visible.
      expect(tester.getTopLeft(stubText), closedTop);
      expect(stubText, findsOneWidget);
    });

    testWidgets('a committed tear completes exactly once', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 50));

      // Pull past the commit point and release.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('AZAMAN TRANSIT')),
      );
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();

      // Pump through the tear animation (MotionTokens.standard = 220ms).
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 300));

      // The stub is gone — the pass stays open.
      expect(find.text('KEEP THIS STUB'), findsNothing);
      expect(find.text('AZAMAN TRANSIT'), findsNothing);

      // Still open after more frames: the tear does not replay or regress.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('KEEP THIS STUB'), findsNothing);
    });
  });

  group('deterministic barcode seed', () {
    test('stable for the same booking id, distinct across ids', () {
      expect(transitBarcodeSeed('bk-7f3a'), transitBarcodeSeed('bk-7f3a'));
      expect(
        transitBarcodeSeed('bk-7f3a'),
        isNot(transitBarcodeSeed('bk-7f3b')),
      );
      // NOT the unstable String.hashCode path.
      expect(transitBarcodeSeed('bk-7f3a'), isNot('bk-7f3a'.hashCode));
    });
  });

  group('SeatCanvasPainter cabin lighting', () {
    const layout = VehicleLayout(
      id: 'light-test',
      vehicleType: 'COACH',
      decks: [
        Deck(
          deckIndex: 0,
          label: 'Main',
          grid: [
            [
              GridSlot(
                type: SlotType.seat,
                row: 0,
                col: 0,
                seatId: '1A',
                tier: SeatTier.vip,
                fare: 30,
              ),
              GridSlot(
                type: SlotType.seat,
                row: 0,
                col: 1,
                seatId: '1B',
                fare: 18,
              ),
            ],
          ],
        ),
      ],
    );

    Future<Uint8List> paint(CabinLighting? lighting) async {
      final geometry = const SeatGeometrySolver().compute(layout);
      final painter = SeatCanvasPainter(
        geometry: geometry,
        iconCache: const SeatIconCache(),
        selectedSeats: const <String>{},
        hullStyle: const HullStyle(
          bodyColor: Color(0xFF888888),
          borderColor: Color(0xFF444444),
        ),
        accentColor: _testColors.accent,
        selectionPulse: 0,
        currentDeck: 0,
        cabinLighting: lighting,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), geometry.totalBounds.size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        geometry.totalBounds.width.ceil().clamp(1, 512),
        geometry.totalBounds.height.ceil().clamp(1, 512),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return Uint8List.view(data!.buffer);
    }

    test(
      'CabinLighting == null preserves the legacy (un-lit) painter path',
      () async {
        final legacy = await paint(null);
        final legacyAgain = await paint(null);
        final lit = await paint(const CabinLighting());

        // Legacy path is deterministic: identical for the same inputs.
        expect(legacy, equals(legacyAgain));
        // The lighting pass is purely additive — it visibly changes output,
        // so the null path is genuinely the pre-TASK-014 rendering.
        expect(legacy, isNot(equals(lit)));
      },
    );
  });

  group('deck-slice invariant', () {
    testWidgets(
      'switching decks keeps exactly one InteractiveViewer and one shared '
      'TransformationController',
      (tester) async {
        const multiDeck = VehicleLayout(
          id: 'deck-test',
          vehicleType: 'COACH',
          decks: [
            Deck(
              deckIndex: 0,
              label: 'Lower',
              grid: [
                [
                  GridSlot(
                    type: SlotType.seat,
                    row: 0,
                    col: 0,
                    seatId: '1A',
                    fare: 18,
                  ),
                  GridSlot(
                    type: SlotType.seat,
                    row: 0,
                    col: 1,
                    seatId: '1B',
                    fare: 18,
                  ),
                ],
              ],
            ),
            Deck(
              deckIndex: 1,
              label: 'Upper',
              grid: [
                [
                  GridSlot(
                    type: SlotType.seat,
                    row: 0,
                    col: 0,
                    seatId: '2A',
                    fare: 18,
                  ),
                  GridSlot(
                    type: SlotType.seat,
                    row: 0,
                    col: 1,
                    seatId: '2B',
                    fare: 18,
                  ),
                ],
              ],
            ),
          ],
        );

        final controller = SeatSelectorController();
        controller.loadLayout(multiDeck);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BusSeatSelector(
                layout: multiDeck,
                controller: controller,
                accentColor: _testColors.accent,
                surfaceColor: _testColors.surface,
                cardColor: _testColors.card,
                dividerColor: _testColors.divider,
                textPrimary: _testColors.textPrimary,
                textSecondary: _testColors.textSecondary,
                textTertiary: _testColors.textTertiary,
                successColor: _testColors.success,
                dangerColor: _testColors.danger,
                backgroundColor: _testColors.background,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        TransformationController viewerController() => tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!;

        expect(find.byType(InteractiveViewer), findsOneWidget);
        final before = viewerController();

        // Switch deck — mid-animation is where a second viewer would appear
        // if an AnimatedSwitcher had been used.
        await tester.tap(find.text('Upper'));
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(identical(viewerController(), before), isTrue);

        // Post-animation: still one viewer, same controller, deck switched.
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(identical(viewerController(), before), isTrue);
        expect(controller.currentDeck, 1);
      },
    );
  });

  group('hold-generation invalidation (corrigendum §7)', () {
    testWidgets('a hold resolving after deselection never reappears', (
      tester,
    ) async {
      final gateway = _ScriptedHoldGateway();
      await _pumpScreen(tester, gateway: gateway);

      await _tapSeat(tester, '1A'); // generation 1, hold A in flight
      expect(gateway.pending, hasLength(1));

      await _tapSeat(tester, '1A'); // deselect → generation 2, empty
      expect(gateway.pending, hasLength(1)); // no new hold on empty

      // The stale generation-1 result arrives late.
      gateway.pending[0].complete(
        TransitHoldSuccess(
          holdId: 'stale-a',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Re-select: the stale hold must NOT install itself for the new
      // selection — the ring appears only when generation 3 resolves.
      await _tapSeat(tester, '1A'); // generation 3
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsNothing);

      gateway.pending[1].complete(
        TransitHoldSuccess(
          holdId: 'fresh-3',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsOneWidget);
    });

    testWidgets('a hold for selection A cannot replace selection B', (
      tester,
    ) async {
      final gateway = _ScriptedHoldGateway();
      await _pumpScreen(tester, gateway: gateway);

      await _tapSeat(tester, '1A'); // generation 1, hold A in flight
      await _tapSeat(tester, '1B'); // generation 2, hold B in flight

      // A's result arrives late — B is what the user is looking at.
      gateway.pending[0].complete(
        TransitHoldSuccess(
          holdId: 'stale-a',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsNothing);

      // B's result installs normally.
      gateway.pending[1].complete(
        TransitHoldSuccess(
          holdId: 'fresh-b',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsOneWidget);
    });

    testWidgets('an old expiry callback cannot clear a newer selection', (
      tester,
    ) async {
      final gateway = _ScriptedHoldGateway();
      var fakeNow = DateTime(2026, 9, 29, 12, 0);
      DateTime clock() => fakeNow;
      await _pumpScreen(tester, gateway: gateway, clock: clock);

      // Selection A installs a hold and shows the ring.
      await _tapSeat(tester, '1A');
      gateway.pending[0].complete(
        TransitHoldSuccess(
          holdId: 'hold-a',
          expiresAt: fakeNow.add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsOneWidget);

      // Capture generation-A's expiry closure — the exact callback the old
      // ring would fire when it expires.
      final staleExpiry = tester
          .widget<TransitHoldRing>(find.byType(TransitHoldRing))
          .onExpired!;

      // Selection B: generation 2, hold B installs.
      await _tapSeat(tester, '1B');
      gateway.pending[1].complete(
        TransitHoldSuccess(
          holdId: 'hold-b',
          expiresAt: fakeNow.add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsOneWidget);

      // The stale generation-A expiry executes late.
      staleExpiry();
      await tester.pump(const Duration(milliseconds: 50));

      // B's hold and the {1A,1B} selection must survive.
      expect(find.byType(TransitHoldRing), findsOneWidget);
      expect(find.text('1A'), findsOneWidget);
      expect(find.text('1B'), findsOneWidget);
      expect(
        find.text('Seat hold expired — select your seats again.'),
        findsNothing,
      );
    });

    testWidgets('a hold resolving after successful booking never re-arms', (
      tester,
    ) async {
      final gateway = _ScriptedHoldGateway();
      final notifier = _ScriptedBookingNotifier();
      await _pumpScreen(tester, gateway: gateway, bookingNotifier: notifier);

      // Seat 1A selected and held (generation 1).
      await _tapSeat(tester, '1A');
      gateway.pending[0].complete(
        TransitHoldSuccess(
          holdId: 'hold-1',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TransitHoldRing), findsOneWidget);

      // A second selection starts a new in-flight hold (generation 2)...
      await _tapSeat(tester, '1B');
      expect(gateway.pending, hasLength(2));

      // ...then the booking succeeds, invalidating all generations.
      notifier.state = const BookingActionState(
        result: booking.BookSeatResult(
          success: true,
          bookingId: 'bk-1',
          bookingRef: 'REF-9F2',
          seatIds: ['1A'],
          totalFare: 18,
          status: 'confirmed',
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // The in-flight generation-2 hold resolves after the booking:
      // it must not re-arm the ring.
      gateway.pending[1].complete(
        TransitHoldSuccess(
          holdId: 'post-booking',
          expiresAt: DateTime.now().add(transitHoldWindow),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TransitHoldRing), findsNothing);
      // The booking cleared the selection: the dock (and its chip row)
      // is gone; only the success sheet's keepsake remains.
      expect(find.text('Names'), findsNothing);

      // The success sheet staggers its rows in via Future.delayed
      // (MotionTokens stagger, max 300ms): flush every pending delay so
      // teardown sees no live timer.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
