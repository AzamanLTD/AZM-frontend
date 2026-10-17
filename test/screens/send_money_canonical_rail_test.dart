// =============================================================================
// r43 — Send Money canonical-rail contract (Workstream C, P0 fix).
//
// The redesigned Send Money screen shipped calling routes that DO NOT exist
// (POST /finance/internal-transfer, GET /users/lookup?identifier=) while
// fabricating 'AZM-•••' identifiers for contact rows. The ONLY user-to-user
// transfer rail is friendship-scoped: POST /api/friends/transfer/send
// { friendshipId, amount } via FriendService.sendFunds.
//
// This suite pins the truthful wiring end-to-end at the widget level:
//   1. Contact sends go to the canonical rail with the row's REAL
//      friendshipId — and nothing fabricated ever renders.
//   2. AZM-ID lookups resolve through GET /users/lookup/:azamanId; the
//      caller's friendship state decides sendability.
//   3. PENDING / stranger recipients FAIL CLOSED: no amount UI, no send.
//   4. Username search hits the real /friends/search rail with truthful
//      status tags; an ACCEPTED hit resolves its friendshipId through the
//      paginated friends rail before the send unlocks.
//   5. Lookups that cannot prove a friendship never invent one.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/friend_service.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

User _sessionUser({double balance = 250.0}) => User(
      id: '1',
      username: 'me',
      email: 'me@example.com',
      token: 'test-token',
      role: 'USER',
      azamanId: 'AZM-000111111',
      availableBalance: balance,
    );

/// AuthProvider with the network-bound lifecycle (fetchUserDetails,
/// syncFcmToken) stubbed — the screen only reads .user.
class _SeedAuthProvider extends AuthProvider {
  _SeedAuthProvider({required super.ref, required User user}) {
    setUser(user);
  }

  @override
  Future<void> fetchUserDetails() async {}

  @override
  Future<void> syncFcmToken() async {}
}

/// FriendProvider with refreshAll stubbed (no socket, no HTTP prefetch) —
/// tests seed .friends directly.
class _SeedFriendProvider extends FriendProvider {
  _SeedFriendProvider(super.ref, List<Map<String, dynamic>> rows) {
    friends.addAll(rows);
  }

  @override
  Future<void> refreshAll() async {}
}

/// The rail under test: every FriendService HTTP call this screen can make.
class _RailApiClient extends ApiClient {
  _RailApiClient({
    this.lookupStatus = 200,
    this.lookupUser,
    this.searchHits = const [],
    this.friendsPage = const [],
  });

  final int lookupStatus;
  final Map<String, dynamic>? lookupUser;
  final List<Map<String, dynamic>> searchHits;
  final List<Map<String, dynamic>> friendsPage;

  final List<String> getCalls = [];
  final List<String> postPaths = [];
  final List<Map<String, dynamic>> postBodies = [];
  final List<String> operationTypes = [];

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    getCalls.add(endpoint);

    if (endpoint.startsWith('/users/lookup/')) {
      if (lookupStatus == 200 && lookupUser != null) {
        return _json(200, {
          'success': true,
          'data': {'user': lookupUser},
        });
      }
      return _json(lookupStatus, {
        'success': false,
        'message': 'User not found.',
        'errorCode': 'USER_NOT_FOUND',
      });
    }
    if (endpoint.startsWith('/friends/search')) {
      return _json(200, {'users': searchHits});
    }
    if (endpoint.startsWith('/friends')) {
      return _json(200, {
        'friends': friendsPage,
        'hasMore': false,
        'nextCursor': null,
      });
    }
    return _json(404, {'success': false, 'message': 'no stub'});
  }

  @override
  Future<http.Response> postFinancial(
    String path,
    Map<String, dynamic> requestBody, {
    required String operationType,
    FinancialOperationRef? ref,
    bool requireAuth = true,
    Map<String, String>? headers,
  }) async {
    postPaths.add(path);
    postBodies.add(Map<String, dynamic>.from(requestBody));
    operationTypes.add(operationType);
    return _json(201, {
      'data': {
        'transaction': {'id': 'tx-1', 'status': 'COMPLETED'},
      },
    });
  }
}

Widget _testApp({required List<Override> overrides, Widget? home}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: home ?? const SendMoneyScreen()),
    );

