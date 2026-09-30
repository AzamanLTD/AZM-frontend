// =============================================================================
// NotificationBell — one-shot attention pop (milestone 2026-09-30) guards
//
// The old bell ran an infinite `.repeat(reverse: true)` pulse while unread
// > 0. The rule now, pinned by this suite:
//
//   * unread == 0          → no badge, no attention animation
//   * unread 0 → positive  → ONE pop, then settled at scale 1.0
//   * unread stays positive → no second pop on further increases
//                             (the badge count still updates)
//   * unread → 0            → badge gone
//   * a LATER 0 → positive  → fires a fresh pop (per-arrival signal)
//   * reduced motion        → no pop at all, badge appears settled
//
// Observable: the badge's Transform.scale — 1.35 at pop start, exactly 1.0
// at rest. A repeating animation would leave it away from 1.0 at almost any
// sample point after settle.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/widgets/notification_bell.dart';

/// Container-owned unread source: tests flip it mid-test to drive the
/// derived `unreadCountProvider` without touching the real notifier
/// (whose constructor fetches over the network).
final _fakeUnread = StateProvider<int>((ref) => 0);

Widget _host({bool reduceMotion = false}) {
  return ProviderScope(
    overrides: [
      unreadCountProvider.overrideWith((ref) => ref.watch(_fakeUnread)),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: Center(child: NotificationBell()),
      ),
    ),
  );
}

/// The badge's scale — 1.0 means settled/rested.
double _badgeScale(WidgetTester tester) {
  final transform = find.descendant(
    of: find.byType(NotificationBell),
    matching: find.byType(Transform),
  );
  final t = tester.widget<Transform>(transform.first).transform;
  // Uniform scale pop → the max axis scale is the badge scale.
  return t.getMaxScaleOnAxis();
}

Finder _badgeText(String text) => find.descendant(
      of: find.byType(NotificationBell),
      matching: find.text(text),
    );

void main() {
  testWidgets('unread 0 — no badge, no attention animation', (tester) async {
    await tester.pumpWidget(_host());
    // Clear the 300ms entrance fade so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.descendant(
      of: find.byType(NotificationBell),
      matching: find.byType(Transform),
    ), findsNothing);
    expect(_badgeText('0'), findsNothing);
  });

  testWidgets('0 → positive fires ONE pop then settles (no idle cycles)',
      (tester) async {
    await tester.pumpWidget(_host());
    // Clear the 300ms entrance fade so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));

    // 0 → 3.
    final element = tester.element(find.byType(NotificationBell));
    ProviderScope.containerOf(element, listen: false)
        .read(_fakeUnread.notifier)
        .state = 3;
    await tester.pump(); // rebuild with the badge
    await tester.pump(const Duration(milliseconds: 40));

    expect(_badgeText('3'), findsOneWidget);
    // Mid-pop: scale is away from rest (overshoot curve starts at 1.35).
    expect(_badgeScale(tester), isNot(moreOrLessEquals(1.0, epsilon: 0.01)));

    // After the pop duration: settled at exactly 1.0.
    await tester.pump(const Duration(milliseconds: 500));
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));

    // A long idle window at unread 3 — a repeating pulse would move the
    // scale at (at least one of) these sample points; one-shot does not.
    for (final d in [
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 700),
      const Duration(seconds: 1),
    ]) {
      await tester.pump(d);
      expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.001),
          reason: 'no idle animation cycles while unread stays at 3');
    }
  });

  testWidgets('staying positive never re-pops; count still updates',
      (tester) async {
    await tester.pumpWidget(_host());
    // Clear the 300ms entrance fade so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(NotificationBell)),
            listen: false);
    container.read(_fakeUnread.notifier).state = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // pop finished
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));

    // 2 → 5 while still unread: badge text updates but no new pop.
    container.read(_fakeUnread.notifier).state = 5;
    await tester.pump(); // rebuild with new count
    await tester.pump(const Duration(milliseconds: 40));
    expect(_badgeText('5'), findsOneWidget);
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.01),
        reason: 'an increase while already unread must not re-pop');

    // 150 unread: the badge caps at 99+, still settled.
    container.read(_fakeUnread.notifier).state = 150;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_badgeText('99+'), findsOneWidget);
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.01));

    // Back to 0: the badge disappears entirely.
    container.read(_fakeUnread.notifier).state = 0;
    await tester.pump();
    expect(find.descendant(
      of: find.byType(NotificationBell),
      matching: find.byType(Transform),
    ), findsNothing);
  });

  testWidgets('a later 0 → positive fires a fresh pop', (tester) async {
    await tester.pumpWidget(_host());
    // Clear the 300ms entrance fade so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(NotificationBell)),
            listen: false);

    // First arrival.
    container.read(_fakeUnread.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.001));

    // Read all, then a NEW arrival — per-arrival signal pops again.
    container.read(_fakeUnread.notifier).state = 0;
    await tester.pump();
    container.read(_fakeUnread.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_badgeScale(tester), isNot(moreOrLessEquals(1.0, epsilon: 0.01)),
        reason: 'each fresh 0 → positive transition signals once');
  });

  testWidgets('reduced motion: badge appears settled, no pop', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 400));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(NotificationBell)),
            listen: false);
    container.read(_fakeUnread.notifier).state = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(_badgeText('3'), findsOneWidget);
    expect(_badgeScale(tester), moreOrLessEquals(1.0, epsilon: 0.001),
        reason: 'reduced motion collapses the pop to zero duration');
  });
}
