// AZAMAN — the two refusals a locked app can produce.
//
// 1. A refused money action shakes once per attempt and haptics, and still
//    reveals nothing. Reduced motion gets the haptic without the movement.
// 2. A changed identity (sign-out, or a different member) always relocks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/money_lock_blocked_feedback.dart';
import 'package:azaman/widgets/home/money_lock_lifecycle_guard.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => ProviderScope(
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('a refused action shakes, once per attempt', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _host(
        Consumer(
          builder: (context, ref, _) => MoneyLockShake(
            child: GestureDetector(
              onTap: () {
                attempts++;
                blockedMoneyAccessFeedback(ref);
              },
              child: const SizedBox(
                key: ValueKey('probe'),
                width: 200,
                height: 60,
                child: ColoredBox(color: Color(0xFF102030)),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('probe')));
    await tester.pump();

    expect(attempts, 1, reason: 'the tap must be refused, not swallowed');

    // The shake is real motion, not a state flag: sample mid-flight.
    await tester.pump(const Duration(milliseconds: 40));
    final moved = tester
        .widgetList<Transform>(find.byType(Transform))
        .where((t) => t.transform.getTranslation().x.abs() > 0.5)
        .length;
    expect(moved, greaterThan(0), reason: 'a refusal must be visible');

    // Settles back to rest.
    await tester.pump(const Duration(milliseconds: 400));
    final resting = tester
        .widgetList<Transform>(find.byType(Transform))
        .where((t) => t.transform.getTranslation().x.abs() > 0.5)
        .length;
    expect(resting, 0, reason: 'the shake must settle');
  });

  testWidgets('reduced motion refuses without moving', (tester) async {
    await tester.pumpWidget(
      _host(
        Consumer(
          builder: (context, ref, _) => MoneyLockShake(
            child: GestureDetector(
              onTap: () => blockedMoneyAccessFeedback(ref),
              child: const SizedBox(
                key: ValueKey('probe'),
                width: 200,
                height: 60,
                child: ColoredBox(color: Color(0xFF102030)),
              ),
            ),
          ),
        ),
        reduceMotion: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('probe')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final moved = tester
        .widgetList<Transform>(find.byType(Transform))
        .where((t) => t.transform.getTranslation().x.abs() > 0.5)
        .length;
    expect(moved, 0, reason: 'reduced motion: haptic only, no movement');
  });

  test('signing out and switching member both relock', () {
    // Same identity keeps the unlock.
    expect(identityChangeRequiresRelock('member-1', 'member-1'), isFalse);
    // Sign-out.
    expect(identityChangeRequiresRelock('member-1', 'out'), isTrue);
    // A different member on the same device.
    expect(identityChangeRequiresRelock('member-1', 'member-2'), isTrue);
    // First resolution of identity is not a change.
    expect(identityChangeRequiresRelock(null, 'member-1'), isFalse);
  });
}
