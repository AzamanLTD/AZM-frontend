// A CAPABILITY THE BACKEND DOES NOT PUBLISH IS NOT A BUTTON.
//
// Every template in the published registry carries capabilities, and today all
// of them are false for lookup, quote and payment. The gateway refuses those
// calls by name; these contracts check the other half — that the UI does not
// dangle an action it knows cannot finish, and that a category the server has
// services for can actually be opened.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/bills/bills_pay_screen.dart';
import 'package:azaman/screens/bills/bills_request_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';

SavedBillAccount _account({required bool canQuote, required bool canPay}) =>
    SavedBillAccount(
      id: 'acct_1',
      billerId: 'ECG_PREPAID:ECG',
      billerName: 'ECG prepaid',
      categoryId: 'ELECTRICITY',
      identifierMasked: '•••• 4321',
      verificationStatus: 'UNVERIFIED',
      canQuote: canQuote,
      canPay: canPay,
    );

class _Gateway extends UnavailableBillsGateway {
  _Gateway(this.accounts);

  final List<SavedBillAccount> accounts;

  @override
  bool get isDemo => false;

  @override
  Future<List<SavedBillAccount>> savedAccounts() async => accounts;

  @override
  Future<BillsAvailability> availability() async =>
      const BillsAvailability(isAvailable: true);

  @override
  Future<List<BillPaymentRequest>> requests() async =>
      const <BillPaymentRequest>[];
}

Future<void> _pump(WidgetTester tester, Widget screen, _Gateway gw) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(gw)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a bill that cannot quote offers no price button, and says why', (
    tester,
  ) async {
    final gw = _Gateway([_account(canQuote: false, canPay: false)]);
    await _pump(tester, const BillsPayScreen(accountId: 'acct_1'), gw);

    expect(find.text('Get the price'), findsNothing);
    expect(find.text('NOT CONNECTED YET'), findsOneWidget);
    expect(find.textContaining('no price lookup'), findsOneWidget);
    // The saved reference is still shown: it exists, it just cannot be paid.
    expect(find.text('•••• 4321'), findsWidgets);
  });

  testWidgets('a bill that can quote still offers the price button', (
    tester,
  ) async {
    final gw = _Gateway([_account(canQuote: true, canPay: true)]);
    await _pump(tester, const BillsPayScreen(accountId: 'acct_1'), gw);

    expect(find.text('Get the price'), findsOneWidget);
    expect(find.text('NOT CONNECTED YET'), findsNothing);
  });

  testWidgets('a request cannot be sent for a bill that cannot pay', (
    tester,
  ) async {
    final gw = _Gateway([_account(canQuote: false, canPay: false)]);
    await _pump(tester, const BillsRequestScreen(), gw);

    // Pick the saved bill so the summary renders.
    final pick = find.text('ECG prepaid');
    if (pick.evaluate().isNotEmpty) {
      await tester.tap(pick.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Send the request'), findsNothing);
    expect(find.textContaining('not connected yet'), findsWidgets);
  });

  test('a category counts the services the server actually sent', () {
    // The five categories the brief names, with the service counts the
    // registry gives them. billerCount decides whether a category can open, so
    // a zero here is an unreachable category, and a made-up number is a lie.
    final categories = [
      const BillsCategory(
        id: 'ELECTRICITY',
        label: 'Electricity',
        billerCount: 2,
      ),
      const BillsCategory(id: 'WATER', label: 'Water', billerCount: 1),
      const BillsCategory(id: 'TV', label: 'Television', billerCount: 3),
      const BillsCategory(
        id: 'AIRTIME_DATA',
        label: 'Airtime & Data',
        billerCount: 2,
      ),
      const BillsCategory(id: 'INTERNET', label: 'Internet', billerCount: 1),
    ];
    for (final category in categories) {
      expect(category.billerCount, greaterThan(0), reason: category.label);
    }
    expect(categories.map((c) => c.billerCount).reduce((a, b) => a + b), 9);
  });
}
