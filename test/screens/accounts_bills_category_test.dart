// AZAMAN — ACCOUNTS · SAVED BILL ACCOUNTS contracts.
//
// The third Accounts category. It reports the member's saved bill references
// from the Bills contract, and nothing else:
//
//   • a locked app builds no list and fetches nothing, so no mask leaks;
//   • what is shown is the service label, the nickname, the SERVER's mask,
//     the primary flag and the server's verification status;
//   • the reference is never printed in plaintext and no holder name is
//     invented;
//   • there is no Pay action here — paying belongs to the guarded hub;
//   • an unavailable list is stated, never rendered as "you have none".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/screens/accounts_screen.dart';
import 'package:azaman/screens/bills/bills_saved_accounts_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';

class _Gateway extends UnavailableBillsGateway {
  _Gateway({this.rows = const [], this.fail = false});

  final List<SavedBillAccount> rows;
  final bool fail;
  int savedAccountCalls = 0;

  @override
  Future<List<SavedBillAccount>> savedAccounts() async {
    savedAccountCalls++;
    if (fail) throw const BillsUnavailableException('Saved bills are down.');
    return rows;
  }
}

SavedBillAccount _account({
  String id = 'acc-1',
  String? alias = 'My Apartment',
  bool isPrimary = true,
  String status = 'UNVERIFIED',
}) => SavedBillAccount(
  id: id,
  billerId: 'ECG_PREPAID:ECG',
  billerName: 'ECG prepaid',
  categoryId: 'ELECTRICITY',
  identifierMasked: '•••• 7890',
  alias: alias,
  isPrimary: isPrimary,
  verificationStatus: status,
);

Future<_Gateway> _pump(
  WidgetTester tester, {
  required Widget home,
  _Gateway? gateway,
  bool unlocked = true,
}) async {
  final fake = gateway ?? _Gateway();
  await tester.binding.setSurfaceSize(const Size(420, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(fake)],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();

  if (unlocked) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final access = container.read(moneyAccessProvider);
    access.finishUnlock(access.beginUnlock());
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return fake;
}

void main() {
  testWidgets('Accounts carries the third category and opens it', (
    tester,
  ) async {
    await _pump(tester, home: const AccountsScreen());

    expect(find.text('Deposit accounts'), findsOneWidget);
    expect(find.text('Payout destinations'), findsOneWidget);
    expect(find.text('Saved bill accounts'), findsOneWidget);

    await tester.tap(find.text('Saved bill accounts'));
    await tester.pumpAndSettle();
    expect(find.byType(BillsSavedAccountsScreen), findsOneWidget);
  });

  testWidgets('a saved bill shows label, nickname, mask, primary and status', (
    tester,
  ) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(rows: [_account()]),
    );

    expect(find.text('My Apartment'), findsOneWidget);
    expect(find.textContaining('ECG prepaid'), findsOneWidget);
    expect(find.textContaining('Primary'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.textContaining('•••• 7890'), findsOneWidget);
  });

  testWidgets('the reference is never printed and no holder name is invented', (
    tester,
  ) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(rows: [_account()]),
    );

    expect(find.textContaining('1234567890'), findsNothing);
    expect(find.textContaining('holder'), findsNothing);
    expect(find.textContaining('cipher'), findsNothing);
    expect(find.textContaining('fingerprint'), findsNothing);
  });

  testWidgets('there is no Pay action on a saved reference', (tester) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(rows: [_account()]),
    );

    // The explanatory line mentions paying in Bills; no control here pays.
    expect(find.text('Pay'), findsNothing);
    expect(find.byType(BillsPrimaryButton), findsNothing);
    expect(find.textContaining('GHS'), findsNothing);
  });

  testWidgets('locked: nothing is fetched and no mask is built', (
    tester,
  ) async {
    final gateway = await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(rows: [_account()]),
      unlocked: false,
    );

    expect(
      gateway.savedAccountCalls,
      0,
      reason: 'the lock refuses the request instead of hiding its result',
    );
    expect(find.textContaining('••••'), findsNothing);
    expect(find.text('My Apartment'), findsNothing);
    expect(find.textContaining('Unlock'), findsOneWidget);
  });

  testWidgets('no saved bills is an empty state that leads to discovery', (
    tester,
  ) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(),
    );

    expect(find.textContaining('No saved bills yet'), findsOneWidget);
    expect(find.text('Find a biller'), findsOneWidget);
  });

  testWidgets('an unavailable list is not reported as having none', (
    tester,
  ) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(fail: true),
    );

    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(find.textContaining('No saved bills yet'), findsNothing);
    expect(find.text('Find a biller'), findsNothing);
  });

  testWidgets('rename, primary and remove are offered, not the identifier', (
    tester,
  ) async {
    await _pump(
      tester,
      home: const BillsSavedAccountsScreen(),
      gateway: _Gateway(rows: [_account()]),
    );

    await tester.tap(find.byKey(const ValueKey('saved-bill-actions-acc-1')));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Remove primary'), findsOneWidget);
    expect(find.text('Remove this bill'), findsOneWidget);
    // Nothing here edits the reference itself.
    expect(find.textContaining('Edit number'), findsNothing);
  });
}
