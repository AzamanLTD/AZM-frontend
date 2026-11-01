// The locked surface must be a REPLACEMENT, not a blur: while locked the
// protected subtree is not built at all, so no amount can leak through
// semantics or the accessibility tree. Tapping it hints instead of acting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';

Widget _host(Widget child, {required MoneyAccessController access}) {
  return ProviderScope(
    overrides: [moneyAccessProvider.overrideWith((ref) => access)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('locked hides the protected content entirely', (tester) async {
    await tester.pumpWidget(
      _host(
        const MoneyLockGate(child: Text('GH₵ 1,250.00')),
        access: MoneyAccessController(),
      ),
    );
    expect(
      find.text('GH₵ 1,250.00'),
      findsNothing,
      reason: 'a locked amount must not exist in the tree',
    );
    expect(find.byType(LockedMoneySurface), findsOneWidget);
    expect(find.textContaining('locked'), findsWidgets);
  });

  testWidgets('the protected content cannot be read by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const MoneyLockGate(child: Text('GH₵ 1,250.00')),
        access: MoneyAccessController(),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('1,250')), findsNothing);
    handle.dispose();
  });

  testWidgets('unlocked shows the protected content and no lock surface', (
    tester,
  ) async {
    final access = MoneyAccessController();
    access.finishUnlock(access.beginUnlock());
    await tester.pumpWidget(
      _host(const MoneyLockGate(child: Text('GH₵ 1,250.00')), access: access),
    );
    expect(find.text('GH₵ 1,250.00'), findsOneWidget);
    expect(find.byType(LockedMoneySurface), findsNothing);
  });

  testWidgets('tapping the lock surface neither navigates nor throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MoneyLockGate(child: Text('GH₵ 1,250.00')),
        access: MoneyAccessController(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('locked-money-surface')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('GH₵ 1,250.00'), findsNothing);
  });

  testWidgets('reduced motion shakes not at all but still responds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MoneyLockGate(child: Text('GH₵ 1,250.00')),
        ),
        access: MoneyAccessController(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('locked-money-surface')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
