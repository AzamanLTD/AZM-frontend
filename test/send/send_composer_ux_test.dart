// =============================================================================
// AZAMAN — UNIFIED SEND: COMPOSER UX + MONEY-ACTION SAFETY TESTS
//
// Covers work-order groups 1, 2, 8 and the chat-seed semantics:
//   • keypad → review shows the full contract before any commit
//   • a duplicate tap during flight NEVER double-commits
//   • an ambiguous (timeout/offline) outcome is NEVER reported as failed
//     or as success — retry is the only path onward
//   • an explicit insufficient-funds failure is honest — no success panel
//   • self-send, not-connected and session-less states fail closed BEFORE
//     the rail is touched
//   • a Send-Again AZM-ID seed resolves through the live identity contract
//     and honestly shows its connection state — never assumed transferable
// =============================================================================

import 'dart:async';
import 'dart:io';

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
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/home/activity_actions.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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
    ];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

User _user({String token = 'tok', String username = 'me'}) => User(
      id: '7',
      username: username,
      email: 'me@example.com',
      token: token,
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

SendRecipient _friendRecipient() => SendRecipient(
      username: 'ama',
      displayName: 'Ama Mensah',
      userId: 101,
      friendshipId: 'fs-1',
      source: SendRecipientSource.friend,
    );

Future<void> _mockSecureStorage() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
}

Future<ThemeProvider> _theme() async => ThemeProvider();

Widget _wrap(ThemeProvider tp, Widget screen, User authUser) => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(authUser)),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
      ],
      child: MaterialApp(home: screen),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  User? authUser,
}) async {
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  await _mockSecureStorage();
  final tp = await _theme();
  await tester.pumpWidget(_wrap(tp, screen, authUser ?? _user()));
  await tester.pumpAndSettle();
}

Future<void> _enterAmount(WidgetTester tester) async {
  await tester.tap(find.text('5').first);
  await tester.pump();
  await tester.tap(find.text('.').first);
  await tester.pump();
  await tester.tap(find.text('0').first);
  await tester.pump();
  await tester.tap(find.text('0').first);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'keypad → review shows the full contract, and a duplicate tap during '
      'flight commits EXACTLY once',
      (tester) async {
    var commits = 0;
    final gate = Completer<Map<String, dynamic>>();
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          expect(friendshipId, 'fs-1',
              reason: 'the wire key is the friendship');
          expect(token, 'tok');
          commits++;
          return gate.future;
        },
      ),
    );

    await _enterAmount(tester);

    // Compose CTA is enabled and honest about its action.
    final reviewCta = find.byKey(const ValueKey('send-cta-Review'));
    await tester.tap(reviewCta);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-review-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-review-amount')), findsOneWidget);
    expect(find.text('@ama'), findsWidgets);

    // Commit — then tap AGAIN mid-flight: the CTA relabels to 'Sending…'
    // and disables, so the duplicate tap can never re-enter _commit.
    final sendCta =
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC'));
    await tester.tap(sendCta);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-sending-banner')), findsOneWidget);
    final inFlightCta = find.byKey(const ValueKey('send-cta-Sending…'));
    expect(inFlightCta, findsOneWidget,
        reason: 'the in-flight CTA is disabled — no second commit is possible');
    await tester.tap(inFlightCta, warnIfMissed: false);
    await tester.pump();
    expect(commits, 1, reason: 'duplicate tap must never double-commit');

    gate.complete({'success': true});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    expect(commits, 1);
  });

  testWidgets(
      'a not-connected recipient can never reach review — the rail is '
      'untouched',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: SendRecipient(
          username: 'stranger',
          userId: 555,
          source: SendRecipientSource.directoryUser,
        ),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          throw StateError('the rail must never be touched');
        },
      ),
    );
    await _enterAmount(tester);
    expect(
        find.byKey(const ValueKey('send-not-connected-chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-review-card')), findsNothing,
        reason: 'a non-friend can never reach review');
    expect(commits, 0);
  });

  testWidgets(
      'a self-recipient is blocked at commit time with an honest message — '
      'no commit',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: SendRecipient(
          username: 'me',
          displayName: 'Myself',
          userId: 7,
          friendshipId: 'fs-x',
          source: SendRecipientSource.friend,
        ),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          throw StateError('the rail must never be touched');
        },
      ),
    );
    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC')));
    await tester.pumpAndSettle();
    expect(find.text("That's you — you can't send to yourself."),
        findsOneWidget);
    expect(commits, 0, reason: 'no commit for a self-send');
  });

  testWidgets(
      'a timeout is AMBIGUOUS — never a false failure, never a false '
      'success; Retry is the only onward path',
      (tester) async {
    var commits = 0;
    var first = true;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          if (first) {
            first = false;
            throw const SocketException('dropped');
          }
          return {'success': true};
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC')));
    await tester.pumpAndSettle();

    // Ambiguous banner, NOT a failure claim, NOT a success panel.
    expect(find.byKey(const ValueKey('send-unknown-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-error-text')), findsNothing);
    expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);

    // Retry: the same rail, and success lands.
    await tester.tap(find.byKey(const ValueKey('send-cta-Retry transfer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    expect(commits, 2, reason: 'a retry is a second real attempt');
  });

  testWidgets(
      'an explicit insufficient-funds failure is honest — no success panel',
      (tester) async {
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          throw ApiException(
              message: 'Insufficient funds', statusCode: 400);
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC')));
    await tester.pumpAndSettle();

    expect(find.text('Insufficient balance for this transfer.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);
    expect(find.byKey(const ValueKey('send-cta-Retry transfer')),
        findsOneWidget);
  });

  testWidgets(
      'a session-less composer fails closed — no commit without a live token',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          throw StateError('must not commit');
        },
      ),
      authUser: _user(token: ''),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Your session needs to be refreshed. Re-open Send to continue.'),
        findsOneWidget);
    expect(commits, 0, reason: 'a dead session must never reach the rail');
  });

  testWidgets(
      'a Send-Again AZM-ID seed resolves through the live identity contract '
      'and honestly shows its connection state — never assumed transferable',
      (tester) async {
    final api = ApiClient(
      client: MockClient((req) async {
        if (req.url.path.contains('/users/lookup/AZM-123456789')) {
          return http.Response(
              '{"user":{"azamanId":"AZM-123456789","username":"ama2",'
              '"displayName":"Ama Mensah","avatar":null}}',
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{"error":"unexpected"}', 500);
      }),
    );

    await _pump(
      tester,
      screen: SendMoneyScreen(
        initialRecipient: const ActivityRecipient(
            azamanId: 'AZM-123456789', displayName: 'Ama Mensah'),
        discovery: RecipientDiscoveryService(api: api),
        sendOverride: (friendshipId, amount, reference, token) async {
          throw StateError('an AZM-ID identity is never a friendship');
        },
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The resolved identity is shown with its AZM ID and honest state.
    expect(find.text('AZM-123456789 · @ama2'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('send-not-connected-chip')), findsOneWidget);

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-review-card')), findsNothing,
        reason: 'the honest seed can never reach review');
  });
}
