// A GOAL SHEET IS MONEY, AND THE GATE REACHES IT.
//
// The Home deck and the history were the visible leaks; a savings goal is the
// quiet one. Its header states how much is saved, how much is left, and what
// the schedule moves each month, and its two action tiles move money out of the
// wallet. All of that has to obey the same lock:
//
//   • while locked, no figure reaches text, semantics or a screenshot;
//   • while locked, Fund and Withdraw refuse with the same honest feedback the
//     rest of the app uses — they never open an amount pad;
//   • unlocked, the figures come back and the pad opens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/savings_goal_sheet.dart';

import '../support/money_access_test_support.dart';

final _goal = <String, dynamic>{
  'id': 'goal-1',
  'name': 'Rent 2027',
  'status': 'ACTIVE',
  'frequency': 'MONTHLY',
  'frequencyAmount': 250.0,
  'currentAmountGhs': 1250.0,
  'targetAmountGhs': 5000.0,
  'isLocked': false,
};

Future<void> _open(WidgetTester tester, {required bool unlocked}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (unlocked) unlockedMoneyAccess()],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => SavingsGoalSheet.show(
                  context,
                  goal: _goal,
                  onChanged: () {},
                ),
                child: const Text('open goal'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open goal'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('locked: no figure survives in the sheet', (tester) async {
    await _open(tester, unlocked: false);

    expect(find.text('Rent 2027'), findsOneWidget);
    expect(find.textContaining('1,250'), findsNothing);
    expect(find.textContaining('1250'), findsNothing);
    expect(find.textContaining('5,000'), findsNothing);
    expect(find.textContaining('5000'), findsNothing);
    expect(find.textContaining('250'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
  });

  testWidgets('locked: semantics carry no amounts', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, unlocked: false);

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label ?? '')
        .join(' ');
    expect(labels.contains('1,250'), isFalse);
    expect(labels.contains('1250'), isFalse);
    expect(labels.contains('5,000'), isFalse);
    handle.dispose();
  });

  testWidgets('locked: Fund refuses and never opens an amount pad', (
    tester,
  ) async {
    await _open(tester, unlocked: false);

    await tester.tap(find.text('Fund'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The pad's own heading, and its submit control, must not appear.
    expect(find.textContaining('GHS'), findsNothing);
    expect(find.text('Rent 2027'), findsOneWidget);
  });

  testWidgets('locked: Withdraw refuses too', (tester) async {
    await _open(tester, unlocked: false);

    await tester.tap(find.text('Withdraw'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('GHS'), findsNothing);
  });

  testWidgets('unlocked: the goal states its real amounts again', (
    tester,
  ) async {
    await _open(tester, unlocked: true);

    // The sheet prints the ledger figures verbatim: current / target.
    expect(find.textContaining('1250.00'), findsWidgets);
    expect(find.textContaining('250'), findsWidgets);
    expect(find.textContaining('••••'), findsNothing);
  });
}
