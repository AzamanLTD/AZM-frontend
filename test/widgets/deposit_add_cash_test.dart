// =============================================================================
// ADD CASH REDESIGN — WIDGET TESTS: GROUP A (initial surface), B (odometer
// wiring), C (quick amounts), F (CTA + the full Moolre flow under demo
// mode), I (accessibility).
//
// Group J (regression) lives with the existing suites; this file must stay
// green on its own and alongside them.
//
// Harness: a minimal GoRouter with '/' (a sentinel home) and '/deposit'
// wired EXACTLY like the real registry (risePage, query params). Pull-down
// dismissal tests live in deposit_surface_interactions_test.dart.
//
// Demo mode (the sanctioned test seam — same as friends_hub_demo_test):
//   • GET /saved-momo      → two seeded accounts (Kwame Mensah, MTN primary;
//                            Ama Boateng, Telecel)
//   • POST /deposit/validate-name        → 'Kwame Mensah'
//   • POST /deposit/fiat/initiate/moolre → success, no OTP, DEP-DEMO-* ref
// The financial layer is therefore exercised end-to-end with zero network.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/widgets/odometer_number.dart';
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

/// The demo seed's two accounts, for tests that don't override the provider.
Widget _app({List<SavedMomoAccount>? fakeAccounts}) {
  return ProviderScope(
    overrides: [
      if (fakeAccounts != null)
        savedMomoProvider.overrideWith(() => _FakeSavedMomo(fakeAccounts)),
    ],
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
        child: DepositScreen(
          prefillAmount: s.uri.queryParameters['amount'],
          memo: s.uri.queryParameters['memo'],
        ),
      ),
    ),
  ],
);

/// Phone-surface viewport, tall enough for the non-compact layout.
void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  // risePage entry: 350ms transition.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tap a keypad key. Keys are scoped to the AmountKeypad so the
/// odometer's identical digit glyphs can never shadow a key.
Future<void> _tapKey(WidgetTester tester, String k) async {
  final finder = k == 'del'
      ? find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.byIcon(Icons.backspace_outlined),
        )
      : find.descendant(of: find.byType(AmountKeypad), matching: find.text(k));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
}

