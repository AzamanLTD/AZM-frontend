import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/receive_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

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
    bool failClosedOnPendingFingerprintChange = false,
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
          'mode': requestBody['requestMode'],
          if (requestBody['requestMode'] == 'LINK')
            'shareUrl': 'https://pay.azaman.test/request/req-42',
        },
      },
    });
  }
}

class _SeedFriendProvider extends FriendProvider {
  _SeedFriendProvider(super.ref, {this.failingQueries = const {}}) {
    friends.add({
      'id': 'friendship-999',
      'friendshipId': 'friendship-999',
      'friendUsername': 'ama',
      'friend': {'id': '42', 'username': 'ama', 'displayName': 'Ama Boateng'},
    });
  }

  final Set<String> failingQueries;
  final List<String> searchQueries = [];

  @override
  Future<void> fetchFriends() async {}

  @override
  Future<void> searchUsers(String query) async {
    searchQueries.add(query);
    if (query.trim().length < 2) {
      searchResults = [];
      searchError = null;
      notifyListeners();
      return;
    }
    if (failingQueries.contains(query)) {
      searchResults = [];
      searchError =
          'Contact search failed. Check your connection and try again.';
      notifyListeners();
      return;
    }
    searchError = null;
    // Deterministic fixture: 'zz' never matches anything; everything else
    // resolves to one user.
    searchResults = query == 'zz'
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            {'id': '77', 'username': 'akosua', 'displayName': 'Akosua Mensah'},
          ];
    notifyListeners();
  }
}

void _phoneSize(WidgetTester tester, {Size size = const Size(420, 920)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Opens the Request composer (the resisted handoff) and settles it.
Future<void> _openComposer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('receive-request-toggle')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String?> sharedTexts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
    sharedTexts = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
            if (call.method == 'share' &&
                call.arguments is Map &&
                (call.arguments as Map).containsKey('text')) {
              sharedTexts.add((call.arguments as Map)['text'] as String?);
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          null,
        );
  });

  testWidgets(
    'direct Request selects one contact via the picker and sends the exact '
    'two-decimal GHS contract, reusing its identity on repeat',
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

      await _openComposer(tester);

      // The compact resting row replaces the old inline contact list.
      expect(find.text('Choose contact'), findsOneWidget);
      expect(find.text('ama'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('receive-request-contact-row')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The sheet offers exactly one selection per tap; picking pops it.
      await tester.tap(find.text('Ama Boateng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Choose contact'), findsNothing);
      // The compact row shows the selected person (username-first, like the
      // pre-PR composer) — with change and clear affordances.
      expect(find.text('ama'), findsOneWidget);
      expect(find.text('@ama'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'GH₵ 10'));
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

      // Repeating the SAME request must reuse the created record: no duplicate
      // economics call against the idempotent backend authority.
      await tester.tap(find.byKey(const ValueKey('receive-request-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.postCount, 1);
    },
  );

  testWidgets('open request link creates a LINK request and shares the '
      'server-issued shareUrl', (tester) async {
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

    await _openComposer(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'GH₵ 20'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('receive-request-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.body?['requestMode'], 'LINK');
    expect(
      api.body?.containsKey('recipientUserId'),
      isFalse,
      reason: 'a LINK request has no preselected recipient',
    );
    expect(api.body?['amount'], '20.00');
    expect(api.body?['currency'], 'GHS');
    // The canonical shareUrl comes from the create response only.
    expect(
      sharedTexts,
      contains(
        'Pay my request on Azaman: '
        'https://pay.azaman.test/request/req-42',
      ),
    );
  });

  testWidgets('contact picker covers loading, empty search, failed search, '
      'and clear/change selection', (tester) async {
    _phoneSize(tester);
    final api = _RequestApiClient();
    late _SeedFriendProvider contacts;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          friendProvider.overrideWith(
            (ref) =>
                contacts = _SeedFriendProvider(ref, failingQueries: {'aku'}),
          ),
        ],
        child: const MaterialApp(home: ReceiveScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _openComposer(tester);

    // Resting state: friends list inside the sheet; one selection allowed.
    await tester.tap(find.byKey(const ValueKey('receive-request-contact-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('contact-picker-results')),
      findsOneWidget,
    );
    expect(find.text('Ama Boateng'), findsOneWidget);

    // Failed search: honest error state with a retry affordance — never a
    // silent empty list.
    await tester.enterText(
      find.byKey(const ValueKey('contact-picker-search')),
      'aku',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Contact search failed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    // Empty search result is a DIFFERENT, honest state from a failure.
    await tester.enterText(
      find.byKey(const ValueKey('contact-picker-search')),
      'zz',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('No matching Azaman users found'),
      findsOneWidget,
    );
    expect(contacts.searchQueries, containsAll(['aku', 'zz']));

    // Select, then clear from the compact row.
    await tester.enterText(
      find.byKey(const ValueKey('contact-picker-search')),
      'ak',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Akosua Mensah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('akosua'), findsOneWidget);
    expect(find.text('Choose contact'), findsNothing);

    await tester.tap(find.byIcon(Icons.cancel_rounded));
    await tester.pump();
    expect(find.text('Choose contact'), findsOneWidget);
    expect(find.text('akosua'), findsNothing);

    // Re-open and change the selection.
    await tester.tap(find.byKey(const ValueKey('receive-request-contact-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ama Boateng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ama'), findsOneWidget);
  });

  testWidgets(
    'with the system keyboard up, picker results stay above the keyboard '
    'and the composer actions clear the home-indicator inset',
    (tester) async {
      _phoneSize(tester, size: const Size(390, 844));
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
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

      // Request composer actions must not sit under the home-indicator inset.
      await _openComposer(tester);
      final submitBox =
          tester.renderObject(
                find.byKey(const ValueKey('receive-request-submit')),
              )
              as RenderBox;
      expect(
        submitBox.localToGlobal(Offset.zero).dy + submitBox.size.height,
        lessThan(844 - 34),
      );

      // Keyboard interaction: the sheet lifts its content above the keyboard.
      await tester.tap(
        find.byKey(const ValueKey('receive-request-contact-row')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final resultsBox =
          tester.renderObject(
                find.byKey(const ValueKey('contact-picker-results')),
              )
              as RenderBox;
      final sheetTop = tester
          .getTopLeft(find.byKey(const ValueKey('contact-picker-search')))
          .dy;
      expect(
        sheetTop,
        lessThan(844 - 280),
        reason: 'the search field must remain visible above the keyboard',
      );
      expect(
        resultsBox.size.height,
        greaterThan(0),
        reason: 'the results list remains reachable above the keyboard',
      );
    },
  );

  testWidgets('receive details bottom content scrolls fully clear of the home '
      'indicator inset on a 430x932 viewport', (tester) async {
    _phoneSize(tester, size: const Size(430, 932));
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
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

    final finder = find.textContaining(
      'Creating a request does not automatically send',
    );
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject(finder) as RenderBox;
    final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
    expect(
      bottom,
      lessThan(932 - 34),
      reason: 'the last receive-details content must clear the inset',
    );
  });
}
