// The transit dock says what the backend does. Pay books AND pays from the
// wallet in one transaction (payWith: WALLET), so the dock shows the server's
// quote (fare, Azaman fee, total, the wallet), offers Pay when the wallet
// covers it and Add money when it does not, and sends the second factor with
// the payment. A paid result is "Booking confirmed" with the boarding pass and
// what left the wallet; a pending one is "Seats reserved" with no pass. And
// the seat map, which refits when the dock arrives, keeps the passenger's seat
// in view.
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
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/widgets/marketplace/transit_boarding_pass.dart';
import 'package:azaman/widgets/security/second_factor.dart';

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
    await (FontLoader(family)..addFont(
          Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(bytes).buffer),
          ),
        ))
        .load();
  }
  _fontsLoaded = true;
}

/// Prices from a script and records the pay call (no network).
class _FakeService extends MarketplaceBookingService {
  _FakeService(this.quote);
  TransitPaymentQuote quote;
  final payCalls =
      <
        ({
          List<String> seats,
          bool payWithWallet,
          SecondFactor? factor,
          double? expectedTotal,
        })
      >[];
  Object? payError;
  String payStatus = 'CONFIRMED';

  @override
  Future<TransitPaymentQuote> quoteSeats({
    required String tripId,
    required List<String> seatIds,
  }) async => quote;

  @override
  Future<BookSeatResult> bookSeats({
    required String tripId,
    required List<String> seatIds,
    List<String>? passengerNames,
    String? customerNote,
    String? businessProfileId,
    String? operationType,
    FinancialOperationRef? ref,
    bool payWithWallet = false,
    SecondFactor? secondFactor,
    double? expectedTotalUsdc,
  }) async {
    payCalls.add((
      seats: seatIds,
      payWithWallet: payWithWallet,
      factor: secondFactor,
      expectedTotal: expectedTotalUsdc,
    ));
    if (payError != null) throw payError!;
    return BookSeatResult(
      success: true,
      bookingId: 'bk-1',
      bookingRef: 'TRN-1',
      seatIds: seatIds,
      totalFare: quote.fareUsdc,
      status: payStatus,
      paidTotalUsdc: quote.totalUsdc,
      paidFeeUsdc: quote.feeUsdc,
    );
  }
}

TransitPaymentQuote _quote({double available = 50}) => TransitPaymentQuote(
  seatIds: const ['1A'],
  fareUsdc: 0.6,
  feeUsdc: 0.003,
  feePct: 0.005,
  totalUsdc: 0.603,
  availableUsdc: available,
  canPay: available >= 0.603,
);

Future<_FakeService> _pump(
  WidgetTester tester, {
  TransitPaymentQuote? quote,
  List<SecondFactorKind>? asked,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(360, 780) * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadFonts);
  final svc = _FakeService(quote ?? _quote());
  final container = ProviderContainer(
    overrides: [
      unlockedMoneyAccess(),
      tripDetailProvider('trip-1').overrideWith((ref) async => _trip()),
      seatAvailabilityProvider(
        'trip-1',
      ).overrideWith((ref) async => _availability()),
      marketplaceBookingServiceProvider.overrideWithValue(svc),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: TransitSeatSelectionScreen(
          tripId: 'trip-1',
          secondFactorPrompt: ({required kind, errorText}) async {
            asked?.add(kind);
            return const SecondFactor.password('pw');
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return svc;
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

Future<void> _pick(WidgetTester tester, String seat) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^Seat $seat,')));
  await _settle(tester);
}

void main() {
  testWidgets('the dock shows the quote: fare, Azaman fee, total, wallet', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, '1A');

    expect(find.byKey(const ValueKey('transit-booking-dock')), findsOneWidget);
    expect(find.textContaining('Azaman fee'), findsOneWidget);
    expect(find.textContaining(r'$0.003'), findsOneWidget);
    expect(find.text(r'$0.603 USDC'), findsOneWidget);
    expect(find.text(r'Pay $0.603'), findsOneWidget);
    expect(find.textContaining('From your wallet'), findsOneWidget);
    // The fare is never rounded up to a whole unit.
    expect(find.textContaining(r'$1'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('Pay sends the payment with the second factor and confirms', (
    tester,
  ) async {
    final asked = <SecondFactorKind>[];
    final svc = await _pump(tester, asked: asked);
    await _pick(tester, '1A');
    await tester.tap(find.text(r'Pay $0.603'));
    await _settle(tester);

    expect(asked, [SecondFactorKind.password]);
    expect(svc.payCalls, hasLength(1));
    expect(svc.payCalls.single.payWithWallet, isTrue);
    expect(svc.payCalls.single.factor?.toWire(), {'password': 'pw'});
    expect(svc.payCalls.single.seats, ['1A']);
    // The total the passenger saw is the total they approved.
    expect(svc.payCalls.single.expectedTotal, 0.603);

    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Paid from wallet'), findsOneWidget);
    expect(find.byType(TransitBoardingPassCard), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a wallet that cannot cover it offers Add money, not Pay', (
    tester,
  ) async {
    await _pump(tester, quote: _quote(available: 0.2));
    await _pick(tester, '1A');
    expect(find.text('Add money'), findsOneWidget);
    expect(find.textContaining(r'Pay $'), findsNothing);
    expect(find.textContaining('Your wallet has'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a short balance at pay time charges nothing and says so', (
    tester,
  ) async {
    final svc = await _pump(tester);
    svc.payError = ApiException(
      message: 'Insufficient balance.',
      statusCode: 402,
      code: 'INSUFFICIENT_BALANCE',
    );
    await _pick(tester, '1A');
    await tester.tap(find.text(r'Pay $0.603'));
    await _settle(tester);
    expect(
      find.text('Your wallet does not cover this yet. Nothing was charged.'),
      findsOneWidget,
    );
    expect(find.text('Booking confirmed'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a price change since the quote charges nothing and says so', (
    tester,
  ) async {
    final svc = await _pump(tester);
    svc.payError = ApiException(
      message: 'The price changed.',
      statusCode: 409,
      code: 'PRICE_CHANGED',
    );
    await _pick(tester, '1A');
    await tester.tap(find.text(r'Pay $0.603'));
    await _settle(tester);
    expect(
      find.text('The price changed. Check the new total. Nothing was charged.'),
      findsOneWidget,
    );
    expect(find.text('Booking confirmed'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a pending booking is "Seats reserved", with no boarding pass', (
    tester,
  ) async {
    final svc = await _pump(tester);
    svc.payStatus = 'PENDING';
    await _pick(tester, '1A');
    await tester.tap(find.text(r'Pay $0.603'));
    await _settle(tester);
    expect(find.text('Seats reserved'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsNothing);
    expect(find.byType(TransitBoardingPassCard), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
    'a seat chosen near the back stays in view when the dock arrives',
    (tester) async {
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
    },
  );

  testWidgets('the cab is announced: driver and mate, neither bookable', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.bySemanticsLabel('Driver'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mate, crew seat')), findsOneWidget);
    await _unmount(tester);
  });
}
