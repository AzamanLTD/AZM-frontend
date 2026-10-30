// SAVING A BILL THE BACKEND CAN ACTUALLY SAVE.
//
// The published contract (AZM-backend, feat/bills-saved-service-accounts)
// accepts a service code, a provider code and one identifier field, and answers
// with a server-made mask and a verification STATUS. It performs no lookup, so
// there is no holder name to show.
//
// That made the save screen dead-end: it waited for a lookup that the backend
// deliberately does not offer. These contracts pin the honest way out — the
// member can save the reference, the screen says plainly that no holder name
// will appear until lookup exists, and nothing about the member's typing is
// presented as a verified identity.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/bills/bills_add_account_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';

/// Refuses lookup exactly as HttpBillsGateway does when the service registry
/// says `lookupAccount: false`, and records what a save was asked to store.
class _NoLookupGateway extends UnavailableBillsGateway {
  final List<Map<String, String?>> saves = <Map<String, String?>>[];
  int lookups = 0;

  @override
  Future<List<Biller>> billers({String? categoryId}) async => const [
    Biller(
      id: 'ECG_PREPAID:ECG',
      categoryId: 'ELECTRICITY',
      name: 'ECG prepaid',
      identifierLabel: 'Meter number',
    ),
  ];

  @override
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  }) async {
    lookups++;
    throw const BillsUnavailableException(
      'ECG prepaid cannot be verified yet: no provider lookup is connected.',
    );
  }

  @override
  Future<SavedBillAccount> saveAccount({
    required String billerId,
    required String identifier,
    String? alias,
  }) async {
    saves.add({'billerId': billerId, 'identifier': identifier, 'alias': alias});
    return SavedBillAccount(
      id: 'acct_1',
      billerId: billerId,
      billerName: 'ECG prepaid',
      categoryId: 'ELECTRICITY',
      identifierMasked: '•••• 7890',
      // The contract returns a status, not a name.
      verificationStatus: 'UNVERIFIED',
      alias: alias,
    );
  }
}

Future<void> _pump(WidgetTester tester, _NoLookupGateway gateway) async {
  await tester.binding.setSurfaceSize(const Size(420, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: BillsAddAccountScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _attemptLookup(WidgetTester tester) async {
  await tester.tap(find.text('ECG prepaid'));
  await tester.pump();
  await tester.enterText(find.byType(TextField).first, '1234567890');
  await tester.tap(find.text('Look it up'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'a refused lookup offers saving, and says why nothing is verified',
    (tester) async {
      final gateway = _NoLookupGateway();
      await _pump(tester, gateway);
      await _attemptLookup(tester);

      expect(gateway.lookups, 1);
      expect(find.text('3 · SAVE UNVERIFIED'), findsOneWidget);
      expect(
        find.textContaining('no provider lookup is connected'),
        findsOneWidget,
        reason: 'the server\'s own reason reaches the member',
      );
      expect(
        find.textContaining('no holder name will be shown'),
        findsOneWidget,
      );
      // A refused capability is not a dead end: no error banner about being
      // unable to reach the biller.
      expect(find.text('Look it up'), findsNothing);
    },
  );

  testWidgets(
    'saving sends the service identity and the typed identifier only',
    (tester) async {
      final gateway = _NoLookupGateway();
      await _pump(tester, gateway);
      await _attemptLookup(tester);

      await tester.enterText(find.byType(TextField).last, 'My Apartment');
      await tester.tap(find.text('Save without verification'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.saves.length, 1);
      expect(gateway.saves.single['billerId'], 'ECG_PREPAID:ECG');
      expect(gateway.saves.single['identifier'], '1234567890');
      expect(gateway.saves.single['alias'], 'My Apartment');
    },
  );

  testWidgets('no holder name is ever printed for an unverified save', (
    tester,
  ) async {
    final gateway = _NoLookupGateway();
    await _pump(tester, gateway);
    await _attemptLookup(tester);

    // The CONFIRM step is the only place a holder name can appear, and it only
    // exists once a lookup returned one.
    expect(find.text('3 · CONFIRM'), findsNothing);
    expect(find.text('Account holder'), findsNothing);
  });
}
