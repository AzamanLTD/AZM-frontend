// =============================================================================
// AZAMAN — UNIFIED SEND: RECIPIENT SELECTOR + QR ROUTING TESTS
//
// Covers work-order groups 3, 4 and 5:
//   • friend list identity + local filter (no network for friends)
//   • directory search with SAFE query encoding; friend vs not-connected
//   • AZM-ID lookup: found / self / not-found / malformed honest states
//   • stale async lookups never overwrite the newest query
//   • QR: ONLY the audited person-identity contract parses — reservation
//     check-in / dine-in table tokens are rejected as payment identity
//   • self-recipient and missing-canonical-ID rejection; placeholders are
//     structurally impossible to construct into the selection
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/send/recipient_selector_sheet.dart';

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);

  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {}
}

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    friends = [
      {
        'friendshipId': 'fs-1',
        'friend': {'id': 101, 'username': 'ama', 'fullName': 'Ama Mensah'},
      },
      {
        'friendshipId': 'fs-2',
        'friend': {'id': 102, 'username': 'kojo', 'fullName': 'Kojo Boateng'},
      },
    ];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

class _ScriptedApi {
  final requests = <http.Request>[];
  FutureOr<http.Response> Function(http.Request) respond;

  _ScriptedApi(this.respond);

  late final ApiClient api = ApiClient(
    client: MockClient((request) async {
      requests.add(request);
      return respond(request);
    }),
  );
}

User _user() => User(
  id: '7',
  username: 'me',
  email: 'me@example.com',
  token: 'tok',
  role: 'USER',
  azamanId: 'AZM-999999999',
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> _mockSecureStorage() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
}

