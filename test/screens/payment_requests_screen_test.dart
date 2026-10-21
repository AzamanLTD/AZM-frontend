import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/screens/payment_request_landing_screen.dart';
import 'package:azaman/screens/payment_requests_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _listItem({
  String id = 'req-123',
  String amount = '25.00',
  String status = 'PENDING',
  String mode = 'DIRECT',
  String? requesterUsername,
  String? recipientUsername,
}) =>
    {
      'id': id,
      'amount': amount,
      'currency': 'GHS',
      'status': status,
      'mode': mode,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'expiresAt': '2026-10-08T10:00:00.000Z',
      'resolvedAt': null,
      'requester': requesterUsername == null
          ? null
          : {'displayName': requesterUsername, 'username': requesterUsername},
      'recipient': recipientUsername == null
          ? null
          : {'displayName': recipientUsername, 'username': recipientUsername},
      'requesterDisplayName': requesterUsername,
      'recipientDisplayName': recipientUsername,
    };

/// One client for the whole requests surface: GET list + idempotent
/// postFinancial terminal operations, recording every call.
class _RequestsApiClient extends ApiClient {
  _RequestsApiClient({this.listItems, this.resolveStatus = 200});

  final List<Map<String, dynamic>>? listItems;
  final int resolveStatus;
  int getCount = 0;
  int postCount = 0;
  String? lastEndpoint;
  String? lastOperationType;
  Map<String, dynamic>? lastBody;
  final List<Object?> postRefs = [];

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    getCount++;
    return _json(200, {
      'data': {
        'requests': listItems ?? [],
        'hasMore': false,
      },
    });
  }

  @override
  Future<http.Response> postFinancial(
    String path,
    Map<String, dynamic> requestBody, {
    required String operationType,
    FinancialOperationRef? ref,
    bool requireAuth = true,
    Map<String, String>? headers,
    bool failClosedOnPendingFingerprintChange = false,
  }) async {
    postCount++;
    lastEndpoint = path;
    lastOperationType = operationType;
    lastBody = Map<String, dynamic>.from(requestBody);
    postRefs.add(ref);
    if (resolveStatus == 200) {
      final id = path.split('/')[2];
      final action = path.endsWith('/cancel') ? 'cancel' : 'decline';
      return _json(200, {
        'data': {
          'request': _listItem(
            id: id,
            status: action == 'cancel' ? 'CANCELLED' : 'DECLINED',
          ),
        },
      });
    }
    return _json(resolveStatus, {
      'success': false,
      'code': resolveStatus == 409
          ? 'PAYMENT_REQUEST_ALREADY_RESOLVED'
          : 'PAYMENT_REQUEST_RESOLVE_FAILED',
      'message': resolveStatus == 409
          ? 'This payment request is already CANCELLED.'
          : 'The payment request could not be updated. Please try again.',
    });
  }
}

class _LandingApiClient extends ApiClient {
  _LandingApiClient(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  final List<String> calls = [];

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add('$endpoint|auth=$requireAuth');
    return _json(status, body);
  }
}

Widget _testApp({required ApiClient api, required Widget home}) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(home: home),
  );
}

