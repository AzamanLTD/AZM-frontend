// THE BILLS HUB MAY NOT INVENT A BILL.
//
// Until the backend contract for billers is agreed, the only honest screen is
// one that says so. These tests pin that, and pin the shape the hub takes when
// the server DOES report reachable billers:
//
//   • an unconfigured backend shows the truth, with no biller names, no
//     accounts, no amounts and nothing that looks payable;
//   • a failing gateway is treated as unavailable, never as empty-but-fine;
//   • categories come from the server verbatim, counts included;
//   • the production gateway is the unavailable one — no demo data ships.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/bills/bills_home_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';

class _FakeGateway implements BillsGateway {
  _FakeGateway(this.answer);

  final Future<BillsAvailability> Function() answer;

  @override
  Future<BillsAvailability> availability() => answer();
}

Future<void> _pump(WidgetTester tester, BillsGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: BillsHomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unconfigured backend tells the truth and offers nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeGateway(() async => BillsAvailability.unavailable),
    );

    expect(find.text('Bill payments are not available yet'), findsOneWidget);
    // No invented catalogue, no invented money.
    expect(find.textContaining('ECG'), findsNothing);
    expect(find.textContaining('DStv'), findsNothing);
    expect(find.textContaining('GHS'), findsNothing);
    expect(find.textContaining('₵'), findsNothing);
    expect(find.textContaining('Pay'), findsNothing);
  });

  testWidgets('a failing gateway is unavailable, not empty-but-fine', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeGateway(() async => throw StateError('bills service down')),
    );

    expect(find.text('Bill payments are not available yet'), findsOneWidget);
  });

  testWidgets('server-reported categories are rendered as reported', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeGateway(
        () async => const BillsAvailability(
          isAvailable: true,
          categories: [
            BillsCategory(id: 'electricity', label: 'Electricity'),
            BillsCategory(id: 'water', label: 'Water', billerCount: 2),
          ],
        ),
      ),
    );

    expect(find.text('Electricity'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // The unavailable copy must not linger once the facility exists.
    expect(find.text('Bill payments are not available yet'), findsNothing);
  });

  test('the production gateway ships no demo billers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(billsGatewayProvider),
      isA<UnavailableBillsGateway>(),
      reason: 'a fake gateway in the live app is a fake bill',
    );
  });

  test('no live Bills source hardcodes a biller brand', () {
    // FEX's published billers are not proof our credentials reach them, and a
    // brand name in the source is how a fake catalogue starts.
    final brands = [
      'ECG',
      'Ghana Water',
      'DStv',
      'GOtv',
      'StarTimes',
      'Telecel',
    ];
    final sources =
        Directory('lib/services/bills')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..addAll(
            Directory('lib/screens/bills')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')),
          );

    expect(sources, isNotEmpty);
    for (final file in sources) {
      final content = file.readAsStringSync();
      for (final brand in brands) {
        expect(
          content.contains(brand),
          isFalse,
          reason: '${file.path} hardcodes the biller "$brand"',
        );
      }
    }
  });
}
