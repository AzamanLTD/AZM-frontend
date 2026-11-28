// Orders & bookings: one place for store orders, trips, reservations and
// bills, with "Needs you" first.
//   1. hubTasks picks what is waiting on the customer, most urgent first,
//      and nothing that is not (paid orders, far-off trips, past stays).
//   2. Reservations parse, count nights, and offer the check-in QR from a
//      day before arrival until the end.
//   3. The hub: Needs you opens the thing itself (a route) or its tab;
//      Reservations shows the QR only when it applies; Bills lists unpaid
//      first. Captured light and dark (test/goldens/hub/).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/orders_bookings_hub_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';

import 'support/money_access_test_support.dart';

final _now = DateTime(2026, 12, 5, 9, 0);

Map<String, dynamic> _order({
  String id = 'o1',
  String status = 'AWAITING_PAYMENT',
  String escrowStatus = 'DRAFT',
  String store = 'Kofi Bakery',
}) => {
  'id': id,
  'orderRef': 'ORD-$id',
  'status': status,
  'amountUsdc': '12.5',
  'title': 'Sourdough x2',
  // The card dates against the real clock.
  'createdAt': DateTime.now()
      .subtract(const Duration(hours: 2))
      .toIso8601String(),
  'deliveredAt': status == 'DELIVERED' ? _now.toIso8601String() : null,
  'items': [
    {'id': 'i1'},
  ],
  'businessProfile': {'id': 'bp-1', 'businessName': store},
  'escrow': {
    'id': 'esc-$id',
    'status': escrowStatus,
    'amountUsdc': '12.5',
    'feeUsdc': '0.125',
    'payerSatisfied': false,
    // Relative to the real clock: StoreOrderPayment checks the real now.
    'expiresAt': DateTime.now()
        .add(const Duration(hours: 20))
        .toIso8601String(),
  },
};

TransitBookingSummary _trip({
  String id = 't1',
  String status = 'CONFIRMED',
  DateTime? at,
  Map<String, dynamic>? boarding,
  String? payment,
}) => TransitBookingSummary.fromJson({
  'id': id,
  'bookingRef': 'TRN-$id',
  'status': status,
  'pickupAddress': 'Circle',
  'dropoffAddress': 'Kumasi',
  'scheduledAt': (at ?? _now.add(const Duration(hours: 3))).toIso8601String(),
  'amountUsdc': 9,
  'payment': payment,
  'businessProfile': {'businessName': 'VIP Jeoun'},
  'metadata': {'boarding': ?boarding},
});

ReservationSummary _stay({
  String id = 'r1',
  String status = 'CONFIRMED',
  DateTime? start,
  int nights = 2,
  String category = 'HOSPITALITY',
}) {
  final s = start ?? DateTime(2026, 12, 5, 14);
  return ReservationSummary.fromJson({
    'id': id,
    'reservationRef': 'RES-$id',
    'status': status,
    'startDatetime': s.toIso8601String(),
    'endDatetime':
        (nights == 0
                ? s.add(const Duration(hours: 2))
                : DateTime(s.year, s.month, s.day + nights, 11))
            .toIso8601String(),
    'partySize': 2,
    'amountUsdc': 180,
    'businessProfile': {
      'businessName': 'Labadi Beach Hotel',
      'category': category,
      'bizId': 'BIZ-1',
    },
  });
}

BusinessInvoice _bill({
  String id = 'b1',
  String status = 'SENT',
  String biz = 'Buka',
}) => BusinessInvoice.fromJson({
  'id': id,
  'businessProfileId': 'bp-9',
  'invoiceRef': 'INV-$id',
  'customerId': 10,
  'status': status,
  'billTotalUsdc': 23.4,
  'createdAt': _now.toIso8601String(),
  'businessProfile': {'businessName': biz},
});

class _Invoices extends MyInvoicesNotifier {
  _Invoices(List<BusinessInvoice> list) : super(BusinessService()) {
    state = MyInvoicesState(invoices: list);
  }
  @override
  Future<void> load({String? status}) async {}
}

