// The transit booking says what the backend does. `POST .../book` creates a
// PENDING reservation and charges nothing, so the dock offers "Reserve", shows
// no booking fee and says no charge is taken; a pending result is "Seats
// reserved" with no boarding pass. And the seat map, which refits when the
// dock arrives, keeps the passenger's seat in view.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/widgets/marketplace/transit_boarding_pass.dart';

import '../../support/money_access_test_support.dart';

TransitTrip _trip() => TransitTrip(
      id: 'trip-1',
      businessProfileId: 'b1',
      vehicleId: 'v1',
      routeName: 'Circle - Madina',
      origin: 'Circle',
      destination: 'Madina',
      departureAt: DateTime(2026, 12, 1, 7, 30),
      fareUsdc: 0.6,
      availableSeats: 16,
      status: TripStatus.scheduled,
      vehicleType: 'Trotro',
    );

SeatAvailability _availability() {
  final seats = <TransitSeat>[
    for (var r = 1; r <= 4; r++)
      for (var c = 1; c <= 4; c++)
        TransitSeat(
          seatId: '$r${String.fromCharCode(64 + c)}',
          row: r,
          col: c,
          type: SeatType.window,
          status: SeatStatus.available,
          fare: 0.6,
        ),
  ];
  return SeatAvailability(
    tripId: 'trip-1',
    seats: seats,
    availableCount: seats.length,
    totalSeats: seats.length,
    tripStatus: 'SCHEDULED',
    fareUsdc: 0.6,
  );
}

// Real metrics: the app theme (Inter) with Inter loaded, so layout is judged
// as a phone renders it, not in the test font's square glyphs.
bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  for (final (family, path) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf'),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)
          ..addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer))))
        .load();
  }
  _fontsLoaded = true;
}

class _ScriptedBookingNotifier extends BookingActionNotifier {
  _ScriptedBookingNotifier() : super(MarketplaceBookingService());
}

Future<_ScriptedBookingNotifier> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(360, 780) * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadFonts);
  final notifier = _ScriptedBookingNotifier();
  final container = ProviderContainer(overrides: [
    unlockedMoneyAccess(),
    tripDetailProvider('trip-1').overrideWith((ref) async => _trip()),
    seatAvailabilityProvider('trip-1').overrideWith((ref) async => _availability()),
    bookingActionProvider.overrideWith((ref) => notifier),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.light),
      home: const TransitSeatSelectionScreen(tripId: 'trip-1'),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return notifier;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the dock reserves, shows no fee and says nothing is charged', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Seat 1A,')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('transit-booking-dock')), findsOneWidget);
    expect(find.text('Reserve 1 seat'), findsOneWidget);
    expect(find.textContaining('Booking fee'), findsOneWidget);
    expect(find.textContaining('None'), findsOneWidget);
    expect(find.text(r'$0.60 USDC'), findsOneWidget);
    expect(
      find.text('No charge now. The operator confirms your seats.'),
      findsOneWidget,
    );
    // The fare is never rounded up to a whole unit.
    expect(find.text(r'$0.60'), findsOneWidget); // the trip strip
    expect(find.textContaining(r'$1'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a pending booking is "Seats reserved", with no boarding pass', (tester) async {
    final notifier = await _pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Seat 1A,')));
    await _settle(tester);

    notifier.state = const BookingActionState(
      result: BookSeatResult(
        success: true,
        bookingId: 'bk-1',
        bookingRef: 'TRN-1',
        seatIds: ['1A'],
        totalFare: 0.6,
        status: 'PENDING',
      ),
    );
    await _settle(tester);

    expect(find.text('Seats reserved'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsNothing);
    expect(
      find.text('The operator confirms your seats. No charge has been taken.'),
      findsOneWidget,
    );
    expect(find.byType(TransitBoardingPassCard), findsNothing);
    expect(find.text('Total Paid'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a confirmed booking keeps the boarding pass', (tester) async {
    final notifier = await _pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Seat 1A,')));
    await _settle(tester);

    notifier.state = const BookingActionState(
      result: BookSeatResult(
        success: true,
        bookingId: 'bk-2',
        bookingRef: 'TRN-2',
        seatIds: ['1A'],
        totalFare: 0.6,
        status: 'CONFIRMED',
      ),
    );
    await _settle(tester);

    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.byType(TransitBoardingPassCard), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a seat chosen near the back stays in view when the dock arrives', (tester) async {
    await _pump(tester);
    // Scroll-free: the fourth row is reachable at the opening fit.
    final seat = find.bySemanticsLabel(RegExp(r'^Seat 3B,'));
    await tester.tap(seat);
    await _settle(tester);

    final viewer = tester.getRect(find.byType(InteractiveViewer));
    final rect = tester.getRect(seat);
    expect(rect.top, greaterThanOrEqualTo(viewer.top));
    expect(rect.bottom, lessThanOrEqualTo(viewer.bottom));
    await _unmount(tester);
  });

  testWidgets('the cab is announced: driver and mate, neither bookable', (tester) async {
    await _pump(tester);
    expect(find.bySemanticsLabel('Driver'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mate, crew seat')), findsOneWidget);
    await _unmount(tester);
  });
}
