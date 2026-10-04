// =============================================================================
// ADD CASH REDESIGN — WIDGET TESTS: GROUP D (saved accounts on the fiat
// surface) + GROUP E (the payment-method selector sheet).
//
// The provider is overridden with curated account sets so selection rules
// (primary preselect, accountName over nickname, empty and no-primary
// states) are deterministic.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';

class _FakeSavedMomo extends SavedMomoNotifier {
  _FakeSavedMomo(this.accounts);
  final List<SavedMomoAccount> accounts;
  @override
  Future<List<SavedMomoAccount>> build() async => accounts;
}

SavedMomoAccount _acct(
  String id,
  String nickname,
  String provider,
  String phone, {
  String? accountName,
  bool isPrimary = false,
}) => SavedMomoAccount(
  id: id,
  nickname: nickname,
  provider: provider,
  phoneNumber: phone,
  accountName: accountName,
  isVerified: true,
  isPrimary: isPrimary,
  createdAt: DateTime.utc(2026, 9, 1),
);

Widget _app(List<SavedMomoAccount> accounts) {
  return ProviderScope(
    overrides: [savedMomoProvider.overrideWith(() => _FakeSavedMomo(accounts))],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => GoRouter.of(c).push('/deposit'),
            child: const Text('home-sentinel'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/deposit',
      name: 'deposit',
      pageBuilder: (c, s) => risePage(
        key: s.pageKey,
        restorationId: s.name,
        child: const DepositScreen(),
      ),
    ),
  ],
);

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A modal sheet's ticker anchors at its first tick: pump a zero-duration
/// frame BEFORE advancing the clock, or the sheet sits below the viewport
/// and its rows are unhittable.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

final _twoWithPrimary = [
  _acct(
    'a1',
    'Personal',
    'MTN',
    '+233244123456',
    accountName: 'Kwame Mensah',
    isPrimary: true,
  ),
  _acct(
    'a2',
    'Telecel Acct',
    'TELECEL',
    '+233500987654',
    accountName: 'Ama Boateng',
  ),
];

final _noPrimary = [
  _acct('a1', 'Personal', 'MTN', '+233244123456', accountName: 'Kwame Mensah'),
  _acct(
    'a2',
    'Telecel Acct',
    'TELECEL',
    '+233500987654',
    accountName: 'Ama Boateng',
  ),
];

void main() {
  AppConfig.enableDemoMode();

  group('D — saved accounts on the fiat surface', () {
    testWidgets('the primary account is preselected with its registered name '
        'over the nickname', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_twoWithPrimary));
      await _openDeposit(tester);

      // accountName wins over nickname ('Personal' is not shown as the
      // main identity; the resolved registered name is).
      expect(find.text('Kwame Mensah'), findsOneWidget);
      expect(find.text('024 412 3456'), findsOneWidget);
      expect(find.text('MTN'), findsOneWidget); // network badge
    });

    testWidgets('a single account is auto-selected', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _app([
          _acct(
            'only',
            'Daily',
            'AIRTELTIGO',
            '+233261234567',
            accountName: 'Yaw Owusu',
          ),
        ]),
      );
      await _openDeposit(tester);

      expect(find.text('Yaw Owusu'), findsOneWidget);
      expect(find.text('026 123 4567'), findsOneWidget);
    });

    testWidgets('no primary among several accounts → the row prompts a '
        'choice', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_noPrimary));
      await _openDeposit(tester);

      expect(find.text('Choose a payment method'), findsOneWidget);
      expect(find.text('Choose a payment method to continue.'), findsOneWidget);
    });

    testWidgets('no saved accounts → the row offers to add one, CTA hint '
        'says why it cannot proceed', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(const []));
      await _openDeposit(tester);

      expect(find.text('Add mobile money account'), findsOneWidget);
      expect(
        find.text('Add a mobile money account to continue.'),
        findsOneWidget,
      );
    });

    testWidgets('without a nickname the account still shows a name '
        '(fallback honesty)', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _app([_acct('a1', 'Account', 'MTN', '+233244123456')]),
      );
      await _openDeposit(tester);

      // accountName is null → the row falls back rather than showing an
      // empty identity.
      expect(find.text('024 412 3456'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });
  });

  group('E — payment-method selector', () {
    testWidgets('opens listing every saved account with the selection marked', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_twoWithPrimary));
      await _openDeposit(tester);

      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);

      expect(find.text('Payment method'), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsWidgets);
      expect(find.text('Ama Boateng'), findsOneWidget);
      // The preselected (primary) row carries the check.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('switching the selection persists across sheet open/close', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_twoWithPrimary));
      await _openDeposit(tester);

      // Open the selector, pick the second account.
      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);
      await tester.tap(find.text('Ama Boateng'));
      // UI-correction Phase A: the sheet closes after a tiny
      // acknowledgement delay (the check lands in-sheet first). Cross the
      // delay explicitly — pumpAndSettle alone stops at the idle frame
      // BEFORE the close timer fires — then settle the exit animation.
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text('Payment method'), findsNothing); // sheet closed

      // The fiat surface now shows the new account.
      expect(find.text('Ama Boateng'), findsOneWidget);
      expect(find.text('050 098 7654'), findsOneWidget);
      expect(find.text('Kwame Mensah'), findsNothing);

      // Reopening shows the SAME selection still checked (state persistence).
      await tester.tap(find.text('Ama Boateng'));
      await _settleSheet(tester);
      expect(find.text('Payment method'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('closing the sheet via its X keeps the current selection '
        'untouched', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_twoWithPrimary));
      await _openDeposit(tester);

      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);
      // The sheet's close affordance (the second Icons.close — the first
      // is the surface header's).
      await tester.tap(find.byIcon(Icons.close).last);
      await _settleSheet(tester);

      expect(find.text('Payment method'), findsNothing);
      expect(find.text('Kwame Mensah'), findsOneWidget);
    });

    testWidgets('the sheet offers the add-account action', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_twoWithPrimary));
      await _openDeposit(tester);

      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);
      expect(find.text('Add mobile money account'), findsOneWidget);
    });

    testWidgets('selection is required before the CTA proceeds (no primary '
        'seeded)', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(_noPrimary));
      await _openDeposit(tester);

      // Type an amount — the CTA stays inert without an account. The key
      // is scoped to the keypad so the odometer's identical glyph can
      // never be tapped instead.
      await tester.tap(
        find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.text('5'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Confirm account'), findsNothing);

      // Select an account via the sheet, then the CTA proceeds.
      await tester.tap(find.text('Choose a payment method'));
      await _settleSheet(tester);
      await tester.tap(find.text('Ama Boateng'));
      // UI-correction Phase A: acknowledge-then-close — cross the delay,
      // then settle the exit animation.
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text('Ama Boateng'), findsOneWidget);

      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Confirm account'), findsOneWidget);
    });
  });
}
