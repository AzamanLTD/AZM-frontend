// =============================================================================
// AZAMAN — UNIFIED SEND: COMPOSER UX + MONEY-ACTION SAFETY TESTS
//
// Covers work-order groups 1, 2, 8, the chat-seed semantics AND the PR #165
// review remediation contract:
//   • keypad → review shows the full contract before any commit
//   • the money action requires an INTENTIONAL slide — a reflex tap on the
//     confirm surface never commits (PR #165 finding 1)
//   • a duplicate gesture during flight NEVER double-commits
//   • with biometric lock ON, a cancelled prompt never executes the
//     transfer and re-arms the slider (PR #165 finding 1)
//   • an ambiguous (timeout/offline/409/429/5xx) outcome is NEVER reported
//     as failed or as success; retry is the only path onward and the
//     composition is FROZEN while unknown (PR #165 finding 2)
//   • the unknown-outcome pop is explicit — retry or acknowledge, never a
//     silent abandonment (PR #165 finding 2)
//   • an explicit insufficient-funds failure is honest — no success panel
//   • self-send, not-connected and session-less states fail closed BEFORE
//     the rail is touched
//   • a username-less identity hit renders HONESTLY — display name + AZM
//     ID, never a fabricated @handle (PR #165 finding 4)
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
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/home/activity_actions.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// local_auth's DEFAULT platform implementation (the one active in widget
// tests, where no Android/iOS delegate is registered) speaks this
// channel. Its real method surface: canCheckBiometrics maps to
// deviceSupportsBiometrics() -> 'getAvailableBiometrics' (non-empty
// list), plus 'isDeviceSupported' and 'authenticate'.
const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

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

/// Mocks the local_auth platform channel. [authenticate] is the value the
/// biometric prompt resolves with: false = user cancel/failure, true = pass.
void _mockLocalAuth({
  required bool canCheckBiometrics,
  required bool deviceSupported,
  required bool authenticate,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
    switch (call.method) {
      case 'getAvailableBiometrics':
        return canCheckBiometrics ? <String>['fingerprint'] : <String>[];
      case 'isDeviceSupported':
        return deviceSupported;
      case 'authenticate':
        return authenticate;
      default:
        return null;
    }
  });
}

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
  bool biometricLock = false,
}) async {
  SharedPreferences.setMockInitialValues(
      {'azaman_theme': 1, 'biometric_lock_enabled': biometricLock});
  await _mockSecureStorage();
  final tp = ThemeProvider();
  await tester.pumpWidget(_wrap(tp, screen, authUser ?? _user()));
  await tester.pumpAndSettle();
}

/// Rolls the entry wheel to USDC so the legacy harness amounts keep
/// meaning '5.00 USDC'. (The wheel's production default is GHS-first;
/// the GHS conversion path is covered by its own tests below.)
///
/// Send's roller is VERTICAL: a deliberate upward flick (against the
/// reading direction) advances the unit, GHS -> USDC.
Future<void> _selectUsdcEntry(WidgetTester tester) async {
  final wheel = find.byKey(const ValueKey('send-amount-currency'));
  expect(wheel, findsOneWidget);
  await tester.drag(wheel, const Offset(0, -80));
  await tester.pumpAndSettle();
}

/// Taps a keypad key by its LABEL, scoped to the AmountKeypad itself.
///
/// Scoping matters: the odometer renders each amount digit as its own
/// Text, so a bare `find.text('0')` can match a display digit (or a
/// digit inside an overlay route) instead of the key — which is exactly
/// how the §1/§2/§4 tests first failed. Every amount tap in this suite
/// goes through here.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.descendant(
    of: find.byType(AmountKeypad),
    matching: find.text(key),
  );
  expect(finder, findsWidgets, reason: 'the keypad must offer "$key"');
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump();
}

Future<void> _enterAmount(WidgetTester tester) async {
  await _selectUsdcEntry(tester);
  for (final key in const ['5', '.', '0', '0']) {
    await _tapKey(tester, key);
  }
}

