// The hotel booking flow: dates and guests first, then a room among those
// free for them, then a REQUEST (the hotel confirms; paid at the hotel).
//   1. The stay quote parses and names why a room is greyed.
//   2. The summary bar shows the server's total, waits while pricing, and
//      refuses a room the quote says is not free.
//   3. The screen: a back button; picking dates prices the stay; more guests
//      grey a room that is too small; the request carries the guest count;
//      the confirmation says "requested" and pay at the hotel, and opens
//      Orders & bookings (never a check-in QR that does not exist yet).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/hotel_marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/hotel_booking_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart';
import 'package:azaman/widgets/marketplace/stay_date_ribbon.dart';
import 'package:azaman/widgets/marketplace/stay_summary_bar.dart';
import 'package:azaman/widgets/security/second_factor.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

HotelRoom _room(
  String n, {
  int capacity = 2,
  double price = 80,
  int floor = 1,
}) => HotelRoom(
  id: 'room-$n',
  businessProfileId: 'bp-h',
  roomNumber: n,
  roomType: 'DELUXE',
  capacity: capacity,
  status: 'AVAILABLE',
  basePriceUsdc: price,
  amenities: const [],
  imageUrls: const [],
  floor: floor,
);

class _Hotel extends HotelMarketplaceService {
  _Hotel({this.payInApp = false, this.reserveError}) : super();
  final bool payInApp;
  final Object? reserveError;
  final quotes = <String>[];
  final reserved = <Map<String, Object?>>[];

  @override
  Future<HotelBusinessDetail> fetchHotel(String bizId) async =>
      HotelBusinessDetail(
        business: BusinessProfile.fromJson({
          'id': 'bp-h',
          'bizId': bizId,
          'businessName': 'Labadi Beach Hotel',
          'category': 'HOSPITALITY',
        }),
        rooms: [_room('101'), _room('102', capacity: 4, price: 120)],
      );

  @override
  Future<StayQuote> stayQuote({
    required String bizId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
  }) async {
    quotes.add('$guests');
    final nights = checkOut.difference(checkIn).inDays;
    double fee(double t) => double.parse((t * 0.01).toStringAsFixed(6));
    double pay(double t) => double.parse((t + fee(t)).toStringAsFixed(6));
    if (payInApp) {
      final t101 = 95.5 * nights;
      final t102 = 130.0 * nights;
      return StayQuote(
        nights: nights,
        guests: guests,
        payAt: 'APP',
        rooms: {
          'room-101': RoomQuote(
            roomId: 'room-101',
            bookable: guests <= 2,
            reason: guests <= 2 ? null : 'TOO_SMALL',
            totalUsdc: t101,
            capacity: 2,
            feeUsdc: fee(t101),
            payTotalUsdc: pay(t101),
          ),
          'room-102': RoomQuote(
            roomId: 'room-102',
            bookable: true,
            totalUsdc: t102,
            capacity: 4,
            feeUsdc: fee(t102),
            payTotalUsdc: pay(t102),
          ),
        },
      );
    }
    return StayQuote(
      nights: nights,
      guests: guests,
      rooms: {
        'room-101': RoomQuote(
          roomId: 'room-101',
          bookable: guests <= 2,
          reason: guests <= 2 ? null : 'TOO_SMALL',
          totalUsdc: 95.5 * nights,
          capacity: 2,
        ),
        'room-102': RoomQuote(
          roomId: 'room-102',
          bookable: true,
          totalUsdc: 130.0 * nights,
          capacity: 4,
        ),
      },
    );
  }

