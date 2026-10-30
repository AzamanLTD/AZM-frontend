// The Home trigger is the unlock affordance while money is locked. The tap
// that unlocks must NOT also open the actions menu, and the menu itself must
// remain the untouched five-action launcher.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/widgets/az_logo_mark.dart';
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

    testWidgets('the logo plays its own animation after the lock opens', (
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

      // The three beats are distinct, in this order: the badge opens, and only
      // then does the Azaman logo fill (the access signal).
      double peakFill = 0;
      double opacityWhenFillStarted = -1;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final marks = tester.widgetList<AzLogoMark>(find.byType(AzLogoMark));
        if (marks.isEmpty) continue;
        final mark = marks.first;
        if (mark.fill3 > 0 && opacityWhenFillStarted < 0) {
          final fades = tester.widgetList<Opacity>(
            find.descendant(of: badge(), matching: find.byType(Opacity)),
          );
          opacityWhenFillStarted = fades.isEmpty ? 0 : fades.first.opacity;
        }
        peakFill = math.max(peakFill, mark.fill3);
      }

      expect(
        peakFill,
        greaterThan(0.9),
        reason: 'the Azaman logo must play its own fill animation on unlock',
      );
      expect(
        opacityWhenFillStarted,
        lessThan(0.2),
        reason: 'the lock must have finished opening before the logo plays',
      );
      expect(badge(), findsNothing, reason: 'the lock stays open afterwards');
      expect(
        controller.isOpen,
        isFalse,
        reason: 'the whole choreography resolves to the mark, not the menu',
      );
      final mark = tester.widgetList<AzLogoMark>(find.byType(AzLogoMark)).first;
      expect(
        mark.fill3,
        0,
        reason: 'it releases back to the idle mark once the animation ends',
      );
    });

    testWidgets('tapping the unlocked mark plays the same logo animation', (
      tester,
    ) async {
      // The member already unlocked earlier in the session, through the
      // controller's real API.
      final access = MoneyAccessController();
      access.finishUnlock(access.beginUnlock());
      final controller = PlusLauncherController();
      final coordinator = _FakeCoordinator(
        const MoneyUnlockResult(MoneyUnlockOutcome.unlocked),
      );

      await tester.pumpWidget(
        _host(controller: controller, access: access, coordinator: coordinator),
      );
      await tester.tap(find.byKey(const ValueKey('plus-launcher-trigger')));
      await tester.pump();

      double peakFill = 0;
      var openedAtFill = -1.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final marks = tester.widgetList<AzLogoMark>(find.byType(AzLogoMark));
        if (marks.isEmpty) continue;
        final fill = marks.first.fill3;
        if (controller.isOpen && openedAtFill < 0) openedAtFill = fill;
        if (!controller.isOpen) peakFill = math.max(peakFill, fill);
      }

      expect(
        peakFill,
        greaterThan(0.9),
        reason: 'the tap to open uses the logo own animation, as it always has',
      );
      expect(
        controller.isOpen,
        isTrue,
        reason: 'the menu still opens after the animation, unchanged',
      );
      expect(
        openedAtFill,
        greaterThan(0.9),
        reason: 'the menu opens only once the final segment has filled',
      );
      expect(
        coordinator.calls,
        0,
        reason: 'an unlocked tap must never re-prompt for authentication',
      );
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
