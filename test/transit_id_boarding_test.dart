// Boarding by ID check, beside the QR (app side).
//   1. The AZM-ID search shows the passenger as staff check them (photo,
//      name, name on ID, AZM-ID, ID verified) and their trips here.
//   2. "Board after ID check" asks staff to compare the person and their ID
//      first, then boards with the AZM-ID as that check; a refusal keeps the
//      search on screen with the server's reason.
//   3. A business that boards by QR only offers no ID boarding.
//   4. "Next customer" keeps the check-in screen open.
//   5. The passenger's trip asks "Was this you?": yes confirms, "Not me"
//      reports it with an optional note.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/screens/marketplace/business_checkin_screen.dart';
import 'package:azaman/screens/marketplace/my_transit_trips_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/services/notification_action_dispatcher.dart';

final _departure = DateTime.now().add(const Duration(minutes: 30));

Map<String, dynamic> _searchJson({
  bool canBoard = true,
  bool allowIdCheck = true,
  String status = 'CONFIRMED',
}) => {
  'success': true,
  'customer': {
    'id': 10,
    'username': 'ama',
    'azamanId': 'AZM-000004242',
    'displayName': 'Ama Mensah',
    'legalName': 'Ama Owusu Mensah',
    'profilePictureUrl': null,
    'idVerified': true,
  },
  'reservations': const [],
  'boardingPolicy': {'allowIdCheck': allowIdCheck},
  'transitBookings': [
    {
      'id': 'bk-1',
      'bookingRef': 'TRN-1A2B',
      'status': status,
      'origin': 'Circle',
      'destination': 'Kumasi',
      'departureAt': _departure.toIso8601String(),
      'seats': [
        {'seatId': '3B', 'passengerName': null},
      ],
      'amountUsdc': 12,
      'payment': 'HELD',
      'paid': true,
      'passenger': {
        'azamanId': 'AZM-000004242',
        'username': 'ama',
        'displayName': 'Ama Mensah',
        'legalName': 'Ama Owusu Mensah',
        'idVerified': true,
      },
      'boarding': null,
      'canBoardById': canBoard,
      'boardingWindow': {
        'opensAt': _departure
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'closesAt': _departure.add(const Duration(hours: 1)).toIso8601String(),
      },
    },
  ],
};

class _FakeService extends MarketplaceBookingService {
  _FakeService({this.trips = const [], this.boardError});
  final List<TransitBookingSummary> trips;
  final Object? boardError;
  final boarded = <List<String>>[];
  final confirmed = <String>[];
  final reported = <List<String?>>[];

  @override
  Future<CheckInResult> boardByIdCheck(
    String bookingId,
    String azamanId,
  ) async {
    boarded.add([bookingId, azamanId]);
    if (boardError != null) throw boardError!;
    return const CheckInResult(
      success: true,
      isTransit: true,
      boardedByIdCheck: true,
      fareHeldHours: 24,
      reservationRef: 'TRN-1A2B',
      status: 'IN_PROGRESS',
    );
  }

  @override
  Future<List<TransitBookingSummary>> myTransitBookings() async => trips;

  @override
  Future<void> confirmIdCheckBoarding(String bookingId) async {
    confirmed.add(bookingId);
  }

  @override
  Future<bool> reportIdCheckBoarding(String bookingId, {String? reason}) async {
    reported.add([bookingId, reason]);
    return false;
  }
}

class _Seeded extends CheckInActionNotifier {
  _Seeded(super.svc, CheckInActionState initial) {
    state = initial;
  }
}

Future<void> _pumpCheckIn(
  WidgetTester tester,
  _FakeService svc,
  AzamanIdSearchResult search,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceBookingServiceProvider.overrideWithValue(svc),
        checkInActionProvider.overrideWith(
          (ref) => _Seeded(svc, CheckInActionState(searchResult: search)),
        ),
      ],
      child: const MaterialApp(home: BusinessCheckInScreen()),
    ),
  );
  await tester.pump();
}

