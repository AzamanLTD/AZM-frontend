// QR boarding, app side. A paid fare reaches the operator only when the
// passenger is boarded by their own signed code, so:
//   1. the business scanner tells a transit boarding pass from a hotel code
//      (payload type, or the bare token's own typ) and sends each to the
//      endpoint that verifies it;
//   2. the passenger can find every booking again (Your trips) and open its
//      boarding QR on the day;
//   3. outside the boarding window the screen shows the server's reason.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/screens/marketplace/checkin_qr_screen.dart';
import 'package:azaman/screens/marketplace/my_transit_trips_screen.dart';
import 'package:azaman/screens/marketplace/transit_boarding_qr_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/utils/checkin_scan.dart';

String _bareToken(Map<String, dynamic> payload) =>
    '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${'a' * 64}';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _FakeService extends MarketplaceBookingService {
  _FakeService({this.trips = const [], this.code, this.codeError});
  final List<TransitBookingSummary> trips;
  final TransitBoardingCode? code;
  final Object? codeError;

  @override
  Future<List<TransitBookingSummary>> myTransitBookings() async => trips;

  @override
  Future<TransitBoardingCode> transitBoardingCode(String bookingId) async {
    if (codeError != null) throw codeError!;
    return code!;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen,
  _FakeService svc,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [marketplaceBookingServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  group('parseCheckInScan', () {
    test('a transit boarding pass payload is transit', () {
      final s = parseCheckInScan(
        '{"token":"t.sig","type":"AZAMAN_TRANSIT_CHECKIN"}',
      );
      expect(s.kind, CheckInScanKind.transit);
      expect(s.token, 't.sig');
    });

    test('a hotel check-in payload is a reservation', () {
      final s = parseCheckInScan('{"token":"r.sig","type":"AZAMAN_CHECKIN"}');
      expect(s.kind, CheckInScanKind.reservation);
      expect(s.token, 'r.sig');
    });

    test('a bare token is routed by its own typ', () {
      expect(
        parseCheckInScan(
          _bareToken({'typ': 'TRANSIT_CHECKIN', 'bid': 'b'}),
        ).kind,
        CheckInScanKind.transit,
      );
      expect(
        parseCheckInScan(_bareToken({'typ': 'CHECKIN', 'rid': 'r'})).kind,
        CheckInScanKind.reservation,
      );
      expect(parseCheckInScan('not-a-token').kind, CheckInScanKind.reservation);
    });
  });

  group('CheckInActionNotifier.verifyScan', () {
    Future<(List<http.Request>, CheckInActionNotifier)> run(String raw) async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path.endsWith('/transit/boarding')) {
          return _json(200, {
            'success': true,
            'booking': {'bookingRef': 'TRN-9', 'status': 'IN_PROGRESS'},
          });
        }
        return _json(200, {
          'success': true,
          'reservation': {'reservationRef': 'RES-1', 'status': 'CHECKED_IN'},
        });
      });
      final n = CheckInActionNotifier(
        MarketplaceBookingService(apiClient: ApiClient(client: client)),
      );
      await n.verifyScan(raw);
      return (requests, n);
    }

    test('a transit pass boards through /transit/boarding', () async {
      final (requests, n) = await run(
        '{"token":"t.sig","type":"AZAMAN_TRANSIT_CHECKIN"}',
      );
      expect(requests.single.url.path, endsWith('/transit/boarding'));
      expect(jsonDecode(requests.single.body), {'token': 't.sig'});
      expect(n.state.result?.isTransit, isTrue);
      expect(n.state.result?.reservationRef, 'TRN-9');
    });

    test('a hotel code still checks in through the reservation path', () async {
      final (requests, n) = await run(
        '{"token":"r.sig","type":"AZAMAN_CHECKIN"}',
      );
      expect(
        requests.single.url.path,
        endsWith('/marketplace/business/checkin'),
      );
      expect(n.state.result?.isTransit, isFalse);
    });
  });

  test('a booking summary reads the list endpoint shape', () {
    final b = TransitBookingSummary.fromJson({
      'id': 'b1',
      'bookingRef': 'TRN-1',
      'status': 'CONFIRMED',
      'pickupAddress': 'Circle',
      'dropoffAddress': 'Madina',
      'scheduledAt': '2026-12-01T07:30:00Z',
      'amountUsdc': '0.6',
      'feeUsdc': '0.003',
      'businessProfile': {'businessName': 'Metro Mass'},
      'metadata': {
        'boarding': {'method': 'QR_TOKEN'},
      },
    });
    expect(b.origin, 'Circle');
    expect(b.amountUsdc, 0.6);
    expect(b.operatorName, 'Metro Mass');
    expect(b.boardingMethod, 'QR_TOKEN');
    expect(b.canShowBoardingQr, isTrue);
  });

  testWidgets(
    'Your trips offers the boarding QR only for paid, unboarded trips',
    (tester) async {
      TransitBookingSummary t(String id, String status) =>
          TransitBookingSummary(
            id: id,
            bookingRef: 'TRN-$id',
            status: status,
            origin: 'Circle',
            destination: 'Madina',
            amountUsdc: 0.6,
            departureAt: DateTime(2026, 12, 1, 7, 30),
          );
      await _pumpScreen(
        tester,
        const MyTransitTripsScreen(),
        _FakeService(
          trips: [t('a', 'CONFIRMED'), t('b', 'COMPLETED'), t('c', 'PENDING')],
        ),
      );
      expect(find.text('Circle → Madina'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('my-trip-qr-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('my-trip-qr-b')), findsNothing);
      expect(find.byKey(const ValueKey('my-trip-qr-c')), findsNothing);
      expect(find.text('Paid · ready to board · TRN-a'), findsOneWidget);
    },
  );

  testWidgets('the boarding pass shows the signed code', (tester) async {
    await _pumpScreen(
      tester,
      const TransitBoardingQrScreen(bookingId: 'a'),
      _FakeService(
        code: TransitBoardingCode(
          qrPayload: '{"token":"t.sig","type":"AZAMAN_TRANSIT_CHECKIN"}',
          expiresAt: DateTime(2026, 12, 1, 7, 20),
        ),
      ),
    );
    expect(
      tester.widget<CheckInCode>(find.byType(CheckInCode)).payload,
      contains('AZAMAN_TRANSIT_CHECKIN'),
    );
    expect(find.byKey(const ValueKey('boarding-qr-expiry')), findsOneWidget);
  });

  testWidgets('outside the boarding window it shows the server reason', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const TransitBoardingQrScreen(bookingId: 'a'),
      _FakeService(
        codeError: ApiException(
          message: 'QR code will be valid 1 hour before departure.',
          statusCode: 400,
        ),
      ),
    );
    expect(
      find.text('QR code will be valid 1 hour before departure.'),
      findsOneWidget,
    );
    expect(find.byType(CheckInCode), findsNothing);
  });
}
