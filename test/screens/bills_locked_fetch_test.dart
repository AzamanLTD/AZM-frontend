// THE LOCK MUST STOP THE REQUEST, NOT JUST THE PAINT.
//
// The defect these contracts exist for: the Bills hub rendered its private
// section inside a MoneyLockGate while still watching `billsHubProvider` ABOVE
// the gate. The provider loads the member's saved accounts, so a locked member
// made a private API call and kept a full snapshot in memory — the lock only
// decided whether the pixels were shown.
//
// A gateway that counts calls is the only honest witness: asserting on the
// string "Your bills are locked" proves the gate rendered, not that the data
// stayed unsent. So every contract here asserts on the COUNTER.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/screens/bills/bills_home_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/services/bills/http_bills_gateway.dart';

/// Records every private read the screen causes.
class _RecordingGateway extends UnavailableBillsGateway {
  int availabilityCalls = 0;
  int hubCalls = 0;
  int savedAccountCalls = 0;

  @override
  Future<BillsAvailability> availability() async {
    availabilityCalls++;
    // The catalogue is public: a locked member may still discover services.
    return const BillsAvailability(
      isAvailable: true,
      categories: [BillsCategory(id: 'ELECTRICITY', label: 'Electricity')],
    );
  }

  @override
  Future<BillsHubSnapshot> hub() async {
    hubCalls++;
    return const BillsHubSnapshot(
      savedAccounts: [
        SavedBillAccount(
          id: 'a1',
          billerId: 'b1',
          billerName: 'Test Power',
          categoryId: 'electricity',
          identifierMasked: '•••• 9911',
          verificationStatus: 'UNVERIFIED',
        ),
      ],
    );
  }

  @override
  Future<List<SavedBillAccount>> savedAccounts() async {
    savedAccountCalls++;
    return (await hub()).savedAccounts;
  }
}

Future<_RecordingGateway> _pump(
  WidgetTester tester, {
  required bool unlocked,
}) async {
  final gateway = _RecordingGateway();
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: BillsHomeScreen()),
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
  return gateway;
}

void main() {
  testWidgets('locked: the private hub is never fetched', (tester) async {
    final gateway = await _pump(tester, unlocked: false);

    expect(
      gateway.hubCalls,
      0,
      reason: 'the lock must refuse the request, not hide its result',
    );
    expect(gateway.savedAccountCalls, 0);
    expect(
      gateway.availabilityCalls,
      greaterThan(0),
      reason: 'the service catalogue is public and may load while locked',
    );
  });

  testWidgets('locked: no saved-account data is constructed at all', (
    tester,
  ) async {
    final gateway = await _pump(tester, unlocked: false);

    // The mask, the biller label and the account's own title are all private.
    expect(find.textContaining('9911'), findsNothing);
    expect(find.text('Test Power'), findsNothing);
    expect(find.text('Unverified'), findsNothing);
    // Public discovery is still there.
    expect(find.text('Electricity'), findsOneWidget);
    expect(gateway.hubCalls, 0);
  });

  testWidgets('unlocked: the same screen does fetch, and shows the account', (
    tester,
  ) async {
    final gateway = await _pump(tester, unlocked: true);

    expect(gateway.hubCalls, 1);
    expect(find.textContaining('9911'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
  });

  testWidgets('locking again drops the data instead of keeping the snapshot', (
    tester,
  ) async {
    await _pump(tester, unlocked: true);
    expect(find.textContaining('9911'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(moneyAccessProvider).lock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('9911'),
      findsNothing,
      reason: 'a re-lock must not leave the previous snapshot on screen',
    );
  });

  group('capabilities fail closed', () {
    test('a saved account claims nothing it was not told', () {
      const account = SavedBillAccount(
        id: 'a1',
        billerId: 'b1',
        billerName: 'Test Power',
        categoryId: 'electricity',
        identifierMasked: '•••• 9911',
      );
      expect(account.canQuote, isFalse);
      expect(account.canPay, isFalse);
    });

    test('an absent capability object is not permission', () {
      for (final raw in <Object?>[null, const <String, dynamic>{}, 'yes']) {
        final caps = BillServiceCapabilities.fromJson(raw);
        expect(caps.lookupAccount, isFalse);
        expect(caps.quote, isFalse);
        expect(caps.payment, isFalse);
      }
    });

    test('only an explicit true grants a capability', () {
      final caps = BillServiceCapabilities.fromJson(const <String, dynamic>{
        'saveAccount': true,
      });
      expect(caps.saveAccount, isTrue);
      expect(caps.quote, isFalse);
      expect(caps.payment, isFalse);
    });
  });
}
