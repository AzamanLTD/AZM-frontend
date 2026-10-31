// TRANSACTION HISTORY IS PROTECTED MONEY.
//
// Amounts, counterparties and references are exactly what the privacy lock is
// for, so while the gate is locked the list must not exist: not painted, not in
// the widget tree, not in the accessibility tree. This suite pins that, and
// pins that unlocking brings the real screen back.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/screens/transaction_history_screen.dart';

import '../support/money_access_test_support.dart';

Future<void> _pump(WidgetTester tester, {required bool unlocked}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (unlocked) unlockedMoneyAccess()],
      child: const MaterialApp(home: TransactionHistoryScreen()),
    ),
  );
  // One bounded pump: the history provider reaches for the network in this
  // environment and must not be waited on.
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a locked member sees a locked screen, not a list of amounts', (
    tester,
  ) async {
    await _pump(tester, unlocked: false);

    expect(find.text('Transactions are locked'), findsOneWidget);

    // The filters and rows are part of the protected surface.
    expect(find.text('ALL'), findsNothing);
    expect(find.text('INTERNAL'), findsNothing);
    expect(find.textContaining('GHS'), findsNothing);
    expect(find.textContaining('₵'), findsNothing);
    expect(find.textContaining('USDC'), findsNothing);
  });

  testWidgets('the locked screen offers a real way in', (tester) async {
    await _pump(tester, unlocked: false);

    expect(find.byKey(const ValueKey('history-unlock')), findsOneWidget);
    expect(
      find.text('Unlock'),
      findsOneWidget,
      reason: 'a locked screen with no route forward is a dead end',
    );
  });

  testWidgets('an unlocked member gets the history back', (tester) async {
    await _pump(tester, unlocked: true);

    expect(find.text('Transactions are locked'), findsNothing);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('INTERNAL'), findsOneWidget);
  });
}
