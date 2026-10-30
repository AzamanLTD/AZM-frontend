// THE LOCK IS NOT A HOME SCREEN PROPERTY.
//
// Two surfaces reachable from ordinary browsing still handed out money while
// the member was locked:
//
//   • the P2P marketplace's own cash-balance card, which has an eye toggle the
//     member controls — but no notion of the privacy lock, so a member who had
//     never toggled it saw their balance over a public catalogue;
//   • the peer transfer sheet, opened from a chat, which composed a payment
//     with a balance, an amount field and a confirm control.
//
// These contracts pin the fix: the figure is masked, the money pills refuse in
// place, and the composer is never built while locked.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';

import '../support/money_access_test_support.dart';

void main() {
  testWidgets('the locked gate never builds the composer it wraps', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(AzamanTheme.light),
          home: Scaffold(
            body: MoneyLockGate(
              message: 'Sending money is locked',
              child: Builder(
                builder: (context) {
                  builds++;
                  return const TextField();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(builds, 0, reason: 'a locked composer must not exist at all');
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Sending money is locked'), findsOneWidget);
  });

  testWidgets('the same gate builds the composer once the money is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [unlockedMoneyAccess()],
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(AzamanTheme.light),
          home: Scaffold(
            body: MoneyLockGate(
              message: 'Sending money is locked',
              child: const TextField(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sending money is locked'), findsNothing);
  });
}
