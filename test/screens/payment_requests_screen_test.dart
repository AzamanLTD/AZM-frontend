import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/payment_request_landing_screen.dart';
import 'package:azaman/screens/receive_screen.dart';
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:azaman/screens/payment_requests_screen.dart';
import 'package:azaman/services/api_client.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.onGet);

  final Future<http.Response> Function(
    String endpoint, {
    Map<String, String>? headers,
    bool? requireAuth,
  }) onGet;

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) =>
      onGet(endpoint, headers: headers, requireAuth: requireAuth);
}

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _RequestApiClient extends ApiClient {
  String? endpoint;
  Map<String, dynamic>? body;
  String? operationType;
  int postCount = 0;

  @override
  Future<http.Response> postFinancial(
    String path,
    Map<String, dynamic> requestBody, {
    required String operationType,
    FinancialOperationRef? ref,
    bool requireAuth = true,
    Map<String, String>? headers,
  }) async {
    endpoint = path;
    body = Map<String, dynamic>.from(requestBody);
    this.operationType = operationType;
    postCount++;
    return _json(201, {
      'data': {
        'request': {
          'id': 'req-42',
          'amount': requestBody['amount'],
          'currency': requestBody['currency'],
          'status': 'PENDING',
          'shareUrl': 'https://pay.azaman.test/request/req-42',
        },
      },
    });
  }
}

class _SeedFriendProvider extends FriendProvider {
  _SeedFriendProvider(Ref ref) : super(ref) {
    friends.add({
      'id': 'friendship-999',
      'friendshipId': 'friendship-999',
      'friendUsername': 'ama',
      'friend': {'id': '42', 'username': 'ama'},
    });
  }

  @override
  Future<void> fetchFriends() async {}
}


Widget _testApp({
  required ApiClient api,
  required Widget home,
}) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(home: home),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  });


  testWidgets('direct Request creates a standalone payment request and reuses its identity on repeat',
      (tester) async {
    final api = _RequestApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          friendProvider.overrideWith((ref) => _SeedFriendProvider(ref)),
        ],
        child: const MaterialApp(home: ReceiveScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final toggle = find.byKey(const ValueKey('receive-request-toggle'));
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.widgetWithText(ActionChip, 'GH₵ 10'));
    await tester.pump();
    final recipientTile = find.ancestor(
      of: find.text('ama'),
      matching: find.byType(ListTile),
    );
    await tester.tap(recipientTile);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('receive-request-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Request created'), findsOneWidget);
    expect(api.endpoint, '/payment-requests');
    expect(api.operationType, 'payment.request.create');
    expect(api.body, {
      'amount': '10.00',
      'currency': 'GHS',
      'requestMode': 'DIRECT',
      'recipientUserId': '42',
    });
    expect(api.postCount, 1);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('receive-request-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.postCount, 1,
        reason: 'repeating a successful request must reuse the created record, not create a duplicate');
  });

  testWidgets('incoming request list renders real server response and status',
      (tester) async {
    final calls = <String>[];
    final api = _FakeApiClient((endpoint, {headers, requireAuth = true}) async {
      calls.add('$endpoint|auth=$requireAuth');
      return _json(200, {
        'data': {
          'requests': [
            {
              'id': 'req-123',
              'amount': '25.00',
              'currency': 'GHS',
              'status': 'PENDING',
              'requester': {'username': 'kwame'},
            },
          ],
        },
      });
    });

    await tester.pumpWidget(
      _testApp(api: api, home: const PaymentRequestsScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('kwame'), findsOneWidget);
    expect(find.text('GH₵ 25.00'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(calls, contains('/payment-requests?direction=INCOMING|auth=true'));
  });

  testWidgets('public link detail lookup does not require an authenticated token',
      (tester) async {
    final calls = <String>[];
    final api = _FakeApiClient((endpoint, {headers, requireAuth = true}) async {
      calls.add('$endpoint|auth=$requireAuth');
      return _json(200, {
        'data': {
          'request': {
            'publicId': 'REQ-123',
            'amount': '70.00',
            'currency': 'GHS',
            'status': 'PENDING',
            'requesterDisplayName': 'Ama Boateng',
            'description': 'Dinner',
            'shareUrl': 'https://pay.azaman.test/request/demo-token',
          },
        },
      });
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
    expect(find.text('Dinner'), findsOneWidget);
    expect(
      calls,
      contains('/payment-requests/public/demo-token|auth=false'),
    );
    expect(find.textContaining('Payment is not initiated by opening'), findsOneWidget);
  });

  testWidgets('missing public request renders an error, never a fake paid state',
      (tester) async {
    final api = _FakeApiClient((endpoint, {headers, requireAuth = true}) async {
      return _json(404, {'message': 'Request not found'});
    });

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
}