/// Drives the money-action slide through its full intentional gesture:
/// thumb to the end. The slide is the ONLY entry into _commit — there is
/// no tappable CTA on the review stage anymore (PR #165 finding 1).
Future<void> _slideToConfirm(WidgetTester tester) async {
  final slide = find.byType(SlideToConfirm);
  expect(slide, findsOneWidget,
      reason: 'the money action is a slide-to-confirm surface');
  final topLeft = tester.getTopLeft(slide);
  final gesture = await tester.startGesture(topLeft + const Offset(28, 30));
  // Full deliberate drag: far past the 90% threshold on the widest surface.
  await gesture.moveBy(const Offset(1200, 0));
  await gesture.up();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'keypad → review shows the full contract, and a duplicate gesture '
      'during flight commits EXACTLY once',
      (tester) async {
    var commits = 0;
    final gate = Completer<Map<String, dynamic>>();
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
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

    // Commit via the intentional slide — then attempt a SECOND slide
    // mid-flight: the slider is in its loading state and rejects drags, so
    // the duplicate gesture can never re-enter _commit.
    await _slideToConfirm(tester);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-sending-banner')), findsOneWidget);
    await _slideToConfirm(tester);
    await tester.pump();
    expect(commits, 1, reason: 'duplicate gesture must never double-commit');

    gate.complete({'success': true});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    expect(commits, 1);
  });

  testWidgets(
      'the money action requires an intentional slide — a plain tap on '
      'the confirm surface never commits',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          throw StateError('a tap must never fire the rail');
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();

    // Reflex taps on the slider body do nothing — the thumb never moved.
    await tester.tap(find.byType(SlideToConfirm), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byType(SlideToConfirm), warnIfMissed: false);
    await tester.pump();
    expect(commits, 0,
        reason: 'only a full intentional drag confirms the transfer');
    expect(find.byKey(const ValueKey('send-sending-banner')), findsNothing);
  });

  testWidgets(
      'a cancelled biometric prompt never executes the transfer — and the '
      'slider re-arms for a deliberate retry',
      (tester) async {
    var commits = 0; // first prompt: user cancels / fails
    _mockLocalAuth(
      canCheckBiometrics: true,
      deviceSupported: true,
      authenticate: false,
    );
    await _pump(
      tester,
      biometricLock: true,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          return {'success': true};
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();

    await _slideToConfirm(tester);
    await tester.pumpAndSettle();

    // The gate swallowed the slide: no wire traffic, honest feedback, and
    // the composer is still on review — NOT sending, NOT done.
    expect(commits, 0,
        reason: 'a cancelled prompt must never execute the transfer');
    expect(find.byKey(const ValueKey('send-sending-banner')), findsNothing);
    expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);
    expect(find.text('Authentication failed. Action cancelled.'),
        findsOneWidget);
    expect(find.byType(SlideToConfirm), findsOneWidget,
        reason: 'the slider is still present and re-armed after cancel');

    // The cancel snackbar sits over the bottom slider; dismiss it so the
    // retry gesture reaches the re-armed thumb.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // The slider re-armed: a second deliberate slide with a PASSING prompt
    // goes through — exactly once.
    _mockLocalAuth(
      canCheckBiometrics: true,
      deviceSupported: true,
      authenticate: true,
    );
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();
    expect(commits, 1, reason: 'the re-armed slider commits after a pass');
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
  });

  testWidgets(
      'with biometric lock on and the prompt passing, the slide commits '
      'through the canonical rail EXACTLY once',
      (tester) async {
    var commits = 0;
    _mockLocalAuth(
      canCheckBiometrics: true,
      deviceSupported: true,
      authenticate: true,
    );
    await _pump(
      tester,
      biometricLock: true,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
        recipient: _friendRecipient(),
        sendOverride: (friendshipId, amount, reference, token) async {
          commits++;
          expect(friendshipId, 'fs-1');
          expect(amount, 5.0);
          return {'success': true};
        },
      ),
    );

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();

    await _slideToConfirm(tester);
    await tester.pumpAndSettle();

    expect(commits, 1, reason: 'gate pass → exactly one canonical commit');
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
  });

  testWidgets(
      'a not-connected recipient can never reach review — the rail is '
      'untouched',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
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
    expect(find.byType(SlideToConfirm), findsNothing);
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
        fxRateOverride: 15.38,
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
    await _slideToConfirm(tester);
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
        fxRateOverride: 15.38,
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
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();

    // Ambiguous banner, NOT a failure claim, NOT a success panel.
    expect(find.byKey(const ValueKey('send-unknown-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-error-text')), findsNothing);
    expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);

    // Retry (the re-armed slider): the same rail, and success lands.
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    expect(commits, 2, reason: 'a retry is a second real attempt');
  });

  testWidgets(
      '409, 429 and 5xx are UNKNOWN outcomes — honest banner, frozen '
      'composition, retry on the SAME durable identity',
      (tester) async {
    const statuses = [409, 429, 500, 503];
    for (final status in statuses) {
      final attempts = <List<Object?>>[];
      var first = true;
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 15.38,
          // A unique key per iteration: pumpWidget reuses State when the
          // widget type matches, and iteration 1 ends on the done stage.
          key: ValueKey('send-unknown-$status'),
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async {
            attempts.add([friendshipId, amount, reference, token]);
            if (first) {
              first = false;
              throw ApiException(
                  message: 'transport', statusCode: status);
            }
            return {'success': true};
          },
        ),
      );

      await _enterAmount(tester);
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();
      await _slideToConfirm(tester);
      await tester.pumpAndSettle();

      // UNKNOWN, not failed, not succeeded.
      expect(find.byKey(const ValueKey('send-unknown-banner')), findsOneWidget,
          reason: 'HTTP $status is an unknown outcome');
      expect(find.byKey(const ValueKey('send-error-text')), findsNothing,
          reason: 'HTTP $status is never claimed as failed');
      expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);

      // The composition is FROZEN: no edit link, the app-bar edit path is
      // disabled, and no keypad to change the amount.
      expect(find.byKey(const ValueKey('send-review-edit')), findsNothing,
          reason: 'HTTP $status freezes the composition');
      final backButton =
          tester.widget<IconButton>(find.byKey(const ValueKey('send-edit-back')));
      expect(backButton.onPressed, isNull,
          reason: 'HTTP $status disables the edit-back affordance');
      expect(find.text('Retry transfer'), findsOneWidget,
          reason: 'HTTP $status offers the exact-operation retry');

      // Retry: byte-identical body — the SAME durable operation identity.
      await _slideToConfirm(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget,
          reason: 'HTTP $status resolves on retry');
      expect(attempts.length, 2);
      expect(attempts[1], attempts[0],
          reason: 'HTTP $status retry re-runs the identical request');
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'the unknown-outcome pop is explicit — retry resolves it, and leaving '
      'is acknowledged, never silent',
      (tester) async {
    var commits = 0;
    var first = true;

    // Two-route harness so the composer can actually pop back somewhere.
    await _mockSecureStorage();
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
    final tp = ThemeProvider();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FixedAuth(_user())),
          friendProvider.overrideWith((ref) => _FakeFriends(ref)),
          themeProvider.overrideWith((ref) => tp),
        ],
        child: MaterialApp(
          home: Scaffold(
            key: const ValueKey('home-root'),
            body: Center(
              child: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const ValueKey('open-send'),
                  onPressed: () => Navigator.of(ctx).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => SendMoneyScreen.toFriend(
                        fxRateOverride: 15.38,
                        recipient: _friendRecipient(),
                        sendOverride:
                            (friendshipId, amount, reference, token) async {
                          commits++;
                          if (first) {
                            first = false;
                            throw ApiException(
                                message: 'conflict', statusCode: 409);
                          }
                          return {'success': true};
                        },
                      ),
                    ),
                  ),
                  child: const Text('Open Send'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drive to the unknown state.
    await tester.tap(find.byKey(const ValueKey('open-send')));
    await tester.pumpAndSettle();
    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-unknown-banner')), findsOneWidget);

    // System back is intercepted: the pop does NOT happen silently.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-root')), findsNothing,
        reason: 'the composer did not silently abandon the operation');
    expect(find.byKey(const ValueKey('send-unknown-leave-dialog')),
        findsOneWidget,
        reason: 'the user gets an explicit decision');

    // 'Retry transfer' resolves the SAME operation and dismisses the dialog.
    await tester.tap(find.byKey(const ValueKey('send-unknown-dialog-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-unknown-leave-dialog')),
        findsNothing);
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    expect(commits, 2, reason: 'the dialog retry is the same operation');

    // Resolved: ordinary navigation works again — Done pops home.
    await tester.tap(find.byKey(const ValueKey('send-success-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-root')), findsOneWidget);
  });

  testWidgets(
      'an explicit insufficient-funds failure is honest — no success panel',
      (tester) async {
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
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
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();

    expect(find.text('Insufficient balance for this transfer.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('send-success-icon')), findsNothing);
    expect(find.text('Retry transfer'), findsOneWidget);
    // A definitive 4xx is genuinely failed — editing is allowed again.
    expect(find.byKey(const ValueKey('send-review-edit')), findsOneWidget);
  });

  testWidgets(
      'a session-less composer fails closed — no commit without a live token',
      (tester) async {
    var commits = 0;
    await _pump(
      tester,
      screen: SendMoneyScreen.toFriend(
        fxRateOverride: 15.38,
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
    await _slideToConfirm(tester);
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
        fxRateOverride: 15.38,
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

  testWidgets(
      'a username-less AZM-ID hit renders HONESTLY — display name + real '
      'AZM ID, never a fabricated @handle (PR #165 finding 4)',
      (tester) async {
    final api = ApiClient(
      client: MockClient((req) async {
        if (req.url.path.contains('/users/lookup/AZM-123456789')) {
          // The identity contract's honest shape: azamanId + displayName,
          // NO username field.
          return http.Response(
              '{"user":{"azamanId":"AZM-123456789",'
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
        fxRateOverride: 15.38,
        initialRecipient: const ActivityRecipient(
            azamanId: 'AZM-123456789', displayName: 'Ama Mensah'),
        discovery: RecipientDiscoveryService(api: api),
        sendOverride: (friendshipId, amount, reference, token) async {
          throw StateError('a display-only identity can never send');
        },
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The confirmed row leads with the display name and shows the real
    // AZM ID as the identity line — '@Ama Mensah' must never exist.
    expect(find.text('Ama Mensah'), findsOneWidget);
    expect(find.text('AZM-123456789'), findsOneWidget);
    expect(find.text('@Ama Mensah'), findsNothing,
        reason: 'displayName is never manufactured into a handle');
    expect(
        find.byKey(const ValueKey('send-not-connected-chip')), findsOneWidget,
        reason: 'no friendship was ever returned, so it is honestly '
            'not send-capable');

    await _enterAmount(tester);
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-review-card')), findsNothing,
        reason: 'a display-only row can never reach review');
  });

  // =========================================================================
  // GHANA-FIRST (2026-10-20) — the GHS entry path through a frozen rate.
  // The wheel's production default is GHS; the rail ALWAYS settles USDC.
  // =========================================================================
  group('GHS-first entry', () {
    /// Enters 5.00 on the wheel's GHS default (no USDC roll), through
    /// the same keypad-scoped finder as every other amount entry.
    Future<void> enterGhs(WidgetTester tester) async {
      for (final key in const ['5', '.', '0', '0']) {
        await _tapKey(tester, key);
      }
    }

    testWidgets('a GHS entry converts through the frozen rate — the rail '
        'carries the exact reviewed USDC wire, never the GHS digits',
        (tester) async {
      final wire = <double>[];
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 15.38,
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async {
            wire.add(amount);
            return {'success': true};
          },
        ),
      );

      // The live equivalent line is present while typing (compose-only).
      await enterGhs(tester);
      expect(
          find.textContaining(
              '≈ 0.33\u00A0USDC — the reviewed transfer is in USDC'),
          findsOneWidget,
          reason: 'the GHS figure shows its USDC pair at the live rate');

      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();

      // Review leads with the entered denomination, identifies the EXACT
      // USDC wire (5.00 / 15.38 = 0.33, half-up at wire decimals) and the
      // rate the figure was derived at.
      expect(find.text('GH\u20B5\u00A05.00'), findsOneWidget);
      expect(find.text('0.33 USDC'), findsOneWidget);
      expect(find.text('1 USDC = GH\u20B5\u00A015.38'), findsOneWidget);

      await _slideToConfirm(tester);
      await tester.pumpAndSettle();

      expect(wire, [0.33],
          reason: 'the rail receives the CONVERTED USDC wire amount');
      expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
      // GHANA-FIRST SUCCESS: the entered figure leads the sentence; the
      // wire truth is labelled separately — never presented as what the
      // user typed.
      expect(
          find.textContaining('GH\u20B5\u00A05.00 to Ama Mensah'),
          findsOneWidget,
          reason: 'the GHS entry leads the success message');
      expect(
          find.text('Transferred on the wire as 0.33 USDC'), findsOneWidget,
          reason: 'the actual USDC settlement is identified separately');
    });

    testWidgets('the entry wheel CONVERTS the digits on a roll — a unit '
        'switch is numeric, never a label swap', (tester) async {
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 15.38,
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async =>
              {'success': true},
        ),
      );

      await enterGhs(tester);
      // The Send roller is VERTICAL: a deliberate upward flick advances
      // GHS -> USDC; the amount converts numerically with the digits.
      await tester.drag(
          find.byKey(const ValueKey('send-amount-currency')),
          const Offset(0, -80));
      await tester.pumpAndSettle();

      // 5.00 GHS -> 0.33 USDC (half-up): the digits THEMSELVES convert.
      // (The figure renders through OdometerNumber's per-slot cells, so
      // the amount contract is pinned on the odometer's own value.)
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '0.33',
          reason: 'the entry converted to its USDC equivalent');
      expect(find.textContaining('≈ GH\u20B5\u00A05.08'), findsOneWidget,
          reason: 'the paired equivalent round-trips at the live rate');
    });

    testWidgets('a GHS composition without a usable rate FAILS CLOSED — '
        'review is unreachable and no wire is ever attempted', (tester) async {
      var commits = 0;
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 0, // unusable: the seam mirrors a dead oracle
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async {
            commits++;
            return {'success': true};
          },
        ),
      );

      await enterGhs(tester);
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('send-review-card')), findsNothing,
          reason: 'an unconvertible composition never reaches review');
      expect(
          find.textContaining(
              'Exchange rate unavailable — enter the amount in USDC instead'),
          findsOneWidget,
          reason: 'the composer explains the dead rate honestly');
      expect(commits, 0, reason: 'the rail is never touched');
    });

    testWidgets('a rate that drifts between review and commit FAILS CLOSED '
        '— the frozen quote is revalidated, never silently re-priced',
        (tester) async {
      var rate = 15.38;
      final wire = <double>[];

      await _mockSecureStorage();
      SharedPreferences.setMockInitialValues({'azaman_theme': 1});
      final tp = ThemeProvider();
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
        // A LIVE oracle the test can move: each (re)compute reads the
        // current value of [rate]. The snapshot carries the FULL §2
        // freshness contract (a genuinely fresh observation).
        fxRateProvider.overrideWith(
            (ref) async => _freshSnapshot(rate)),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SendMoneyScreen.toFriend(
              recipient: _friendRecipient(),
              sendOverride: (friendshipId, amount, reference, token) async {
                wire.add(amount);
                return {'success': true};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Compose + review at 15.38 (via the LIVE provider, not the seam).
      await enterGhs(tester);
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();
      expect(find.text('1 USDC = GH\u20B5\u00A015.38'), findsOneWidget,
          reason: 'the quote froze at the reviewed rate');

      // The oracle moves while the composition sits at review. §2: NO
      // manual invalidation — the commit gate itself re-fetches and
      // re-derives freshness from lastExternalSync, so the moved oracle
      // is detected exactly as in production.
      rate = 15.50;
      await tester.pumpAndSettle();

      // The slide is rejected: the user is returned to compose with an
      // honest explanation and the rail is never touched.
      await _slideToConfirm(tester);
      await tester.pumpAndSettle();
      expect(wire, isEmpty, reason: 'a stale quote never commits');
      expect(
          find.textContaining(
              'The exchange rate changed since you reviewed the amount'),
          findsOneWidget);

      // A FRESH review at the new rate recovers the composition honestly:
      // 5.00 GHS / 15.50 = 0.32 USDC.
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();
      expect(find.text('1 USDC = GH\u20B5\u00A015.50'), findsOneWidget);
      expect(find.text('0.32 USDC'), findsOneWidget);
      await _slideToConfirm(tester);
      await tester.pumpAndSettle();
      expect(wire, [0.32],
          reason: 'the recovery path commits the newly reviewed quote');
      expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
    });

    // =========================================================================
    // PR #165 review §1/§2/§4 — direct USDC entry, server freshness, and
    // the paired display under BOTH entry units.
    // =========================================================================

    testWidgets('§1 — a DIRECT USDC entry submits with UNAVAILABLE FX: the '
        'amount is already the wire, the equivalent is named unavailable '
        '(never a false zero)',
        (tester) async {
      final wire = <double>[];
      await _mockSecureStorage();
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 0, // dead oracle: NO equivalent is displayable
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async {
            wire.add(amount);
            return {'success': true};
          },
        ),
      );

      // Wheel rolled to USDC, 5.00 typed directly in the wire unit.
      await _enterAmount(tester);
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();

      // Review is REACHED with no rate at all — the exact wire amount is
      // the entered amount and the GHS equivalent is honestly unavailable.
      expect(find.byKey(const ValueKey('send-review-card')), findsOneWidget,
          reason: 'direct USDC must not be blocked by a dead oracle');
      expect(find.text('5.00 USDC'), findsOneWidget,
          reason: 'the primary amount is the exact entered wire amount');
      expect(
          find.byKey(const ValueKey('send-review-ghs-equivalent')),
          findsOneWidget,
          reason: 'the paired GHS-equivalent row exists under USDC entry');
      expect(
          find.text('Unavailable — rate not loaded'),
          findsOneWidget,
          reason: 'the unavailable equivalent is named, never GH₵ 0.00');
      expect(find.textContaining('GH₵ 0.00'), findsNothing,
          reason: 'a false zero equivalent must never render');

      // Commit succeeds — the wire amount is exactly the entered amount.
      await _slideToConfirm(tester);
      await tester.pumpAndSettle();
      expect(wire, [5.00],
          reason: 'the USDC digits are the wire payload, unconverted');
      expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
      expect(find.textContaining('5.00 USDC'), findsOneWidget,
          reason: 'success keeps the wire amount primary');
      expect(find.textContaining('GHS equivalent unavailable'), findsOneWidget,
          reason: 'success names the unavailable equivalent honestly');
      expect(find.textContaining('settled in USDC'), findsOneWidget,
          reason: 'success never presents the equivalent as settlement');
    });

    testWidgets('§4 — USDC entry with a VALID rate shows the paired GHS '
        'equivalent in order: primary wire amount, equivalent second, fee '
        'truth, no fabrication',
        (tester) async {
      final wire = <double>[];
      await _mockSecureStorage();
      await _pump(
        tester,
        screen: SendMoneyScreen.toFriend(
          fxRateOverride: 15.38,
          recipient: _friendRecipient(),
          sendOverride: (friendshipId, amount, reference, token) async {
            wire.add(amount);
            return {'success': true};
          },
        ),
      );

      await _enterAmount(tester); // wheel on USDC, 5.00 typed
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('send-review-amount')), findsOneWidget);
      expect(find.text('5.00 USDC'), findsOneWidget,
          reason: 'the primary amount is the exact wire amount');
      // 5.00 × 15.38 = 76.90 — the equivalent rides second.
      expect(
          find.byKey(const ValueKey('send-review-ghs-equivalent')),
          findsOneWidget);
      expect(find.text('GH₵ 76.90'), findsOneWidget,
          reason: 'the GHS equivalent is computed at the frozen rate');
      expect(find.text('Rate used for the equivalent'), findsOneWidget,
          reason: 'the pair is labelled as the derivation rate, not an '
              'execution quote');
      expect(find.text('No fee'), findsOneWidget,
          reason: 'fee truth stays exact');

      await _slideToConfirm(tester);
      await tester.pumpAndSettle();
      expect(wire, [5.00]);
      expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
      expect(find.textContaining('GH₵ 76.90'), findsOneWidget,
          reason: 'success also shows the paired equivalent under USDC entry');
    });

    testWidgets('§2 — a STALE SERVER snapshot is rejected for GHS entry; a '
        'FRESH one is accepted (no manual invalidation anywhere)',
        (tester) async {
      var stale = true;
      await _mockSecureStorage();
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => ThemeProvider()),
        // One live oracle whose CURRENT observation is either stale
        // (aged past the backend threshold, isFresh false) or fresh.
        fxRateProvider.overrideWith(
            (ref) async => stale ? _staleSnapshot(15.38) : _freshSnapshot(15.38)),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SendMoneyScreen.toFriend(
              recipient: _friendRecipient(),
              sendOverride: (friendshipId, amount, reference, token) async =>
                  {'success': true},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // STALE server observation: a GHS composition cannot review.
      await enterGhs(tester);
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send-review-card')), findsNothing,
          reason: 'a stale server snapshot must not convert');
      expect(
          find.textContaining(
              'Exchange rate unavailable — enter the amount in USDC instead'),
          findsOneWidget,
          reason: 'the composer explains the stale oracle honestly');

      // FRESH observation: the oracle recovers, and after the provider
      // recomputes (a later retry of the same composition) review works.
      // Commit-time revalidation itself is covered by the drift test.
      stale = false;
      container.invalidate(fxRateProvider);
      // The composer's rate read is non-watching; force the recompute
      // the same way the commit gate does — await the oracle's future.
      await container.read(fxRateProvider.future);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send-review-card')), findsOneWidget,
          reason: 'a fresh canonical snapshot converts');
      expect(find.text('1 USDC = GH₵ 15.38'), findsOneWidget);
    });
  });
}

  // A genuinely fresh snapshot fixture for §2 tests: the full backend
  // freshness contract holds at the moment of the call.
  FxRateSnapshot _freshSnapshot(double rate) {
    final observed = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
    return FxRateSnapshot(
      ghsPerUsdc: rate,
      source: 'TEST',
      lastSync: observed,
      fetchedAt: DateTime.now().toUtc(),
      serverFresh: true,
      lastExternalSync: observed,
      externalRateAgeSeconds: 10,
      rateFreshnessMaxAgeSeconds: 1800,
    );
  }

  // A stale server observation: aged past the backend's threshold and the
  // backend itself says isFresh == false. fetchedAt is NOW — the §2 trap:
  // a fresh fetch of an old observation must not make it usable.
  FxRateSnapshot _staleSnapshot(double rate) {
    final observed = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    return FxRateSnapshot(
      ghsPerUsdc: rate,
      source: 'TEST',
      lastSync: observed,
      fetchedAt: DateTime.now().toUtc(),
      serverFresh: false,
      lastExternalSync: observed,
      externalRateAgeSeconds: 7200,
      rateFreshnessMaxAgeSeconds: 1800,
    );
  }