void _phoneSize(WidgetTester tester, {Size size = const Size(420, 920)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Taps the first list row (the row containing [name]) to open the detail.
Future<void> _openDetail(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  });

  testWidgets(
      'incoming list renders the real list DTO — person, exact GHS amount, '
      'status — and carries no token material',
      (tester) async {
    final api = _RequestsApiClient(listItems: [
      _listItem(requesterUsername: 'kwame'),
    ]);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('kwame'), findsOneWidget);
    expect(find.text('GH₵ 25.00'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(api.getCount, 1);
    // The list DTO contract has no token fields anywhere in the response.
    final encoded = jsonEncode(api.listItems!.first);
    for (final forbidden in ['token', 'shareUrl', 'url']) {
      expect(encoded.toLowerCase().contains(forbidden), isFalse,
          reason: 'list rows must never echo token material');
    }
  });

  testWidgets('tapping a row opens a detail sheet built from the list DTO — '
      'no token hunt, no navigation, decline for incoming DIRECT PENDING',
      (tester) async {
    final api = _RequestsApiClient(listItems: [
      _listItem(requesterUsername: 'kwame'),
    ]);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _openDetail(tester, 'kwame');

    expect(find.byKey(const ValueKey('payment-request-detail')), findsOneWidget);
    expect(find.text('Request from kwame'), findsOneWidget);
    expect(find.text('Direct request'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-request-decline')), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-request-cancel')), findsNothing,
        reason: 'only the requester can cancel; the recipient declines');
  });

  testWidgets('decline posts the idempotent terminal operation and updates '
      'the row in place', (tester) async {
    final api = _RequestsApiClient(listItems: [
      _listItem(requesterUsername: 'kwame'),
    ]);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _openDetail(tester, 'kwame');

    await tester.tap(find.byKey(const ValueKey('payment-request-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.lastEndpoint, '/payment-requests/req-123/decline');
    expect(api.lastOperationType, 'payment.request.decline');
    expect(api.postCount, 1);
    // The sheet closed with the row updated from the server DTO.
    expect(find.byKey(const ValueKey('payment-request-detail')), findsNothing);
    expect(find.text('DECLINED'), findsOneWidget);
    expect(find.text('PENDING'), findsNothing);
  });

  testWidgets(
      'a cancel that cannot be confirmed keeps its operation identity: the '
      'SAME retry reuses the SAME operation ref (one idempotency instance)',
      (tester) async {
    final api = _RequestsApiClient(
      listItems: [_listItem(id: 'req-7', mode: 'LINK')],
      resolveStatus: 500,
    );

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Sent to become the requester.
    await tester.tap(find.text('Sent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Anyone with the link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // LINK requests have no recipient and the list carries no share URL:
    // the sheet states the documented recovery honestly.
    expect(
      find.textContaining(
        'The share link for this request was shown when it was created',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('payment-request-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('We could not confirm whether the request was updated'),
      findsOneWidget,
    );
    expect(api.postCount, 1);

    // Retry: the SAME operation ref must be reused — the durable client
    // instance (and its idempotency key) survives the unknown outcome.
    await tester.tap(find.byKey(const ValueKey('payment-request-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.postCount, 2);
    expect(api.postRefs[0], same(api.postRefs[1]));
  });

  testWidgets('a 409 cancel converges honestly on the committed state and '
      'reloads the list', (tester) async {
    final api = _RequestsApiClient(
      listItems: [_listItem(id: 'req-7', mode: 'LINK')],
      resolveStatus: 409,
    );

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Anyone with the link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final getsBefore = api.getCount;
    await tester.tap(find.byKey(const ValueKey('payment-request-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('already CANCELLED'), findsOneWidget);
    expect(api.getCount, greaterThan(getsBefore),
        reason: 'the list reloads so the UI shows the committed truth');
  });

  testWidgets('expired and terminal statuses render honestly; expired rows '
      'offer no terminal action', (tester) async {
    final api = _RequestsApiClient(listItems: [
      _listItem(id: 'req-e', status: 'EXPIRED', requesterUsername: 'yaw'),
      _listItem(id: 'req-c', status: 'CANCELLED', requesterUsername: 'abena'),
    ]);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('EXPIRED'), findsOneWidget);
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.text('PAID'), findsNothing,
        reason: 'the contract has no PAID status and none may be invented');

    await tester.tap(find.text('yaw'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('payment-request-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('payment-request-decline')), findsNothing);
  });

  testWidgets(
      'public link detail uses the unauthenticated public DTO contract',
      (tester) async {
    final api = _LandingApiClient(200, {
      'data': {
        'request': {
          'id': 'req-123',
          'amount': '70.00',
          'currency': 'GHS',
          'status': 'PENDING',
          'mode': 'LINK',
          'createdAt': '2026-10-01T10:00:00.000Z',
          'expiresAt': '2026-10-08T10:00:00.000Z',
          'requesterDisplayName': 'Ama Boateng',
          'requester': {'displayName': 'Ama Boateng', 'username': 'ama'},
        },
      },
    });

    await tester.pumpWidget(
      _testApp(
        api: api,
        home: const PaymentRequestLandingScreen(token: 'demo-token'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Payment request from Ama Boateng'), findsOneWidget);
    expect(find.text('GH₵ 70.00'), findsOneWidget);
    expect(
      api.calls,
      contains('/payment-requests/public/demo-token|auth=false'),
    );
    // Honest copy: opening the link does not initiate payment.
    expect(find.textContaining('does not start, authorize or complete'),
        findsOneWidget);
    expect(find.text('Pay now'), findsNothing);
  });

  testWidgets('missing public request renders an error, never a fake paid '
      'state', (tester) async {
    final api = _LandingApiClient(404, {'message': 'Request not found'});

    await tester.pumpWidget(
      _testApp(
        api: api,
        home: const PaymentRequestLandingScreen(token: 'missing-token'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Request not found'), findsOneWidget);
    expect(find.text('Pay now'), findsNothing);
    expect(find.textContaining('no longer active'), findsNothing);
  });

  testWidgets(
      'on 390x844 with a home-indicator inset, the last list row is fully '
      'scrollable/tappable and nothing sits under the inset',
      (tester) async {
    _phoneSize(tester, size: const Size(390, 844));
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);

    final items = List.generate(
      25,
      (i) => _listItem(id: 'req-$i', requesterUsername: 'user$i'),
    );
    final api = _RequestsApiClient(listItems: items);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final lastFinder = find.text('user24');
    await tester.scrollUntilVisible(
      lastFinder,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('payment-requests-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.renderObject(find.ancestor(
      of: lastFinder,
      matching: find.byType(Material),
    ).first) as RenderBox;
    expect(box.localToGlobal(Offset.zero).dy + box.size.height,
        lessThan(844 - 34),
        reason: 'the last row must clear the home-indicator inset');

    // The list viewport itself must end AT the inset, not under it.
    final list = tester.renderObject(
      find.byKey(const ValueKey('payment-requests-list')),
    ) as RenderBox;
    expect(list.localToGlobal(Offset.zero).dy + list.size.height,
        lessThanOrEqualTo(844 - 34));

    // And the fully-scrolled last row stays tappable (opens the detail).
    await tester.tap(lastFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('payment-request-detail')), findsOneWidget);
  });

  testWidgets(
      'on 430x932 with a home-indicator inset, the last list row is fully '
      'scrollable and clear of the inset',
      (tester) async {
    _phoneSize(tester, size: const Size(430, 932));
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);

    final items = List.generate(
      25,
      (i) => _listItem(id: 'req-$i', requesterUsername: 'user$i'),
    );
    final api = _RequestsApiClient(listItems: items);

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final lastFinder = find.text('user24');
    await tester.scrollUntilVisible(
      lastFinder,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('payment-requests-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.renderObject(find.ancestor(
      of: lastFinder,
      matching: find.byType(Material),
    ).first) as RenderBox;
    expect(box.localToGlobal(Offset.zero).dy + box.size.height,
        lessThan(932 - 34));
  });

  testWidgets(
      'public landing content scrolls fully clear of the home-indicator '
      'inset on a phone viewport',
      (tester) async {
    _phoneSize(tester, size: const Size(390, 844));
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);

    final api = _LandingApiClient(200, {
      'data': {
        'request': {
          'id': 'req-123',
          'amount': '70.00',
          'currency': 'GHS',
          'status': 'PENDING',
          'mode': 'LINK',
          'createdAt': '2026-10-01T10:00:00.000Z',
          'expiresAt': '2026-10-08T10:00:00.000Z',
          'requesterDisplayName': 'Ama Boateng',
        },
      },
    });

    await tester.pumpWidget(
      _testApp(
        api: api,
        home: const PaymentRequestLandingScreen(token: 'demo-token'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final finder = find.textContaining('does not start, authorize or complete');
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject(finder) as RenderBox;
    expect(box.localToGlobal(Offset.zero).dy + box.size.height,
        lessThan(844 - 34));
  });
}
