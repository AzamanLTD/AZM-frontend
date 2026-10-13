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

class _TwoFriendProvider extends FriendProvider {
  _TwoFriendProvider(Ref ref) : super(ref) {
    friends.addAll([
      {
        'id': 'friendship-999',
        'friendshipId': 'friendship-999',
        'friendUsername': 'ama',
        'friend': {'id': '42', 'username': 'ama'},
      },
      {
        'id': 'friendship-1000',
        'friendshipId': 'friendship-1000',
        'friendUsername': 'kojo',
        'friend': {'id': '77', 'username': 'kojo'},
      },
    ]);
  }

  @override
  Future<void> fetchFriends() async {}
}

class _EmptyFriendProvider extends FriendProvider {
  _EmptyFriendProvider(Ref ref) : super(ref);

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

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  });


  testWidgets('direct Request creates a standalone payment request and reuses its identity on repeat',
      (tester) async {
    _phoneSize(tester);
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
    // New contact-picker contract: the composer surface shows ONE compact
    // select-contact row, never a contact list under the keypad. The row
    // opens the searchable sheet; choosing commits and closes it.
    final composerSurface = find.ancestor(
      of: find.byKey(const ValueKey('receive-request-contact-row')),
      matching: find.byType(ReceiveScreen),
    );
    expect(
      find.descendant(
        of: composerSurface,
        matching: find.byType(ListTile),
      ),
      findsNothing,
      reason: 'the composer must not carry a contact list under the keypad',
    );
    await tester.tap(find.byKey(const ValueKey('receive-request-contact-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.ancestor(
        of: find.text('ama'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Sheet closed; the row now shows the chosen contact.
    expect(find.text('Search name or username'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('receive-request-contact-row')),
        matching: find.text('ama'),
      ),
      findsOneWidget,
    );

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


testWidgets('composer keeps ONE recipient: choosing again replaces, search never clears a selection',
      (tester) async {
    _phoneSize(tester);
    final api = _RequestApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          friendProvider.overrideWith((ref) => _TwoFriendProvider(ref)),
        ],
        child: const MaterialApp(home: ReceiveScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('receive-request-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    Future<void> choose(String name) async {
      await tester.tap(
        find.byKey(const ValueKey('receive-request-contact-row')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.ancestor(
          of: find.text(name),
          matching: find.byType(ListTile),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await choose('ama');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('receive-request-contact-row')),
        matching: find.text('ama'),
      ),
      findsOneWidget,
    );

    // Changing the selection REOPENS the sheet with the current contact
    // checked and replacing it on the composer — never a second recipient.
    await choose('kojo');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('receive-request-contact-row')),
        matching: find.text('kojo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('receive-request-contact-row')),
        matching: find.text('ama'),
      ),
      findsNothing,
      reason: 'a direct request targets exactly ONE contact',
    );
  });

  testWidgets('empty-contact state is honest on both surface and sheet',
      (tester) async {
    _phoneSize(tester);
    final api = _RequestApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          friendProvider.overrideWith((ref) => _EmptyFriendProvider(ref)),
        ],
        child: const MaterialApp(home: ReceiveScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('receive-request-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // The unselected row invites selection; no fabricated contacts on the
    // composer surface.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('receive-request-contact-row')),
        matching: find.text('Select contact'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('receive-request-contact-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Your Azaman contacts will appear here'),
        findsOneWidget);
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
