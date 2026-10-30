// =============================================================================
// AZAMAN — UNIFIED SEND: CHAT UNIFICATION + CONVERGENCE TESTS
//
// Group 9-10: the chat's money surface and the shared composer converge on
// ONE identity contract:
//   • SendRecipient.friend carries the conversation's authoritative
//     identity — the friendshipId is the wire key, the username is the
//     participant handle, and no AZM ID is ever guessed or fabricated
//   • the composer renders a friend-seeded recipient as pre-verified
//     (no lookup round-trip, no placeholder ID anywhere)
//   • chat transfer records render HONESTLY: status-driven, with
//     request actions only for the pending incoming case
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/chat_money_card.dart';

import '../support/money_access_test_support.dart';

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
    friends = [];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

User _user() => User(
  id: '7',
  username: 'me',
  email: 'me@example.com',
  token: 'tok',
  role: 'USER',
  azamanId: 'AZM-999999999',
  availableBalance: 50.0,
);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  final tp = ThemeProvider();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// The money card reads the app's money gate, so the harness supplies the
/// scope production always has — and an unlocked session, because these
/// contracts are about which ACTIONS a status shows.
Widget _material(Widget child) => ProviderScope(
  overrides: [unlockedMoneyAccess()],
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SendRecipient.friend carries the conversation identity verbatim — '
    'the friendshipId is the wire key and no AZM ID is guessed',
    (tester) async {
      final r = SendRecipient.friend(username: 'ama', friendshipId: 'fs-42');

      expect(
        r.friendshipId,
        'fs-42',
        reason: 'the canonical rail keys on the friendshipId',
      );
      expect(r.username, 'ama');
      expect(
        r.azamanId,
        isNull,
        reason: 'a chat seed never fabricates an AZM ID',
      );
      expect(
        r.canReceive,
        isTrue,
        reason: 'an accepted friendship is transfer-capable',
      );
    },
  );

  testWidgets(
    'a chat-opened Send shows the participant pre-verified — confirmed '
    'recipient, no lookup, no placeholders',
    (tester) async {
      var lookups = 0;
      await _pump(
        tester,
        SendMoneyScreen.toFriend(
          recipient: SendRecipient.friend(
            username: 'ama',
            friendshipId: 'fs-42',
          ),
          // The composer must never resolve a friend seed through the
          // directory — the friendship is already authoritative.
          discovery: _CountingDiscovery(lookups: () => lookups++),
          sendOverride: (friendshipId, amount, reference, token) async {
            expect(friendshipId, 'fs-42');
            return {'success': true};
          },
        ),
      );

      expect(
        find.byKey(const ValueKey('send-recipient-confirmed')),
        findsOneWidget,
      );
      expect(find.text('@ama'), findsWidgets);
      expect(
        find.byKey(const ValueKey('send-not-connected-chip')),
        findsNothing,
      );
      expect(lookups, 0, reason: 'a friend seed needs no directory lookup');
      expect(find.byKey(const ValueKey('send-friend-chip')), findsOneWidget);
    },
  );

  testWidgets(
    'chat transfer records are status-honest: completed and failed carry '
    'no actions; only a pending incoming REQUEST shows Accept / Decline',
    (tester) async {
      // Completed transfer — no actions, honest label.
      await tester.pumpWidget(
        _material(
          ChatMoneyCard(
            amount: 5,
            currency: 'USDC',
            isMe: true,
            contactName: 'Ama',
            timestamp: DateTime(2026, 10, 20),
            status: 'completed',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Accept & Pay'), findsNothing);
      expect(find.text('Decline'), findsNothing);

      // Failed transfer — honest failure, no success paint.
      await tester.pumpWidget(
        _material(
          ChatMoneyCard(
            amount: 5,
            currency: 'USDC',
            isMe: true,
            contactName: 'Ama',
            timestamp: DateTime(2026, 10, 20),
            status: 'failed',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);

      // Pending incoming request — Accept / Decline available.
      var accepted = 0, declined = 0;
      await tester.pumpWidget(
        _material(
          ChatMoneyCard(
            amount: 5,
            currency: 'USDC',
            isMe: false,
            contactName: 'Ama',
            timestamp: DateTime(2026, 10, 20),
            status: 'pending',
            isRequest: true,
            onAccept: () => accepted++,
            onDecline: () => declined++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Accept & Pay'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      await tester.tap(find.text('Decline'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(declined, 1);
      expect(accepted, 0);

      // A pending incoming TRANSFER (not a request) needs no actions —
      // money that already arrived is never re-accepted.
      await tester.pumpWidget(
        _material(
          ChatMoneyCard(
            amount: 5,
            currency: 'USDC',
            isMe: false,
            contactName: 'Ama',
            timestamp: DateTime(2026, 10, 20),
            status: 'pending',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.text('Accept & Pay'),
        findsNothing,
        reason: 'money that already arrived is never re-accepted',
      );
    },
  );
}

/// A discovery service that counts any lookup attempt — the chat-seeded
/// composer must never need one.
class _CountingDiscovery extends RecipientDiscoveryService {
  _CountingDiscovery({required this.lookups}) : super();

  final void Function() lookups;

  @override
  Future<AzmLookupOutcome> lookupByAzamanId(
    String raw, {
    String? myAzamanId,
  }) async {
    lookups();
    return const AzmLookupOutcome(AzmLookupStatus.notFound);
  }
}