void _phoneSize(WidgetTester tester, {Size size = const Size(420, 920)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpReady(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(_testApp(overrides: overrides));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.search_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _enterAmountAndSend(WidgetTester tester, String amount) async {
  await tester.enterText(
      find.byKey(const ValueKey('send-amount-field')), amount);
  await tester.pump();
  final sendButton = find.widgetWithText(ElevatedButton, 'Send');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contactFriendRow = {
    'id': 'fs-1',
    'friendshipId': 'fs-1',
    'friendUsername': 'adjoa',
    'friend': {
      'id': 9,
      'username': 'adjoa',
      'displayName': 'Adjoa Mensah',
      'profilePictureUrl': null,
    },
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  });

  tearDown(() {
    FriendService.testClientOverride = null;
  });

  testWidgets(
      'contact send posts to the canonical friendship rail with the row\'s '
      'REAL friendshipId — no fabricated identifier anywhere',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient();
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith(
          (ref) => _SeedFriendProvider(ref, [contactFriendRow])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    // The contact row renders the username truthfully — the friends payload
    // carries NO azamanId, so no AZM line may appear on the row, and the
    // fabricated 'AZM-•••' is gone entirely.
    expect(find.text('adjoa'), findsOneWidget);
    expect(find.textContaining('AZM-\u2022\u2022\u2022'), findsNothing);

    await tester.tap(find.text('adjoa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Recipient card: username present; NO AZM ID line (none was returned
    // by any rail); the send is unlocked by the row's real friendshipId.
    expect(find.text('adjoa'), findsOneWidget);
    expect(find.text('Adjoa Mensah'), findsNothing); // card shows username
    expect(find.textContaining('AZM-123456789'), findsNothing);

    await _enterAmountAndSend(tester, '12.5');

    // THE canonical rail — the exact call the friends-hub transfer sheet
    // makes, durable operation namespace and all.
    expect(rail.postPaths, ['/friends/transfer/send']);
    expect(rail.postBodies.single['friendshipId'], 'fs-1');
    expect(rail.postBodies.single['amount'], 12.5);
    expect(rail.operationTypes.single, 'friend.transfer.send.fs-1');
    // The dead routes of the broken screen are never touched.
    expect(
        rail.getCalls.where((c) => c.contains('internal-transfer')), isEmpty);
    expect(rail.getCalls.where((c) => c.contains('identifier=')), isEmpty);
    expect(find.textContaining('Sent'), findsOneWidget);
  });

  testWidgets(
      'AZM-ID lookup resolves through GET /users/lookup/:id and an ACCEPTED '
      'friendship unlocks the send with the rail\'s friendshipId',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(lookupUser: {
      'azamanId': 'AZM-123456789',
      'displayName': 'Ama Owusu',
      'avatar': null,
      'friendship': {'friendshipId': 'fs-42', 'status': 'ACCEPTED'},
    });
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'AZM-123456789');

    expect(rail.getCalls.first, '/users/lookup/AZM-123456789');
    expect(find.text('Ama Owusu'), findsOneWidget);
    // The AZM ID shown is the REAL one the rail returned.
    expect(find.text('AZM-123456789'), findsOneWidget);

    await _enterAmountAndSend(tester, '5');

    expect(rail.postPaths, ['/friends/transfer/send']);
    expect(rail.postBodies.single['friendshipId'], 'fs-42');
    expect(rail.postBodies.single['amount'], 5.0);
  });

  testWidgets(
      'a PENDING friendship FAILS CLOSED: truthful status line, no amount '
      'field, no rail call',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(lookupUser: {
      'azamanId': 'AZM-123456789',
      'displayName': 'Ama Owusu',
      'avatar': null,
      'friendship': {'friendshipId': 'fs-42', 'status': 'PENDING'},
    });
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'AZM-123456789');

    expect(find.text('Ama Owusu'), findsOneWidget);
    expect(
        find.text('Friend request pending — you can send once they accept.'),
        findsOneWidget);
    expect(find.text('Amount (USDC)'), findsNothing);
    // No send ACTION — the appbar still says 'Send' as the screen title.
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsNothing);
    expect(rail.postPaths, isEmpty);
  });

  testWidgets(
      'username search hits the REAL /friends/search rail; multiple results '
      'render with truthful status tags',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(searchHits: [
      {
        'id': 5,
        'username': 'amao',
        'friendshipStatus': 'ACCEPTED',
        'profilePictureUrl': null,
      },
      {
        'id': 6,
        'username': 'kojo',
        'friendshipStatus': null,
        'profilePictureUrl': null,
      },
    ]);
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'ama');

    expect(rail.getCalls.first, '/friends/search?q=ama');
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('amao'), findsOneWidget);
    expect(find.text('kojo'), findsOneWidget);
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets(
      'a stranger hit FAILS CLOSED — truthful reason, no amount UI, no send',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(searchHits: [
      {
        'id': 6,
        'username': 'kojo',
        'friendshipStatus': null,
        'profilePictureUrl': null,
      },
    ]);
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'kojo');
    await tester.tap(find.text('kojo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('kojo'), findsOneWidget);
    expect(
        find.text(
            'Only friends can receive transfers. Add them as a friend first.'),
        findsOneWidget);
    expect(find.text('Amount (USDC)'), findsNothing);
    // No send ACTION — the appbar still says 'Send' as the screen title.
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsNothing);
    expect(rail.postPaths, isEmpty);
  });

  testWidgets(
      'an ACCEPTED search hit resolves its friendshipId through the '
      'paginated friends rail before the send unlocks',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(
      searchHits: [
        {
          'id': 7,
          'username': 'esi',
          'friendshipStatus': 'ACCEPTED',
          'profilePictureUrl': null,
        }
      ],
      friendsPage: [
        {
          'id': 'fs-7',
          'friendshipId': 'fs-7',
          'friendUsername': 'esi',
          'friend': {'id': 7, 'username': 'esi'},
        }
      ],
    );
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'esi');
    await tester.tap(find.text('esi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The resolver paged the real /friends rail.
    expect(rail.getCalls.where((c) => c.startsWith('/friends?')), isNotEmpty);
    expect(find.text('esi'), findsOneWidget);

    await _enterAmountAndSend(tester, '3');

    expect(rail.postPaths, ['/friends/transfer/send']);
    expect(rail.postBodies.single['friendshipId'], 'fs-7');
  });

  testWidgets(
      'USER_NOT_FOUND fails closed with the truthful reason — nothing '
      'invented, nothing sent',
      (tester) async {
    _phoneSize(tester);
    final rail = _RailApiClient(lookupStatus: 404);
    FriendService.testClientOverride = rail;

    await _pumpReady(tester, [
      friendProvider.overrideWith((ref) => _SeedFriendProvider(ref, [])),
      authProvider.overrideWith(
          (ref) => _SeedAuthProvider(ref: ref, user: _sessionUser())),
    ]);

    await _searchFor(tester, 'AZM-999999999');

    expect(rail.getCalls.first, '/users/lookup/AZM-999999999');
    expect(find.text('No user with that AZM ID.'), findsOneWidget);
    expect(find.text('Amount (USDC)'), findsNothing);
    expect(rail.postPaths, isEmpty);
  });
}