class _Storefront extends StorefrontService {
  _Storefront(this.orders);
  final List<Map<String, dynamic>> orders;
  @override
  Future<Map<String, dynamic>> getMyOrders({
    String? status,
    int limit = 20,
    String? cursor,
  }) async => {'orders': orders, 'nextCursor': null};
}

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

Future<GoRouter> _pumpHub(
  WidgetTester tester, {
  List<Map<String, dynamic>> orders = const [],
  List<TransitBookingSummary> trips = const [],
  List<ReservationSummary> stays = const [],
  List<BusinessInvoice> bills = const [],
  HubTab tab = HubTab.orders,
  bool dark = true,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => OrdersBookingsHubScreen(initialTab: tab, now: _now),
      ),
      GoRoute(
        path: '/marketplace/booking/checkin-qr/:id',
        builder: (_, s) =>
            Scaffold(body: Text('check-in ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/marketplace/transit/boarding/:id',
        builder: (_, s) =>
            Scaffold(body: Text('boarding ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/business-market/invoices/:id',
        builder: (_, s) =>
            Scaffold(body: Text('invoice ${s.pathParameters['id']}')),
      ),
    ],
  );
  SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
  final tp = ThemeProvider();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => tp),
        unlockedMoneyAccess(),
        storefrontServiceProvider.overrideWithValue(_Storefront(orders)),
        myStoreOrdersProvider.overrideWith((ref) async => orders),
        myTransitBookingsProvider.overrideWith((ref) async => trips),
        myReservationsProvider.overrideWith((ref) async => stays),
        myInvoicesProvider.overrideWith((ref) => _Invoices(bills)),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider.getThemeData(
          dark ? AzamanTheme.dark : AzamanTheme.light,
        ),
        routerConfig: router,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return router;
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

  group('what needs you', () {
    test('most urgent first, and only what is waiting', () {
      final tasks = hubTasks(
        now: _now,
        orders: [
          _order(id: 'pay'),
          _order(
            id: 'got',
            status: 'DELIVERED',
            escrowStatus: 'PENDING_SETTLEMENT',
          ),
          _order(id: 'paid', status: 'PAID', escrowStatus: 'FUNDED'),
        ],
        trips: [
          _trip(id: 'soon'),
          _trip(id: 'far', at: _now.add(const Duration(days: 4))),
          _trip(
            id: 'idc',
            status: 'IN_PROGRESS',
            boarding: {'method': 'ID_CHECK', 'at': _now.toIso8601String()},
            payment: 'HELD',
          ),
        ],
        reservations: [
          _stay(id: 'today'),
          _stay(id: 'next-month', start: DateTime(2027, 1, 5, 14)),
          _stay(id: 'gone', status: 'COMPLETED', start: DateTime(2026, 11, 1)),
        ],
        invoices: [
          _bill(id: 'due'),
          _bill(id: 'done', status: 'PAID'),
        ],
      );
      expect(tasks.map((t) => '${t.kind.name}:${t.id}').toList(), [
        'answerBoarding:idc',
        'payOrder:pay',
        'boardingPass:soon',
        'checkIn:today',
        'confirmOrder:got',
        'payBill:due',
      ]);
      expect(tasks[1].title, r'Pay $12.625');
      expect(tasks[2].route, '/marketplace/transit/boarding/soon');
      expect(tasks[3].route, '/marketplace/booking/checkin-qr/today');
      expect(tasks[4].route, isNull); // its actions are on the Orders tab
    });

    test('tabs read from a link', () {
      expect(hubTabFromQuery('trips'), HubTab.trips);
      expect(hubTabFromQuery('stays'), HubTab.reservations);
      expect(hubTabFromQuery('bills'), HubTab.bills);
      expect(hubTabFromQuery(null), HubTab.orders);
      expect(hubTabFromQuery('nonsense'), HubTab.orders);
    });
  });

  group('reservations', () {
    test('a stay counts nights; a table is same-day', () {
      expect(_stay(nights: 2).nights, 2);
      expect(_stay(nights: 2).isStay, isTrue);
      final table = _stay(nights: 0, category: 'FOOD_BEVERAGE');
      expect(table.nights, 0);
      expect(table.isStay, isFalse);
    });

    test('the check-in QR applies from a day before until the end', () {
      final r = _stay(start: DateTime(2026, 12, 5, 14));
      expect(r.canShowCheckInQr(DateTime(2026, 12, 4, 13)), isFalse);
      expect(r.canShowCheckInQr(DateTime(2026, 12, 4, 15)), isTrue);
      expect(r.canShowCheckInQr(DateTime(2026, 12, 6, 9)), isTrue);
      expect(r.canShowCheckInQr(DateTime(2026, 12, 7, 12)), isFalse);
      expect(_stay(status: 'PENDING').canShowCheckInQr(_now), isFalse);
    });
  });

  group('the hub', () {
    testWidgets('Needs you opens the check-in QR directly', (tester) async {
      await _pumpHub(tester, stays: [_stay(id: 'today')]);
      expect(find.byKey(const ValueKey('hub-needs-you')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hub-task-checkIn-today')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // push() opens the page on top; the opened page is the proof.
      expect(find.text('check-in today'), findsOneWidget);
    });

    testWidgets('a task without a route switches to its tab', (tester) async {
      await _pumpHub(
        tester,
        tab: HubTab.bills,
        orders: [
          _order(
            id: 'got',
            status: 'DELIVERED',
            escrowStatus: 'PENDING_SETTLEMENT',
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('hub-task-confirmOrder-got')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('order-got-it-got')), findsOneWidget);
    });

    testWidgets('nothing waiting: no Needs you strip', (tester) async {
      await _pumpHub(
        tester,
        orders: [_order(id: 'paid', status: 'PAID', escrowStatus: 'FUNDED')],
      );
      expect(find.byKey(const ValueKey('hub-needs-you')), findsNothing);
      expect(
        find.text('Paid · held until the store hands your order over.'),
        findsOneWidget,
      );
    });

    testWidgets('Reservations: the QR only when it applies', (tester) async {
      await _pumpHub(
        tester,
        tab: HubTab.reservations,
        stays: [
          _stay(id: 'today'),
          _stay(id: 'later', start: DateTime(2027, 1, 5, 14)),
          _stay(
            id: 'table',
            nights: 0,
            category: 'FOOD_BEVERAGE',
            start: DateTime(2026, 12, 5, 19, 30),
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey('reservation-qr-today')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reservation-qr-later')), findsNothing);
      expect(
        find.text('Sat 5 Dec → Mon 7 Dec · 2 nights · 2 guests'),
        findsOneWidget,
      );
      expect(find.text('Sat 5 Dec · 19:30 · Table for 2'), findsOneWidget);
    });

    testWidgets('Bills: unpaid first, and each opens its invoice', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        tab: HubTab.bills,
        bills: [
          _bill(id: 'old', status: 'PAID', biz: 'Kenkey House'),
          _bill(id: 'due'),
        ],
      );
      final due = tester.getTopLeft(find.byKey(const ValueKey('bill-due')));
      final old = tester.getTopLeft(find.byKey(const ValueKey('bill-old')));
      expect(due.dy, lessThan(old.dy));
      expect(find.text('Unpaid'), findsOneWidget);
    });
  });

  group('captures', () {
    for (final dark in [true, false]) {
      testWidgets('hub ${dark ? 'dark' : 'light'}', (tester) async {
        await tester.runAsync(_loadFonts);
        await _pumpHub(
          tester,
          dark: dark,
          orders: [
            _order(id: 'pay'),
            _order(
              id: 'got',
              status: 'DELIVERED',
              escrowStatus: 'PENDING_SETTLEMENT',
              store: 'Ama Shoes',
            ),
            _order(
              id: 'done',
              status: 'COMPLETED',
              escrowStatus: 'SETTLED',
              store: 'Makola Fresh',
            ),
          ],
          trips: [_trip(id: 'soon')],
          stays: [_stay(id: 'today')],
          bills: [_bill(id: 'due')],
        );
        await expectLater(
          find.byType(OrdersBookingsHubScreen),
          matchesGoldenFile(
            'goldens/hub/orders_bookings_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  });
}
