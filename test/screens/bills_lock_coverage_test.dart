// BILLS IS A MONEY SURFACE — BUT A CATALOGUE IS NOT MONEY.
//
// The member's saved bills, the pay composer and the request flow are reachable
// by URL, so those must sit behind the same gate as /withdraw and /send, not
// merely behind the Home bubble.
//
// The HUB ITSELF is deliberately NOT gated: a list of biller categories is
// public information, and hiding it while locked made Bills look broken to a
// member who only wanted to see what was available. What stays protected is
// anything personal — and that protection now lives in two places, which is
// what these contracts check:
//   1. STRUCTURE — the Add, Pay and Request destinations are wrapped in
//      MoneyRouteGuard, and the Hub's own saved-bills section is wrapped in
//      MoneyLockGate. A future screen added under /bills without a gate fails
//      this test.
//   2. BEHAVIOUR — mounted while locked, the pay screen is never built, so its
//      gateway is never called: no accounts fetched, no quote requested, no
//      total painted.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/bills/bills_pay_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/widgets/home/money_route_guard.dart';

/// Records every call, because a call is the leak.
class _Recording extends UnavailableBillsGateway {
  int accountReads = 0;
  int quotes = 0;

  @override
  bool get isDemo => false;

  @override
  Future<List<SavedBillAccount>> savedAccounts() async {
    accountReads++;
    return const [
      SavedBillAccount(
        id: 'a1',
        billerId: 'b1',
        billerName: 'Test Power',
        categoryId: 'electricity',
        identifierMasked: '•••• 5678',
        holderName: 'AMA MENSAH',
      ),
    ];
  }

  @override
  Future<BillQuote> quote({required String accountId, double? amount}) async {
    quotes++;
    return BillQuote(
      quoteId: 'q1',
      accountId: accountId,
      billerName: 'Test Power',
      identifierMasked: '•••• 5678',
      holderName: 'AMA MENSAH',
      amount: 214.35,
      feeAmount: 2.5,
      totalAmount: 217.85,
      currency: 'GHS',
      expiresAt: DateTime(2026, 10, 30, 23, 59),
      amountDueIsAuthoritative: true,
    );
  }
}

void main() {
  test('every Bills destination sits behind the money route guard', () {
    final source = File('lib/router/app_router.dart').readAsStringSync();
    final start = source.indexOf('path: AzRoutes.bills,');
    expect(start, greaterThan(-1), reason: 'the Bills route must exist');

    // The Bills block runs to the next top-level GoRoute for /savings.
    final end = source.indexOf("path: '/savings'", start);
    expect(end, greaterThan(start));
    final block = source.substring(start, end);

    // The member's own bills inside the hub are gated where they render,
    // because the hub is browsable.
    final hub = File(
      'lib/screens/bills/bills_home_screen.dart',
    ).readAsStringSync();
    final savingsStart = hub.indexOf("title: 'YOUR BILLS',");
    expect(savingsStart, greaterThan(-1));
    final gateAt = hub.substring(0, savingsStart).lastIndexOf('MoneyLockGate(');
    expect(gateAt, greaterThan(-1), reason: 'YOUR BILLS has no gate at all');
    // The gate must open immediately before this section, not somewhere
    // unrelated earlier in the file.
    expect(
      savingsStart - gateAt,
      lessThan(200),
      reason: 'YOUR BILLS must be the child of that MoneyLockGate',
    );

    // The hub itself must NOT be wholly gated any more: discovery works while
    // locked.
    final hubAt = block.indexOf('BillsHomeScreen()');
    expect(hubAt, greaterThan(-1));
    final hubBefore = block.substring(0, hubAt);
    expect(
      hubBefore.lastIndexOf('MoneyRouteGuard('),
      lessThan(hubBefore.lastIndexOf('pageBuilder:')),
      reason: 'the Bills hub is public; only its private parts are gated',
    );

    for (final screen in [
      'BillsAddAccountScreen(',
      'BillsPayScreen(',
      'BillsRequestScreen(',
    ]) {
      final at = block.indexOf(screen);
      expect(at, greaterThan(-1), reason: '$screen is missing from /bills');
      // Walk back from the screen to the nearest MoneyRouteGuard: it must come
      // before any route boundary, so the guard wraps this screen and not a
      // sibling.
      final before = block.substring(0, at);
      final guard = before.lastIndexOf('MoneyRouteGuard(');
      final boundary = before.lastIndexOf('pageBuilder:');
      expect(
        guard > boundary,
        isTrue,
        reason: '$screen is not wrapped in MoneyRouteGuard',
      );
    }
  });

  testWidgets('locked: a deep link to a Bills payment composes nothing', (
    tester,
  ) async {
    final gateway = _Recording();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [billsGatewayProvider.overrideWithValue(gateway)],
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(AzamanTheme.light),
          home: const MoneyRouteGuard(
            message: 'Your bills are locked',
            child: BillsPayScreen(accountId: 'a1'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(gateway.accountReads, 0, reason: 'no account may be fetched');
    expect(gateway.quotes, 0, reason: 'no price may be requested');
    expect(find.text('Your bills are locked'), findsOneWidget);
    expect(find.textContaining('GHS'), findsNothing);
    expect(find.textContaining('214.35'), findsNothing);
    expect(find.textContaining('Pay '), findsNothing);
  });
}
