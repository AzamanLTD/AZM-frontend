// =============================================================================
// AZAMAN — WORKSTREAM B: SEND SURFACE GRAMMAR TESTS
//
// Send joins the shared transient-surface convention (rise-family route,
// X close, deliberate pull-to-dismiss — the Add Cash / Receive / Convert
// grammar). This suite pins the SURFACE contract only; the composition,
// money action, stages and financial guards keep their own suites.
//
//   • the X closes the surface — the stack returns to what was beneath
//   • a deliberate downward pull commits the dismissal; the stack returns
//   • a small pull is a rejected attempt — it springs back, nothing pops
//   • an UNKNOWN outcome is never silently dragged away: the pull is
//     rejected and the explicit pending-decision dialog appears instead
//     (PR #165 review finding 2, extended to the pull gesture)
//   • the header affordance is honest: X ("Close Send") at compose, the
//     back-to-edit arrow ("Back to edit") at review
// =============================================================================

import 'dart:async';

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
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

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

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
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

/// Pumps Home (base-marker) and pushes the Send surface on top, the way
/// production does (a stacked full-page surface). After this returns the
/// composer is mounted above [ValueKey('base-marker')].
Future<void> _pumpStacked(
  WidgetTester tester, {
  required Widget screen,
}) async {
  SharedPreferences.setMockInitialValues(
      {'azaman_theme': 1, 'biometric_lock_enabled': false});
  await _mockSecureStorage();
  final tp = ThemeProvider();
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
                key: const ValueKey('base-marker'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('base'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('base-marker')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('base-marker')), findsNothing,
      reason: 'the send surface covers the base page');
}

Widget _surface({PeerSendOverride? sendOverride}) => SendMoneyScreen.toFriend(
      fxRateOverride: 15.38,
      recipient: _friendRecipient(),
      sendOverride: sendOverride,
    );

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.descendant(
    of: find.byType(AmountKeypad),
    matching: find.text(key),
  );
  expect(finder, findsWidgets, reason: 'the keypad must offer "$key"');
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump();
}

/// Enters 5.00 USDC (the wheel's production default is GHS-first; roll to
/// USDC the way the composer suite does, then key the amount).
Future<void> _enterAmount(WidgetTester tester) async {
  final wheel = find.byKey(const ValueKey('send-amount-currency'));
  expect(wheel, findsOneWidget);
  await tester.drag(wheel, const Offset(0, -80));
  await tester.pumpAndSettle();
  for (final key in const ['5', '.', '0', '0']) {
    await _tapKey(tester, key);
  }
}

/// Deliberate slide into the commit path — incremental drag (real thumb
/// physics; a one-shot synthetic move leaves the gesture arena unresolved
/// against the surface's vertical recognizer).
Future<void> _slideToConfirm(WidgetTester tester) async {
  final slide = find.byType(SlideToConfirm);
  expect(slide, findsOneWidget);
  final topLeft = tester.getTopLeft(slide);
  final gesture = await tester.startGesture(topLeft + const Offset(28, 30));
  for (var i = 0; i < 24; i++) {
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the X closes the surface — the stack returns to base',
      (tester) async {
    await _pumpStacked(tester, screen: _surface());

    // Compose stage: the affordance is an X, honestly labelled.
    final x = find.byKey(const ValueKey('send-edit-back'));
    expect(x, findsOneWidget);
    expect(
      find.bySemanticsLabel('Close Send'),
      findsOneWidget,
      reason: 'the close affordance announces its action',
    );

    await tester.tap(x, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('base-marker')), findsOneWidget,
        reason: 'the surface popped; the base page is back');
  });

  testWidgets('a deliberate downward pull dismisses the surface',
      (tester) async {
    await _pumpStacked(tester, screen: _surface());

    // From the header band (static area, no child owns the vertical
    // gesture there), pull past the commit threshold: 260 raw px →
    // 143 px of resisted travel > 110 px threshold.
    await tester.dragFrom(const Offset(400, 30), const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('base-marker')), findsOneWidget,
        reason: 'the committed pull dismissed the surface');
  });

  testWidgets('a small pull is rejected — the surface springs back, '
      'nothing pops', (tester) async {
    await _pumpStacked(tester, screen: _surface());

    // 80 raw px → 44 px of resisted travel < 110 px threshold.
    await tester.dragFrom(const Offset(400, 30), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('base-marker')), findsNothing,
        reason: 'a hesitant pull never dismisses');
    expect(find.byKey(const ValueKey('send-edit-back')), findsOneWidget,
        reason: 'the composer is still mounted');
  });

  testWidgets('an UNKNOWN outcome is never silently dragged away — the '
      'pull is rejected and the explicit dialog appears',
      (tester) async {
    await _pumpStacked(
      tester,
      screen: _surface(
        sendOverride: (friendshipId, amount, reference, token) async {
          // Transport loss: the outcome is UNKNOWN, never "failed".
          throw ApiException(message: 'transport', statusCode: 500);
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-unknown-banner')), findsOneWidget,
        reason: 'a 5xx is an unknown outcome');

    // A deliberate pull past the threshold must NOT dismiss.
    await tester.dragFrom(const Offset(400, 30), const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-unknown-leave-dialog')),
        findsOneWidget,
        reason: 'the rejected pull shows the explicit pending decision');
    expect(find.byKey(const ValueKey('base-marker')), findsNothing,
        reason: 'the surface did not pop — the operation stays visible');
    expect(find.byKey(const ValueKey('pull-down-dismiss-transform')),
        findsOneWidget,
        reason: 'the surface sprang back instead of dismissing');
  });

  testWidgets('the header affordance is honest per stage — X at compose, '
      'back-to-edit at review', (tester) async {
    await _pumpStacked(
      tester,
      screen: _surface(
        sendOverride: (friendshipId, amount, reference, token) async {
          final gate = Completer<Map<String, dynamic>>();
          return gate.future;
        },
      ),
    );

    // Compose: X + "Close Send".
    expect(find.bySemanticsLabel('Close Send'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();

    // Review: the affordance becomes the back-to-edit arrow, the title
    // announces the review stage, and the close semantics are gone.
    expect(find.bySemanticsLabel('Back to edit'), findsOneWidget);
    expect(find.bySemanticsLabel('Close Send'), findsNothing);
    expect(find.text('Review transfer'), findsOneWidget);
  });
}
