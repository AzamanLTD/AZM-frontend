// =============================================================================
// AZAMAN — WORKSTREAM C: WITHDRAW SURFACE GRAMMAR TESTS
//
// Withdraw adopts the Add Cash surface grammar (rise-family route, X
// close, deliberate pull-to-dismiss, custom keypad + odometer amount) and
// gains a controlled PageView synced with the MoMo/Crypto segment toggle.
// This suite pins the SURFACE contract only; the financial contracts
// (saved-account allowlists, network rules, balance checks, idempotency,
// durable recovery) are untouched and keep their own suites.
//
//   • the X is the ONE close affordance (no back arrow) and closes the
//     surface — the stack returns to what was beneath
//   • a deliberate downward pull commits the dismissal; a small pull is
//     a rejected attempt that springs back
//   • the segment toggle drives the PageView; a horizontal swipe drives
//     the toggle (a11y: everything operable without swiping)
//   • per-section input state survives mode switches (the pick and the
//     reference note persist across a swipe away and back)
//   • the optional reference is a CANCEL-SAFE modal: Save commits, Cancel
//     discards the draft, and the 80-char cap stays visible
//   • the keypad composes the amount through the AmountInput machine
//   • the commit affordance appears only when the mode's contract is
//     satisfied (saved account + amount on MoMo)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomands.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);

  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {}
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

Future<void> _mockSecureStorage() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
}

/// Mini router wired to the REAL registry location (AzRoutes.withdraw())
/// with the production risePage — the same wiring app_router.dart uses.
GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('base-marker'),
                onPressed: () => GoRouter.of(c).push(AzRoutes.withdraw()),
                child: const Text('base'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/withdraw',
          name: AzRouteNames.withdraw,
          pageBuilder: (c, s) => risePage(
            key: s.pageKey,
            restorationId: s.name,
            child: const WithdrawalScreen(),
          ),
        ),
      ],
    );

Widget _app() => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        themeProvider.overrideWith((ref) => ThemeProvider()),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Pumps Home (base-marker) and pushes the Withdraw surface through the
/// CANONICAL route — after this the surface is mounted above base.
Future<void> _pumpSurface(WidgetTester tester) async {
  _phoneSize(tester);
  SharedPreferences.setMockInitialValues(
      {'azaman_theme': 1, 'biometric_lock_enabled': false});
  await _mockSecureStorage();
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('base-marker')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('base-marker')), findsNothing,
      reason: 'the withdraw surface covers the base page');
}

Finder _odometerCell(String ch) =>
    find.descendant(of: find.byType(OdometerNumber), matching: find.text(ch));

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.descendant(
    of: find.byType(AmountKeypad),
    matching: find.text(key),
  );
  expect(finder, findsWidgets, reason: 'the keypad must offer "$key"');
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump();
}

