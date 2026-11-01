// A DEEP LINK IS NOT A KEY.
//
// The Home trigger, the history and the savings sheet all read the gate. A
// notification or a link straight to `/withdraw`, `/send`, `/deposit`,
// `/convert`, `/card-transfer`, `/payment-requests`, `/request/:token` or the
// activity list did not — it resolved to a live money composer even while the
// app was locked.
//
// MoneyRouteGuard closes that: while the gate is shut the destination is never
// built (so it cannot fetch a balance, quote a fee or paint an amount), the
// member keeps the address, and unlocking rebuilds in place.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/money_route_guard.dart';

import '../support/money_access_test_support.dart';

/// A screen that would be a leak if it ever ran while locked: it records the
/// fact that it was built, and paints a balance as soon as it is.
class _MoneyProbe extends StatelessWidget {
  const _MoneyProbe({required this.builds});

  final ValueNotifier<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.value++;
    return const Scaffold(body: Center(child: Text('GHS 8,412.00')));
  }
}

Future<ValueNotifier<int>> _pump(
  WidgetTester tester, {
  required bool unlocked,
}) async {
  final builds = ValueNotifier<int>(0);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (unlocked) unlockedMoneyAccess()],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MoneyRouteGuard(child: _MoneyProbe(builds: builds)),
      ),
    ),
  );
  await tester.pump();
  return builds;
}

void main() {
  testWidgets('locked: the destination is never built', (tester) async {
    final builds = await _pump(tester, unlocked: false);

    expect(
      builds.value,
      0,
      reason: 'a locked deep link must not run the screen at all',
    );
    expect(find.textContaining('GHS'), findsNothing);
    expect(find.text('GHS 8,412.00'), findsNothing);
  });

  testWidgets('locked: the surface explains itself and offers no action', (
    tester,
  ) async {
    await _pump(tester, unlocked: false);

    expect(find.byKey(const ValueKey('locked-money-surface')), findsOneWidget);
    expect(find.text('Your money is locked'), findsOneWidget);
    expect(find.textContaining('Azaman button'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('locked: a tap shakes and stays exactly where it is', (
    tester,
  ) async {
    await _pump(tester, unlocked: false);

    await tester.tap(find.byKey(const ValueKey('locked-money-surface')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(find.text('Your money is locked'), findsOneWidget);
    expect(find.textContaining('GHS'), findsNothing);
  });

  testWidgets('unlocked: the same address reaches the real screen', (
    tester,
  ) async {
    final builds = await _pump(tester, unlocked: true);

    expect(builds.value, greaterThan(0));
    expect(find.text('GHS 8,412.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-money-surface')), findsNothing);
  });

  testWidgets('unlocking rebuilds in place, without a second navigation', (
    tester,
  ) async {
    final builds = await _pump(tester, unlocked: false);
    expect(builds.value, 0);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MoneyRouteGuard)),
    );
    final controller = container.read(moneyAccessProvider);
    final attempt = controller.beginUnlock();
    controller.finishUnlock(attempt);
    await tester.pump();
    await tester.pump();

    expect(
      builds.value,
      greaterThan(0),
      reason: 'the member stays on the linked address and it resolves',
    );
    expect(find.text('GHS 8,412.00'), findsOneWidget);
  });
}