// The check-in screen's scan line repeats forever, so it never settles:
// step through enough frames for a dialog or a state change instead.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const scanner = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  setUp(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(secureStorage, (call) async => null);
    m.setMockMethodCallHandler(scanner, (call) async => null);
  });
  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(secureStorage, null);
    m.setMockMethodCallHandler(scanner, null);
  });

  group('models', () {
    test('the search carries the passenger card, trips and policy', () {
      final r = AzamanIdSearchResult.fromJson(_searchJson(allowIdCheck: false));
      expect(r.shownName, 'Ama Mensah');
      expect(r.legalName, 'Ama Owusu Mensah');
      expect(r.idVerified, isTrue);
      expect(r.allowIdCheck, isFalse);
      final t = r.transitBookings.single;
      expect(t.seatIds, ['3B']);
      expect(t.isPaid, isTrue);
      expect(t.canBoardById, isTrue);
      expect(t.passenger!.azamanId, 'AZM-000004242');
      // An older server without the new fields still parses.
      final old = AzamanIdSearchResult.fromJson({
        'customer': {'id': 1, 'username': 'kofi', 'azamanId': 'AZM-1'},
        'reservations': const [],
      });
      expect(old.transitBookings, isEmpty);
      expect(old.allowIdCheck, isTrue);
    });

    test('a trip boarded by ID check waits for the passenger\'s answer', () {
      TransitBookingSummary trip(
        Map<String, dynamic> boarding,
        String payment,
      ) => TransitBookingSummary.fromJson({
        'id': 'bk-1',
        'bookingRef': 'TRN-1',
        'status': 'IN_PROGRESS',
        'pickupAddress': 'Circle',
        'dropoffAddress': 'Kumasi',
        'amountUsdc': 12,
        'payment': payment,
        'metadata': {'boarding': boarding},
      });
      expect(
        trip({
          'method': 'ID_CHECK',
          'at': '2026-11-28T09:12:00Z',
        }, 'HELD').awaitsBoardingAnswer,
        isTrue,
      );
      expect(
        trip({
          'method': 'ID_CHECK',
          'passengerConfirmedAt': '2026-11-28T09:20:00Z',
        }, 'HELD').awaitsBoardingAnswer,
        isFalse,
      );
      expect(
        trip({'method': 'QR_TOKEN'}, 'HELD').awaitsBoardingAnswer,
        isFalse,
      );
      expect(trip({'method': 'ID_CHECK'}, 'REPORTED').isReported, isTrue);
    });

    test('the boarding notice opens Your trips', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_TRANSIT_TRIPS',
      });
      expect(a.route, '/marketplace/transit/my-trips');
    });
  });

  group('staff: board by ID check', () {
    testWidgets('shows the passenger as staff check them, then boards', (
      tester,
    ) async {
      final svc = _FakeService();
      await _pumpCheckIn(
        tester,
        svc,
        AzamanIdSearchResult.fromJson(_searchJson()),
      );

      expect(find.text('Ama Mensah'), findsWidgets);
      expect(
        find.byKey(const ValueKey('passenger-legal-name')),
        findsOneWidget,
      );
      expect(find.text('Name on ID: Ama Owusu Mensah'), findsOneWidget);
      expect(find.text('ID verified'), findsOneWidget);
      expect(find.text('Circle → Kumasi'), findsOneWidget);
      expect(find.text('Paid in Azaman'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('board-by-id-bk-1')));
      await _frames(tester);
      // Compare the person and the ID before anything is sent.
      expect(find.text('Check their ID'), findsOneWidget);
      expect(find.text('Ama Owusu Mensah'), findsOneWidget);
      expect(find.text('3B'), findsOneWidget);
      expect(svc.boarded, isEmpty);

      await tester.tap(find.byKey(const ValueKey('confirm-board-by-id')));
      await _frames(tester);
      expect(svc.boarded, [
        ['bk-1', 'AZM-000004242'],
      ]);
      expect(find.text('Boarded'), findsOneWidget);
      expect(find.text('By ID check'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('id-check-payout-note')),
        findsOneWidget,
      );

      // Next customer keeps the screen open, back at the start.
      await tester.tap(find.byKey(const ValueKey('checkin-next')));
      await tester.pump();
      expect(find.byType(BusinessCheckInScreen), findsOneWidget);
      expect(find.text('Boarded'), findsNothing);
    });

    testWidgets('"Not now" sends nothing', (tester) async {
      final svc = _FakeService();
      await _pumpCheckIn(
        tester,
        svc,
        AzamanIdSearchResult.fromJson(_searchJson()),
      );
      await tester.tap(find.byKey(const ValueKey('board-by-id-bk-1')));
      await _frames(tester);
      await tester.tap(find.text('Not now'));
      await _frames(tester);
      expect(svc.boarded, isEmpty);
      expect(find.text('Circle → Kumasi'), findsOneWidget);
    });

    testWidgets('a refusal keeps the search with the server\'s reason', (
      tester,
    ) async {
      final svc = _FakeService(
        boardError: ApiException(
          message: 'That AZM-ID is not the passenger on this booking.',
          statusCode: 409,
          code: 'AZAMAN_ID_MISMATCH',
        ),
      );
      await _pumpCheckIn(
        tester,
        svc,
        AzamanIdSearchResult.fromJson(_searchJson()),
      );
      await tester.tap(find.byKey(const ValueKey('board-by-id-bk-1')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-board-by-id')));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('checkin-search-error')),
        findsOneWidget,
      );
      expect(
        find.text('That AZM-ID is not the passenger on this booking.'),
        findsOneWidget,
      );
      expect(find.text('Circle → Kumasi'), findsOneWidget);
      expect(find.text('Boarded'), findsNothing);
    });

    testWidgets('QR only: no ID boarding is offered', (tester) async {
      final svc = _FakeService();
      await _pumpCheckIn(
        tester,
        svc,
        AzamanIdSearchResult.fromJson(
          _searchJson(canBoard: false, allowIdCheck: false),
        ),
      );
      expect(find.byKey(const ValueKey('board-by-id-bk-1')), findsNothing);
      expect(
        find.text(
          'Your business boards by QR only. Ask for their boarding QR.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an on-board passenger shows how they boarded', (tester) async {
      final json = _searchJson(canBoard: false, status: 'IN_PROGRESS');
      ((json['transitBookings'] as List).first as Map)['boarding'] = {
        'method': 'ID_CHECK',
        'at': DateTime.now().toIso8601String(),
      };
      await _pumpCheckIn(
        tester,
        _FakeService(),
        AzamanIdSearchResult.fromJson(json),
      );
      expect(find.text('On board · by ID check'), findsOneWidget);
      expect(find.byKey(const ValueKey('board-by-id-bk-1')), findsNothing);
    });
  });

  group('passenger: was this you?', () {
    TransitBookingSummary idChecked({String payment = 'HELD'}) =>
        TransitBookingSummary.fromJson({
          'id': 'bk-1',
          'bookingRef': 'TRN-1A2B',
          'status': 'IN_PROGRESS',
          'pickupAddress': 'Circle',
          'dropoffAddress': 'Kumasi',
          'scheduledAt': _departure.toIso8601String(),
          'amountUsdc': 12,
          'payment': payment,
          'businessProfile': {'businessName': 'Kofi Express'},
          'metadata': {
            'boarding': {
              'method': 'ID_CHECK',
              'at': DateTime.now().toIso8601String(),
            },
          },
        });

    Future<void> pumpTrips(WidgetTester tester, _FakeService svc) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [marketplaceBookingServiceProvider.overrideWithValue(svc)],
          child: const MaterialApp(home: MyTransitTripsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('"Yes, it was me" confirms', (tester) async {
      final svc = _FakeService(trips: [idChecked()]);
      await pumpTrips(tester, svc);
      expect(
        find.byKey(const ValueKey('boarding-answer-bk-1')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Kofi Express boarded you after checking your ID. Was this you?',
        ),
        findsOneWidget,
      );
      expect(find.text('On board · ID checked · TRN-1A2B'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('boarding-yes-bk-1')));
      await tester.pump();
      expect(svc.confirmed, ['bk-1']);
    });

    testWidgets('"Not me" reports it with a note', (tester) async {
      final svc = _FakeService(trips: [idChecked()]);
      await pumpTrips(tester, svc);
      await tester.tap(find.byKey(const ValueKey('boarding-not-me-bk-1')));
      await tester.pumpAndSettle();
      expect(find.text('Not you?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('boarding-report-reason')),
        'I was at home',
      );
      await tester.tap(find.byKey(const ValueKey('boarding-report-send')));
      await tester.pumpAndSettle();
      expect(svc.reported, [
        ['bk-1', 'I was at home'],
      ]);
      expect(
        find.text('Reported. The fare stays held while we look into it.'),
        findsOneWidget,
      );
    });

    testWidgets('a reported trip says the fare is held', (tester) async {
      await pumpTrips(
        tester,
        _FakeService(trips: [idChecked(payment: 'REPORTED')]),
      );
      expect(find.byKey(const ValueKey('boarding-answer-bk-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('boarding-reported-bk-1')),
        findsOneWidget,
      );
    });
  });
}
