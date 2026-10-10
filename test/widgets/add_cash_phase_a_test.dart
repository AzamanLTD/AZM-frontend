// =============================================================================
// UI-CORRECTION PHASE A — ADD CASH COMPOSITION + SELECTOR (2026-10-03)
//
// Composition grammar (handoff §4.2): a Phantom-style TOP-LEFT amount with
// the payment-method row DIRECTLY under it (not under the keypad), quick
// amounts, keypad, and the CTA anchored to the bottom. The selected-method
// row is a filled surface with NO border.
//
// Selector grammar (handoff §4.3): ONE bottom-sheet selector. Selecting:
//   1. fires the selection haptic,
//   2. moves the accent check IMMEDIATELY (same frame, sheet still open),
//   3. closes the sheet after a tiny acknowledgement delay.
//
// These tests fail against the pre-fix implementation:
//   • the amount was CENTERED (its glyph sat mid-screen, not top-left);
//   • the method row lived UNDER the keypad;
//   • the selected-method row carried a stroked border;
//   • selecting popped the sheet immediately — the check never moved inside
//     the open sheet (it stayed on the previously selected row).
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
import 'package:azaman/widgets/odometer_number.dart';

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

final _twoWithPrimary = [
  _acct(
    'a1',
    'Kwame',
    'MTN',
    '0244123456',
    accountName: 'Kwame Mensah',
    isPrimary: true,
  ),
  _acct('a2', 'Ama', 'TELECEL', '0500987654', accountName: 'Ama Boateng'),
];

Widget _app() {
  return ProviderScope(
    overrides: [savedMomoProvider.overrideWith(() => _FakeSavedMomo(_twoWithPrimary))],
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

void _phoneSize(WidgetTester tester, {Size size = const Size(420, 920)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _odometerCell(String ch) =>
    find.descendant(of: find.byType(OdometerNumber), matching: find.text(ch));

void main() {
  AppConfig.enableDemoMode();

  group('Phase A — Phantom top-left composition', () {
    testWidgets('the amount sits top-LEFT, not centered', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      final zeroRect = tester.getRect(_odometerCell('0'));
      final symbolRect = tester.getRect(find.text('GH₵'));
      // Viewport is 420 wide. Top-left composition: the cedi symbol is
      // glued to the 24px page margin and the amount glyph follows it —
      // both live in the left region. The pre-fix CENTERED instrument put
      // the symbol at ~left 110 and the glyph at ~left 200.
      expect(symbolRect.left <= 30, isTrue,
          reason: 'the amount row must start at the page margin');
      expect(zeroRect.left < 140, isTrue,
          reason: 'the amount must sit in the top-left region, not centered');
      // And it is genuinely at the TOP: below it come the method row,
      // pills, keypad and CTA — all with larger vertical positions.
      final methodRect = tester.getRect(find.text('Kwame Mensah'));
      final pillRect = tester.getRect(find.text('GH₵ 50'));
      final keypadRect = tester.getRect(find.byType(AmountKeypad));
      final ctaRect = tester.getRect(find.text('Add Cash').last);

      expect(zeroRect.bottom < methodRect.top, isTrue);
      expect(methodRect.bottom < pillRect.top, isTrue,
          reason: 'the method row must sit directly under the amount, '
              'above the quick amounts');
      expect(pillRect.bottom < keypadRect.top, isTrue);
      expect(keypadRect.bottom < ctaRect.top, isTrue);
    });

    testWidgets('the payment-method row sits directly under the amount '
        '(not under the keypad)', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      final method = tester.getRect(find.text('Kwame Mensah'));
      final keypad = tester.getRect(find.byType(AmountKeypad));
      // The method row is in the UPPER half of the surface.
      expect(method.top < keypad.top - 100, isTrue);
    });

    testWidgets('the selected-method row is a filled surface with NO border',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      // No container wrapping the method row may carry a stroked border —
      // separation comes from the surface fill, not a box-in-box outline.
      final containers = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('Kwame Mensah'),
          matching: find.byType(Container),
        ),
      );
      final bordered = containers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).border != null,
      );
      expect(bordered, isEmpty,
          reason: 'the method row must be borderless (fill only)');
    });

    testWidgets('no overflow on a narrow 360dp viewport', (tester) async {
      _phoneSize(tester, size: const Size(360, 740));
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // The full instrument is present even when narrow.
      expect(find.text('Kwame Mensah'), findsOneWidget);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.text('Add Cash').last, findsOneWidget);
    });
  });

  group('Phase A — payment selector grammar', () {
    testWidgets('selecting moves the check IMMEDIATELY inside the still-open '
        'sheet, then closes after the acknowledgement delay', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      // Open the selector.
      await tester.tap(find.text('Kwame Mensah'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Select the second account.
      await tester.tap(find.text('Ama Boateng'));
      await tester.pump(); // ONE frame — no settle, no clock advance

      // The sheet is still open…
      expect(find.text('Payment method'), findsOneWidget);
      // …and the accent check has ALREADY moved to Ama's row. The pre-fix
      // sheet popped on the tap itself, so the check never moved in-sheet.
      final amaRow = find.ancestor(
        of: find.text('Ama Boateng'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: amaRow, matching: find.byIcon(Icons.check)),
        findsOneWidget,
        reason: 'the check must change on the very frame the row is tapped',
      );
      // Exactly one check total — Kwame's row is deselected.
      expect(find.byIcon(Icons.check), findsOneWidget);

      // After the tiny acknowledgement delay the sheet closes.
      await tester.pumpAndSettle();
      expect(find.text('Payment method'), findsNothing);
      // The surface behind now shows the new selection.
      expect(find.text('Ama Boateng'), findsOneWidget);

      // Reopening shows the SAME selection still checked.
      await tester.tap(find.text('Ama Boateng'));
      await tester.pumpAndSettle();
      final amaRow2 = find.ancestor(
        of: find.text('Ama Boateng'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: amaRow2, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('the selector is a bottom sheet with the 28dp top radius',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Kwame Mensah'));
      await tester.pumpAndSettle();

      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, isNotNull);
      final shape = sheet.shape as RoundedRectangleBorder;
      final radius = shape.borderRadius as BorderRadius;
      expect(radius.topLeft, const Radius.circular(28));
      // The barrier is a translucent page-coloured scrim (~60% alpha).
      // (Several barriers exist in the tree; the sheet's is the coloured one.)
      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .where((b) => b.color != null)
          .toList();
      expect(barriers, isNotEmpty);
      for (final barrier in barriers) {
        expect((barrier.color!.a * 255.0).round(), closeTo(153, 2)); // 0.6 × 255
      }
    });

    testWidgets('Add Cash does not mount a Crypto destination', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Fiat'), findsNothing);
      expect(find.text('Crypto'), findsNothing);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.text('Receive USDC'), findsNothing);
    });
  });
}