  @override
  Future<Map<String, dynamic>> reserve({
    required String bizId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    int partySize = 1,
    String? operationType,
    FinancialOperationRef? ref,
    bool payWithWallet = false,
    double? expectedTotalUsdc,
    Map<String, String>? secondFactor,
  }) async {
    if (payWithWallet) {
      reserved.add({
        'roomId': roomId,
        'partySize': partySize,
        'expected': expectedTotalUsdc,
        'factor': secondFactor,
      });
      if (reserveError != null) throw reserveError!;
      return {
        'id': 'res-1',
        'reservationRef': 'RES-7Q2K',
        'amountUsdc': '95.5',
        'status': 'CONFIRMED',
      };
    }
    reserved.add({'roomId': roomId, 'partySize': partySize});
    return {
      'id': 'res-1',
      'reservationRef': 'RES-7Q2K',
      'amountUsdc': '95.5',
      'status': 'PENDING',
    };
  }
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
    SharedPreferences.setMockInitialValues({});
    ApiClient.operationAccountOverride = () async => 'acct-test';
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    ApiClient.operationAccountOverride = null;
  });

  test('the stay quote parses and names why a room is greyed', () {
    final q = StayQuote.fromJson({
      'nights': 2,
      'guests': 3,
      'payAt': 'HOTEL',
      'rooms': [
        {
          'roomId': 'a',
          'bookable': true,
          'reason': null,
          'totalUsdc': 239,
          'capacity': 4,
        },
        {
          'roomId': 'b',
          'bookable': false,
          'reason': 'TOO_SMALL',
          'totalUsdc': 60,
          'capacity': 2,
        },
        {'roomId': 'c', 'bookable': false, 'reason': 'BOOKED', 'totalUsdc': 60},
      ],
    });
    expect(q.payAtHotel, isTrue);
    expect(q.rooms['a']!.totalUsdc, 239);
    expect(q.rooms['b']!.reasonLabel, 'Too small for your group');
    expect(q.rooms['c']!.reasonLabel, 'Taken for these dates');
    expect(_room('1').unavailableForStay().isBookable, isFalse);
  });

  group('summary bar', () {
    Future<int> pumpBar(WidgetTester tester, StaySummaryBar bar) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: const SizedBox(), bottomNavigationBar: bar),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return 0;
    }

    StaySummaryBar bar({
      double? quoted,
      bool pricing = false,
      String? unavailable,
      VoidCallback? onTap,
    }) => StaySummaryBar(
      room: _room('203', price: 80),
      checkIn: DateTime(2027, 12, 3),
      checkOut: DateTime(2027, 12, 6),
      nights: 3,
      isBooking: false,
      onReserve: onTap ?? () {},
      colors: _colors,
      quotedTotalUsdc: quoted,
      pricing: pricing,
      unavailableReason: unavailable,
      note: 'The hotel confirms · pay at the hotel',
    );

    testWidgets('shows the server total, not nights x base rate', (
      tester,
    ) async {
      await pumpBar(tester, bar(quoted: 239));
      expect(find.text('\$239.00 USDC · 3 nights'), findsOneWidget);
      expect(
        find.text('The hotel confirms · pay at the hotel'),
        findsOneWidget,
      );
    });

    testWidgets('waits while pricing, and refuses a room that is not free', (
      tester,
    ) async {
      var taps = 0;
      await pumpBar(tester, bar(pricing: true, onTap: () => taps++));
      expect(find.text('Pricing…'), findsOneWidget);
      await tester.tap(find.text('Request stay'), warnIfMissed: false);
      await pumpBar(
        tester,
        bar(
          quoted: 239,
          unavailable: 'Taken for these dates',
          onTap: () => taps++,
        ),
      );
      expect(find.text('Taken for these dates'), findsOneWidget);
      await tester.tap(find.text('Request stay'), warnIfMissed: false);
      expect(taps, 0);
    });
  });

  testWidgets('dates and guests first, then a room, then a request', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final svc = _Hotel();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const HotelBookingScreen(bizId: 'BIZ-H'),
        ),
        GoRoute(
          path: '/bookings',
          builder: (_, s) =>
              Scaffold(body: Text('bookings ${s.uri.queryParameters['tab']}')),
        ),
        GoRoute(
          path: '/marketplace/booking/checkin-qr/:id',
          builder: (_, _) => const Scaffold(body: Text('check-in qr')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hotelMarketplaceServiceProvider.overrideWithValue(svc)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _frames(tester);

    expect(find.byKey(const ValueKey('hotel-back')), findsOneWidget);
    expect(
      find.text('Pick your dates first to see which rooms are free.'),
      findsOneWidget,
    );
    // Nothing to request before dates and a room.
    expect(svc.quotes, isEmpty);

    // A one-night stay starting in two days (a ribbon cell).
    final day = DateTime.now().add(const Duration(days: 2));
    await tester.tap(
      find
          .descendant(
            of: find.byType(StayDateRibbon),
            matching: find.text('${day.day}'),
          )
          .first,
    );
    await _frames(tester);
    expect(svc.quotes, ['1']);
    expect(find.textContaining('Greyed rooms are taken'), findsOneWidget);

    // Three guests: room 101 (2 people) is greyed; the quote is re-asked.
    await tester.tap(find.byKey(const ValueKey('guests-plus')));
    await _frames(tester, 4);
    await tester.tap(find.byKey(const ValueKey('guests-plus')));
    await _frames(tester);
    expect(find.text('3'), findsWidgets);
    expect(svc.quotes.last, '3');

    // Room 102 fits: open it and select it.
    await tester.tap(find.text('102'));
    await _frames(tester);
    await tester.tap(find.text('Select this room'));
    await _frames(tester);
    expect(find.text('\$130.00 USDC · 1 night'), findsOneWidget);

    await tester.tap(find.text('Request stay'));
    await _frames(tester, 30);
    expect(svc.reserved.single, {'roomId': 'room-102', 'partySize': 3});
    expect(find.text('REQUEST SENT'), findsOneWidget);
    expect(find.text('Your stay is requested'), findsOneWidget);
    expect(find.byKey(const ValueKey('stay-request-note')), findsOneWidget);
    expect(find.text('Total paid'), findsNothing);

    // Never a jump to a check-in QR that only exists once confirmed.
    await _frames(tester, 70);
    expect(find.text('check-in qr'), findsNothing);

    await tester.tap(find.text('View in Orders & bookings'));
    await _frames(tester);
    expect(find.text('bookings reservations'), findsOneWidget);
  });

  group('paying for the stay', () {
    Future<SecondFactor?> askCode({
      required SecondFactorKind kind,
      String? errorText,
    }) async => const SecondFactor.authenticator('123456');

    Future<void> pumpAndPick(WidgetTester tester, _Hotel svc) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                HotelBookingScreen(bizId: 'BIZ-H', secondFactorPrompt: askCode),
          ),
          GoRoute(
            path: '/marketplace/booking/checkin-qr/:id',
            builder: (_, s) =>
                Scaffold(body: Text('check-in qr ${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/bookings',
            builder: (_, _) => const Scaffold(body: Text('bookings')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [hotelMarketplaceServiceProvider.overrideWithValue(svc)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await _frames(tester);
      final day = DateTime.now().add(const Duration(days: 2));
      await tester.tap(
        find
            .descendant(
              of: find.byType(StayDateRibbon),
              matching: find.text('${day.day}'),
            )
            .first,
      );
      await _frames(tester);
      await tester.tap(find.text('101'));
      await _frames(tester);
      await tester.tap(find.text('Select this room'));
      await _frames(tester);
    }

    testWidgets('price + fee, the second factor, then the QR is ready', (
      tester,
    ) async {
      final svc = _Hotel(payInApp: true);
      await pumpAndPick(tester, svc);
      // 95.50 + 1% fee, exactly as charged.
      expect(find.text('Pay \$96.455'), findsOneWidget);
      expect(find.textContaining('Held until you check in'), findsOneWidget);

      await tester.tap(find.text('Pay \$96.455'));
      await _frames(tester, 30);
      expect(svc.reserved.single, {
        'roomId': 'room-101',
        'partySize': 1,
        'expected': 96.455,
        'factor': {'totpToken': '123456'},
      });
      expect(find.text('STAY BOOKED'), findsOneWidget);
      expect(find.text('Your stay is booked'), findsOneWidget);
      expect(find.byKey(const ValueKey('stay-paid-note')), findsOneWidget);
      expect(find.text('\$96.455 USDC · held until check-in'), findsOneWidget);

      await tester.tap(find.text('Show check-in QR'));
      await _frames(tester);
      expect(find.text('check-in qr res-1'), findsOneWidget);
    });

    testWidgets('a short balance charges nothing and offers Add money', (
      tester,
    ) async {
      final svc = _Hotel(
        payInApp: true,
        reserveError: ApiException(
          message: 'Insufficient balance.',
          statusCode: 402,
          code: 'INSUFFICIENT_BALANCE',
        ),
      );
      await pumpAndPick(tester, svc);
      await tester.tap(find.text('Pay \$96.455'));
      await _frames(tester, 20);
      expect(
        find.text(
          'Not enough in your wallet for this stay. Nothing was charged.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add money'), findsOneWidget);
      expect(find.text('Your stay is booked'), findsNothing);
    });
  });
}