/// Let an odometer roll finish. During the roll the AnimatedSwitcher keeps
/// the outgoing digit cell mounted, so exact digit counts are only stable
/// once the transition (MotionTokens.emphasized = 350ms) completes. One
/// pump STARTS the animation (its frame swaps the children); a second pump
/// must advance past 350ms of animation time for the outgoing cell to be
/// unmounted.
Future<void> _settleRoll(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

Finder _odometerCell(String ch) =>
    find.descendant(of: find.byType(OdometerNumber), matching: find.text(ch));

void main() {
  // The financial layer runs against the demo interceptor — no network.
  AppConfig.enableDemoMode();

  group('A — fiat initial state', () {
    testWidgets('header shows one X close and the Add Cash title', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add Cash'), findsWidgets); // header title (and CTA)
      expect(find.byIcon(Icons.close), findsOneWidget);
      // No back arrow — the X is the ONE close affordance.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('Add Cash is dedicated to fiat and has no currency toggle', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Fiat'), findsNothing);
      expect(find.text('Crypto'), findsNothing);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
      expect(find.text('Deposit USDC'), findsNothing);
    });

    testWidgets('resting instrument: amount 0, pills, keypad, method, CTA', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      // Amount renders as 0 inside the odometer (the keypad also has a
      // '0' key, hence the descendant scoping).
      expect(
        find.descendant(
          of: find.byType(OdometerNumber),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );

      // Quick amounts: 50 / 100 / 200 / 500.
      expect(find.text('GH₵ 50'), findsOneWidget);
      expect(find.text('GH₵ 100'), findsOneWidget);
      expect(find.text('GH₵ 200'), findsOneWidget);
      expect(find.text('GH₵ 500'), findsOneWidget);

      // Keypad: all nine digits, decimal, backspace.
      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(find.text(d), findsOneWidget);
      }
      expect(find.text('.'), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

      // Demo seed: Kwame Mensah (MTN, primary) auto-selected.
      expect(find.text('Kwame Mensah'), findsOneWidget);
      expect(find.text('024 412 3456'), findsOneWidget);
    });

    testWidgets('CTA is inert without an amount and without an account', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(fakeAccounts: const []));
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      // No amount, no account: tapping Add Cash must not start the flow.
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Confirm account'), findsNothing);
      expect(
        find.text('Add a mobile money account to continue.'),
        findsOneWidget,
      );
    });
  });

  group('B — odometer wiring (state machine itself is unit-tested)', () {
    testWidgets('typing 50 rolls the odometer and exposes GH₵ 50', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await _tapKey(tester, '5');
      await _tapKey(tester, '0');
      await _settleRoll(tester);

      expect(_odometerCell('5'), findsOneWidget);
      expect(_odometerCell('0'), findsOneWidget);
    });

    testWidgets('1234 renders grouped as 1,234', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      for (final k in ['1', '2', '3', '4']) {
        await _tapKey(tester, k);
      }
      await _settleRoll(tester);
      expect(_odometerCell(','), findsOneWidget);
    });

    testWidgets('decimal typing is preserved as typed: 50.5', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      for (final k in ['5', '0', '.', '5']) {
        await _tapKey(tester, k);
      }
      await _settleRoll(tester);
      // '50.5' — the point, not padded to '50.50'.
      expect(_odometerCell('.'), findsOneWidget);
    });

    testWidgets('backspace deletes back down to 0', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await _tapKey(tester, '9');
      await _settleRoll(tester);
      await _tapKey(tester, 'del');
      await _settleRoll(tester);
      expect(_odometerCell('9'), findsNothing);
      expect(_odometerCell('0'), findsOneWidget);
    });
  });

  group('C — quick amounts', () {
    testWidgets('a pill sets the amount instantly', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('GH₵ 100'));
      await _settleRoll(tester);

      expect(_odometerCell('1'), findsOneWidget);
      expect(_odometerCell('0'), findsNWidgets(2)); // both zeros of 100
    });

    testWidgets('repeated pill taps are harmless', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('GH₵ 200'));
      await tester.tap(find.text('GH₵ 200'));
      await _settleRoll(tester);
      // Still 200 — no doubling, no crash.
      expect(_odometerCell('2'), findsOneWidget);
      expect(_odometerCell('0'), findsNWidgets(2));
    });
  });

  group('F — CTA and the Moolre flow (demo-backed end-to-end)', () {
    testWidgets('valid amount + account runs validate-name → confirm → '
        'initiate → result', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await _tapKey(tester, '5');
      await _tapKey(tester, '0');

      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(seconds: 1));

      // validate-name resolved the registered name → confirmation dialog.
      expect(find.text('Confirm account'), findsOneWidget);
      expect(find.textContaining('Kwame Mensah'), findsWidgets);

      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // postFinancial (durable ref) → no OTP → result view (waiting state).
      expect(find.text('Prompt sent'), findsOneWidget);
      expect(find.textContaining('Waiting for confirmation'), findsOneWidget);

      // Demo mode auto-confirms after 3s — pump past it so the Timer
      // drains AND the full success flow is verified.
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Deposit Confirmed!'), findsOneWidget);
      expect(find.text('Start another deposit'), findsOneWidget);
      // The durable reference is shown to the user.
      expect(find.textContaining('DEP-DEMO'), findsOneWidget);

      // Reset returns to the resting instrument with the amount cleared.
      await tester.tap(find.text('Start another deposit'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Prompt sent'), findsNothing);
      expect(_odometerCell('0'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation dialog aborts cleanly', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await _tapKey(tester, '7');
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Confirm account'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(seconds: 1));

      // Back on the resting instrument; the amount survives.
      expect(find.text('Confirm account'), findsNothing);
      await _settleRoll(tester);
      expect(_odometerCell('7'), findsOneWidget);
    });
  });

  group('I — accessibility', () {
    testWidgets('the surface exposes ONE coherent amount value and labeled '
        'controls', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump(const Duration(seconds: 1));

      // The odometer hides its per-digit cells (no digit spam) and exposes
      // the amount as a single coherent value.
      expect(find.bySemanticsLabel('GH₵ 0'), findsOneWidget);

      await _tapKey(tester, '5');
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.bySemanticsLabel('GH₵ 5'), findsOneWidget);

      // The close affordance is labeled.
      expect(find.bySemanticsLabel('Close Add Cash'), findsOneWidget);

      // Add Cash has no currency-selection tabs; Crypto lives on Receive.

      // Keypad keys carry labels — including the two non-digit keys.
      expect(find.bySemanticsLabel('Decimal point'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);

      semantics.dispose();
    });
  });
}