/// Pumps a host whose only job is opening the selector sheet.
Future<void> _openSheet(
  WidgetTester tester, {
  required _ScriptedApi scripted,
}) async {
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  await _mockSecureStorage();
  final tp = (await tester.runAsync<ThemeProvider>(
    () async => ThemeProvider(),
  ))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => showRecipientSelectorSheet(
                  context,
                  discovery: RecipientDiscoveryService(api: scripted.api),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

Future<void> _typeQuery(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const ValueKey('send-selector-search')), q);
  await tester.pump(const Duration(milliseconds: 400)); // debounce
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'friends render with identity info and filter locally — no network '
    'while filtering accepted friends',
    (tester) async {
      final scripted = _ScriptedApi(
        (req) => throw http.ClientException('no network'),
      );
      await _openSheet(tester, scripted: scripted);

      expect(find.text('@ama'), findsOneWidget);
      expect(find.text('@kojo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('send-selector-row-ama')),
        findsOneWidget,
      );
      expect(
        scripted.requests,
        isEmpty,
        reason: 'local filter must be offline',
      );

      await _typeQuery(tester, 'ko');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send-selector-row-ama')), findsNothing);
      expect(
        find.byKey(const ValueKey('send-selector-row-kojo')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'directory search encodes the query safely and resolves friend matches '
    'to their friendship; unmatched hits are honestly not connected',
    (tester) async {
      final scripted = _ScriptedApi((req) {
        final q = Uri.parse(req.url.toString()).queryParameters['q'];
        if (q == 'ama o') {
          return _json({
            'users': [
              {'id': 101, 'username': 'ama', 'profilePictureUrl': null},
              {'id': 555, 'username': 'stranger', 'profilePictureUrl': null},
            ],
          });
        }
        return _json({'users': []});
      });
      await _openSheet(tester, scripted: scripted);

      await _typeQuery(tester, 'ama o');
      await tester.pumpAndSettle();

      // Safe encoding: user text never interpolated raw — the space must be
      // percent- or plus-encoded, never a literal.
      final wireUrl = scripted.requests
          .map((r) => r.url.toString())
          .where((u) => u.contains('q='))
          .first;
      final q = Uri.parse(wireUrl).queryParameters['q'];
      expect(q, 'ama o', reason: 'the wire query decodes to the typed text');
      expect(
        wireUrl.contains('q=ama o'),
        isFalse,
        reason: 'raw user text must never appear unencoded',
      );

      final amaRow = find.byKey(const ValueKey('send-selector-row-ama'));
      expect(amaRow, findsOneWidget);
      expect(
        find.descendant(of: amaRow, matching: find.text('Friend')),
        findsOneWidget,
        reason: 'directory hit matched to the accepted friendship fs-1',
      );
      final strangerRow = find.byKey(
        const ValueKey('send-selector-row-stranger'),
      );
      expect(strangerRow, findsOneWidget);
      expect(
        find.descendant(of: strangerRow, matching: find.text('Not connected')),
        findsOneWidget,
      );

      await tester.tap(amaRow);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'AZM-ID lookup resolves an identity honestly — no friendship exists on '
    'this surface, so the hit is not send-capable',
    (tester) async {
      final scripted = _ScriptedApi((req) {
        if (req.url.path.contains('/users/lookup/AZM-123456789')) {
          return _json({
            'user': {
              'azamanId': 'AZM-123456789',
              'displayName': 'Ama Mensah',
              'avatar': null,
            },
          });
        }
        return _json({'error': 'unexpected ${req.url}'}, 500);
      });
      await _openSheet(tester, scripted: scripted);

      await _typeQuery(tester, 'AZM-123456789');
      await tester.pumpAndSettle();

      expect(find.text('AZM ID MATCH'), findsOneWidget);
      // PR #165 review finding 4: the identity endpoint returned NO username
      // (only azamanId + displayName). The row leads with the display name
      // and shows the REAL AZM ID — the display name is never fabricated
      // into an `@handle`.
      // Two honest rows share the display name: the accepted FRIEND (with
      // its friendship) and the AZM-ID hit (display-only, not connected).
      expect(
        find.text('Ama Mensah'),
        findsWidgets,
        reason:
            'the friend row and the AZM hit row both lead with the '
            'real display name',
      );
      expect(
        find.text('AZM-123456789'),
        findsWidgets,
        reason:
            'the real AZM ID is the identity line (plus the query '
            'field echoing it)',
      );
      expect(
        find.text('@Ama Mensah'),
        findsNothing,
        reason: 'a displayName must never become an @handle',
      );
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'the query field still echoes the typed AZM ID',
      );
      expect(find.text('Not connected'), findsOneWidget);
      expect(
        scripted.requests.first.url.path,
        contains('/users/lookup/AZM-123456789'),
      );
    },
  );

  testWidgets(
    "self, not-found and network states are honest — a self AZM ID and an "
    'unreachable directory never render a selectable identity',
    (tester) async {
      final scripted = _ScriptedApi((req) {
        if (req.url.path.contains('/users/lookup/')) {
          return _json({'code': 'USER_NOT_FOUND'}, 404);
        }
        throw http.ClientException('offline');
      });
      await _openSheet(tester, scripted: scripted);

      // Self: my own AZM ID (from the auth user) is rejected client-side.
      await _typeQuery(tester, 'AZM-999999999');
      await tester.pumpAndSettle();
      expect(find.text("That's your own AZM ID."), findsOneWidget);
      expect(
        scripted.requests,
        isEmpty,
        reason: 'self check precedes the call',
      );

      // Not found via the typed backend code.
      await _typeQuery(tester, 'AZM-123456789');
      await tester.pumpAndSettle();
      expect(find.text('No active account with that AZM ID.'), findsOneWidget);

      // Directory network failure: honest, retryable, never a fake identity.
      await _typeQuery(tester, 'nobody');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not reach the directory. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('send-selector-row-nobody')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'empty results are honest "no matches" — never a placeholder row',
    (tester) async {
      final scripted = _ScriptedApi((req) => _json({'users': []}));
      await _openSheet(tester, scripted: scripted);

      await _typeQuery(tester, 'zz');
      await tester.pumpAndSettle();
      expect(
        find.text('No matches. You can send to accepted friends.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a stale async response NEVER overwrites the newest query results',
    (tester) async {
      final gates = <String, Completer<http.Response>>{};
      final scripted = _ScriptedApi((req) {
        final q =
            Uri.parse(req.url.toString()).queryParameters['q'] ?? req.url.path;
        final gate = gates[q] ??= Completer<http.Response>();
        return gate.future;
      });
      await _openSheet(tester, scripted: scripted);

      // Query A starts but does not answer.
      await _typeQuery(tester, 'aaaa');
      gates['aaaa']!.complete(
        _json({
          'users': [
            {'id': 1, 'username': 'stale_user'},
          ],
        }),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Query B supersedes it.
      await _typeQuery(tester, 'bbbb');
      gates['bbbb']!.complete(
        _json({
          'users': [
            {'id': 2, 'username': 'fresh_user'},
          ],
        }),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('send-selector-row-fresh_user')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('send-selector-row-stale_user')),
        findsNothing,
        reason: 'the stale generation must be discarded',
      );
    },
  );

  test('QR routing: ONLY the audited person-identity contract parses', () {
    // The audited personal profile QR (qr_profile_popup ↔ scanner).
    expect(personalQrUsername('azaman://user/ama'), 'ama');
    expect(personalQrUsername('azaman://user/@kojo'), 'kojo');
    expect(personalQrUsername('@ama'), 'ama');

    // Reservation check-in / dine-in table tokens are DIFFERENT contracts —
    // they must never resolve as a personal payment identity.
    expect(personalQrUsername('azaman://checkin/RSV-123'), isNull);
    expect(personalQrUsername('azaman://table/5'), isNull);
    expect(personalQrUsername('azaman://biz/INV-77'), isNull);
    expect(
      personalQrUsername('AZM-123456789'),
      isNull,
      reason: 'an AZM ID displayed as text is not a person QR payload',
    );
    expect(personalQrUsername('https://example.com/x'), isNull);
  });

  test('model: placeholders are structurally impossible to construct', () {
    void expectRejected(String? bad) {
      expect(
        () => SendRecipient(
          username: 'ama',
          source: SendRecipientSource.friend,
          azamanId: bad,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'the mask "$bad" must never live inside a recipient',
      );
    }

    expectRejected('AZM-•••');
    expectRejected('AZM-');
    expectRejected('');
    expectRejected('AZM-12345'); // not 9 digits — a truncated id is a mask

    // The empty username (a guest fallback) is impossible too.
    expect(
      () => SendRecipient(username: '', source: SendRecipientSource.friend),
      throwsA(isA<AssertionError>()),
    );
  });
}