/// A point inside the mode pages area (between the amount composition and
/// the keypad), away from every other gesture surface.
Offset get _pagePoint => const Offset(210, 430);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The financial layer runs against the demo interceptor — no network.
  AppConfig.enableDemoMode();

  group('registry', () {
    test('canonical location and route name are stable', () {
      expect(AzRoutes.withdraw(), '/withdraw');
      expect(AzRouteNames.withdraw, 'withdraw');
    });
  });

  group('A — surface grammar', () {
    testWidgets('header shows one X close and the Withdraw title; no '
        'back arrow', (tester) async {
      await _pumpSurface(tester);

      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      // No back arrow — the X is the ONE close affordance.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(
        find.bySemanticsLabel('Close Withdraw'),
        findsOneWidget,
        reason: 'the close affordance announces its action',
      );
    });

    testWidgets('the X closes the surface — the stack returns to base',
        (tester) async {
      await _pumpSurface(tester);

      await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('base-marker')), findsOneWidget,
          reason: 'the surface popped; the base page is back');
    });

    testWidgets('a deliberate downward pull dismisses the surface',
        (tester) async {
      await _pumpSurface(tester);

      // From the header band (static area, no child owns the vertical
      // gesture there): 260 raw px of travel commits the dismissal.
      await tester.dragFrom(const Offset(400, 30), const Offset(0, 260));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('base-marker')), findsOneWidget,
          reason: 'the committed pull dismissed the surface');
    });

    testWidgets('a small pull is rejected — the surface springs back, '
        'nothing pops', (tester) async {
      await _pumpSurface(tester);

      await tester.dragFrom(const Offset(400, 30), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('base-marker')), findsNothing,
          reason: 'a hesitant pull never dismisses');
      expect(find.text('Withdraw'), findsOneWidget,
          reason: 'the surface is still mounted');
    });
  });

  group('B — segment toggle and PageView stay in sync', () {
    testWidgets('tapping the Crypto Wallet segment shows the crypto page',
        (tester) async {
      await _pumpSurface(tester);

      // MoMo page first: the saved-account section is present, the
      // crypto empty state is not.
      expect(find.text('Send to'), findsOneWidget);
      expect(find.text('No saved crypto wallet'), findsNothing);

      await tester.tap(find.text('Crypto Wallet'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('No saved crypto wallet'), findsOneWidget,
          reason: 'demo seeds no legacy wallets — the honest empty state');
      expect(find.text('Send to'), findsNothing,
          reason: 'the MoMo page is off-stage');
    });

    testWidgets('a horizontal swipe drives the segments back and forth',
        (tester) async {
      await _pumpSurface(tester);

      // Swipe left: MoMo → Crypto. Everything must be operable WITHOUT
      // swiping too, but the swipe is the added gesture vocabulary.
      await tester.dragFrom(_pagePoint, const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('No saved crypto wallet'), findsOneWidget);
      expect(find.text('Send to'), findsNothing);

      // Swipe right: Crypto → MoMo.
      await tester.dragFrom(_pagePoint, const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(find.text('Send to'), findsOneWidget);
      expect(find.text('No saved crypto wallet'), findsNothing);
    });

    testWidgets('the keypad and amount stay shared across mode switches',
        (tester) async {
      await _pumpSurface(tester);

      for (final key in const ['1', '2', '.', '5']) {
        await _tapKey(tester, key);
      }
      // The odometer renders layered (rolling) cells, so a digit can be
      // present in more than one layer — presence is the contract.
      expect(_odometerCell('1'), findsWidgets);
      expect(_odometerCell('2'), findsWidgets);
      expect(_odometerCell('.'), findsWidgets);
      expect(_odometerCell('5'), findsWidgets);

      // Switch to Crypto and back: the amount composition is shared
      // surface state — it survives the round trip.
      await tester.tap(find.text('Crypto Wallet'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile Money'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_odometerCell('1'), findsWidgets,
          reason: 'the composed amount survives mode switches');
      expect(_odometerCell('5'), findsWidgets);
    });

    testWidgets('per-section input state survives a swipe away and back',
        (tester) async {
      await _pumpSurface(tester);

      // Pick the demo saved MoMo account through the selector sheet —
      // the pick fills the reference with the account's registered name,
      // so the affordance flips from 'Add' to 'Edit' with the preview.
      await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsWidgets,
          reason: 'the row and the affordance preview both show the name');

      // Swipe away and back: the pick (and its reference fill) must be
      // exactly as it was — page switches never lose section state.
      await tester.dragFrom(_pagePoint, const Offset(-350, 0));
      await tester.pumpAndSettle();
      await tester.dragFrom(_pagePoint, const Offset(350, 0));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget,
          reason: 'the account pick survives the round trip');
      // The account row AND the affordance preview both carry the name.
      expect(find.text('Kwame Mensah'), findsWidgets);
    });
  });

  group('B2 — the payout account is ONE Add-Cash-style selector, never a '
      'stack of wallets (owner correction 2026-10-25)', () {
    testWidgets('the surface renders exactly one account row — the other '
        'saved account never stacks inline', (tester) async {
      await _pumpSurface(tester);

      // Before any pick: the honest choose state, exactly once.
      expect(find.text('Choose payout account'), findsOneWidget);
      // The demo seeds TWO saved accounts (Kwame Mensah · MTN primary,
      // Ama Boateng · Telecel). NEITHER renders inline — the old stacked
      // list showed both networks as two wallets, which the owner
      // corrected: the selector row must be the only surface presence.
      expect(find.text('Kwame Mensah'), findsNothing,
          reason: 'no account tile renders before a pick');
      expect(find.text('Ama Boateng'), findsNothing);
      expect(find.text('My MTN'), findsNothing);
      expect(find.text('Telecel Acct'), findsNothing);
    });

    testWidgets('the row opens the selector sheet; picking an account '
        'lands the row and the reference preview', (tester) async {
      await _pumpSurface(tester);

      await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // The sheet: both real accounts offered, the add-account CTA and
      // a titled header — the Add Cash payment-method grammar.
      expect(find.text('Payout account'), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsOneWidget);
      expect(find.text('Ama Boateng'), findsOneWidget);
      expect(find.text('Add a new account'), findsOneWidget);

      // Pick the primary account.
      await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // The sheet is gone; the row carries the pick.
      expect(find.text('Payout account'), findsNothing,
          reason: 'the sheet closed after the acknowledged pick');
      expect(find.text('Kwame Mensah'), findsWidgets,
          reason: 'the row and the reference preview show the name');
      expect(find.text('024 412 3456'), findsOneWidget,
          reason: 'the Ghana-formatted phone renders on the row');
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('switching accounts in the sheet updates the row — the '
        'selection is a live single source', (tester) async {
      await _pumpSurface(tester);

      // Pick the primary.
      await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Kwame Mensah'), findsWidgets);

      // Reopen and switch to the Telecel account.
      await tester.tap(find.text('Kwame Mensah').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Ama Boateng'), findsOneWidget,
          reason: 'the sheet offers the other real account');
      await tester.tap(find.text('Ama Boateng'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Ama Boateng'), findsWidgets,
          reason: 'the row now carries the switched account');
      expect(find.text('050 098 7654'), findsOneWidget,
          reason: 'the switched account phone renders');
    });

    testWidgets('the sheet opens from the selected row too, and closing it '
        'leaves the pick untouched', (tester) async {
      await _pumpSurface(tester);

      await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Reopen, then dismiss via the close control — the pick survives.
      await tester.tap(find.text('Kwame Mensah').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Payout account'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Payout account'), findsNothing);
      expect(find.text('Kwame Mensah'), findsWidgets,
          reason: 'closing the sheet never undoes the committed pick');
    });
  });

  group('C — the reference affordance is a cancel-safe modal', () {
    testWidgets('Save commits the note to the affordance', (tester) async {
      await _pumpSurface(tester);

      // The affordance starts empty and honest.
      expect(find.text('Add'), findsOneWidget);

      await tester.tap(find.text('Reference'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('e.g. Rent for May'), findsOneWidget,
          reason: 'the modal is open with its hint');
      await tester.enterText(find.byType(TextField).last, 'Rent for May');
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Rent for May'), findsOneWidget,
          reason: 'the committed note is previewed on the affordance');
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('Cancel discards the draft — the committed note is '
        'untouched', (tester) async {
      await _pumpSurface(tester);

      // Commit a note first.
      await tester.tap(find.text('Reference'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Rent for May');
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Draft a change, then CANCEL: the draft dies, the commit lives.
      await tester.tap(find.text('Reference'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Zzz discard me');
      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Rent for May'), findsOneWidget,
          reason: 'cancel-safe: the committed note survived');
      expect(find.text('Zzz discard me'), findsNothing,
          reason: 'the discarded draft never leaked');
    });

    testWidgets('the 80-character cap stays visible in the modal',
        (tester) async {
      await _pumpSurface(tester);

      await tester.tap(find.text('Reference'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // The framework formatter caps at maxLength; the counter must show
      // the cap honestly.
      await tester.enterText(find.byType(TextField).last, 'a' * 90);
      await tester.pump();

      expect(
        find.textContaining(RegExp(r'80\s*/\s*80')),
        findsOneWidget,
        reason: 'the live counter shows the 80-character cap',
      );
    });
  });

  group('D — the commit affordance follows the mode contract', () {
    testWidgets('no account selected: an honest disabled state, never a '
        'live commit', (tester) async {
      await _pumpSurface(tester);

      expect(find.byType(SlideToConfirm), findsNothing,
          reason: 'nothing to slide before an account is picked');
      expect(find.text('Choose an account'), findsOneWidget);
    });

    testWidgets('account picked and amount composed: the slide commit '
        'appears', (tester) async {
      await _pumpSurface(tester);

      await tester.tap(find.text('Choose payout account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kwame Mensah'), warnIfMissed: false);
      await tester.pumpAndSettle();
      for (final key in const ['1', '2', '.', '5']) {
        await _tapKey(tester, key);
      }
      await tester.pump();

      expect(find.byType(SlideToConfirm), findsOneWidget,
          reason: 'the mode contract is satisfied — the commit is live');
      expect(find.text('Slide to send mobile money'), findsOneWidget);
    });
  });
}
