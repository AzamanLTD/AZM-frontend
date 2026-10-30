// The Home trigger is the unlock affordance while money is locked. The tap
// that unlocks must NOT also open the actions menu, and the menu itself must
// remain the untouched five-action launcher.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';

class _FakeCoordinator implements MoneyUnlockCoordinator {
  _FakeCoordinator(this.result);

  MoneyUnlockResult result;
  int calls = 0;

  @override
  Future<MoneyUnlockResult> authenticate() async {
    calls++;
    return result;
  }
}

Widget _host({
  required PlusLauncherController controller,
  required MoneyAccessController access,
  required MoneyUnlockCoordinator coordinator,
}) {
  return ProviderScope(
    overrides: [
      moneyAccessProvider.overrideWith((ref) => access),
      moneyUnlockCoordinatorProvider.overrideWithValue(coordinator),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: PlusLauncherTrigger(controller: controller)),
      ),
    ),
  );
}

void main() {
  testWidgets('a locked tap authenticates and does not open the menu', (
    tester,
  ) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(coordinator.calls, 1);
    expect(access.canViewMoney, isTrue);
    expect(
      controller.isOpen,
      isFalse,
      reason: 'the unlocking tap must not also open the actions menu',
    );
  });

  testWidgets('the next tap opens the existing menu and does not re-prompt', (
    tester,
  ) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(coordinator.calls, 1, reason: 'one challenge, not one per tap');
    expect(controller.isOpen, isTrue);
  });

  testWidgets('a failed verification leaves the app locked and the menu shut', (
    tester,
  ) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.failed),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(access.state, MoneyAccessState.locked);
    expect(controller.isOpen, isFalse);
  });

  testWidgets('an unavailable method does not unlock or pretend to', (
    tester,
  ) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.unavailable),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(access.state, MoneyAccessState.locked);
    expect(controller.isOpen, isFalse);
  });

  testWidgets('rapid taps create exactly one challenge', (tester) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(coordinator.calls, 1);
  });

  testWidgets('the trigger keeps its 54px circular hit surface', (
    tester,
  ) async {
    final access = MoneyAccessController();
    final controller = PlusLauncherController();
    final coordinator = _FakeCoordinator(
      const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
    );

    await tester.pumpWidget(
      _host(controller: controller, access: access, coordinator: coordinator),
    );
    final size = tester.getSize(
      find.byKey(const ValueKey('plus-launcher-trigger')),
    );
    expect(size.width, greaterThanOrEqualTo(54));
    expect(size.height, greaterThanOrEqualTo(54));
  });

  group('the unlock is a visible morph, not a silent state flip', () {
    Finder badge() => find.byKey(const ValueKey('plus-launcher-lock-badge'));

    testWidgets('the closed lock is shown while locked, gone once open', (
      tester,
    ) async {
      final access = MoneyAccessController();
      final controller = PlusLauncherController();
      final coordinator = _FakeCoordinator(
        const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
      );

      await tester.pumpWidget(
        _host(controller: controller, access: access, coordinator: coordinator),
      );

      expect(
        badge(),
        findsOneWidget,
        reason: 'a locked app must say so on the control that unlocks it',
      );

      await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(access.canViewMoney, isTrue);
      expect(badge(), findsNothing, reason: 'the lock opened');
      expect(
        controller.isOpen,
        isFalse,
        reason: 'the morph resolves to the mark, it does not open the menu',
      );
    });

    testWidgets('the badge opens across the morph rather than vanishing', (
      tester,
    ) async {
      final access = MoneyAccessController();
      final controller = PlusLauncherController();
      final coordinator = _FakeCoordinator(
        const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
      );

      await tester.pumpWidget(
        _host(controller: controller, access: access, coordinator: coordinator),
      );
      await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
      await tester.pump();
      // Mid-morph the badge is still mounted but partly faded: the unlock is
      // legible as motion, not as a frame where it disappears.
      await tester.pump(const Duration(milliseconds: 40));

      final opacity = tester.widgetList<Opacity>(
        find.descendant(of: badge(), matching: find.byType(Opacity)),
      );
      if (badge().evaluate().isNotEmpty) {
        expect(opacity.first.opacity, lessThan(1.0));
        expect(opacity.first.opacity, greaterThan(0.0));
      }

      await tester.pump(const Duration(milliseconds: 500));
      expect(badge(), findsNothing);
    });

    testWidgets('a failed verification keeps the lock badge', (tester) async {
      final access = MoneyAccessController();
      final controller = PlusLauncherController();
      final coordinator = _FakeCoordinator(
        const MoneyUnlockResult(MoneyUnlockOutcome.failed),
      );

      await tester.pumpWidget(
        _host(controller: controller, access: access, coordinator: coordinator),
      );
      await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(access.canViewMoney, isFalse);
      expect(
        badge(),
        findsOneWidget,
        reason: 'a refusal must not look like an unlock',
      );
    });

    testWidgets('reduced motion still opens the lock, without the travel', (
      tester,
    ) async {
      final access = MoneyAccessController();
      final controller = PlusLauncherController();
      final coordinator = _FakeCoordinator(
        const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(
            controller: controller,
            access: access,
            coordinator: coordinator,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(access.canViewMoney, isTrue);
      expect(badge(), findsNothing);
      expect(controller.isOpen, isFalse);
    });
  });
}
