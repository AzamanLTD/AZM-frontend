// test/susu_wheel_test.dart
// -----------------------------------------------------------------------------
// Susu wheel — the invariant is NOT "the slots are drawn in a circle". It is:
//   * pure geometry that is honest about degenerate input (0 slots, null windows,
//     fully-taken wheels, repeated rounds);
//   * a dash that advances monotonically and clamps to [0,1];
//   * two different cycle statuses, distinguished by the widget itself;
//   * a drag that ends on a FREE slot and a taken slot that never fires.
// -----------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/widgets/susu/susu_wheel.dart';

void main() {
  group('susuSlotAngle', () {
    test('slot 1 is at 12 o\'clock and the rest advance clockwise', () {
      expect(susuSlotAngle(1, 4), closeTo(-math.pi / 2, 1e-9));
      expect(susuSlotAngle(2, 4), closeTo(0.0, 1e-9));
      expect(susuSlotAngle(3, 4), closeTo(math.pi / 2, 1e-9));
      expect(susuSlotAngle(4, 4), closeTo(math.pi, 1e-9));
    });

    test('a single slot sits exactly at the top', () {
      expect(susuSlotAngle(1, 1), closeTo(-math.pi / 2, 1e-9));
    });

    test('degenerate total does not divide by zero', () {
      expect(susuSlotAngle(1, 0).isFinite, isTrue);
      expect(susuSlotAngle(1, -3).isFinite, isTrue);
    });
  });

  group('susuRotationSlot', () {
    test('maps rotation back onto a slot', () {
      expect(susuRotationSlot(0, 4), 1);
      expect(susuRotationSlot(-math.pi / 2, 4), 2);
      expect(susuRotationSlot(-math.pi, 4), 3);
      expect(susuRotationSlot(math.pi / 2, 4), 4);
    });

    test('wraps through several full rounds', () {
      expect(susuRotationSlot(-4 * math.pi, 4), 1);
      // A full extra round is the same physical position, so the slot is
      // unchanged: -5pi/2 is congruent to -pi/2, which puts slot 2 on top.
      expect(susuRotationSlot(-(5 * math.pi / 2), 4), 2);
    });

    test('degenerate total does not divide by zero', () {
      expect(susuRotationSlot(1.0, 0), inInclusiveRange(1, 1));
    });
  });

  group('susuSnapRotation', () {
    test('finds the shortest-path rotation onto a slot', () {
      expect(susuSnapRotation(0, 1, 4), closeTo(0, 1e-9));
      expect(susuSnapRotation(0, 4, 4), closeTo(math.pi / 2, 1e-9));
      expect(susuSnapRotation(0.1, 1, 4), closeTo(0, 1e-9));
      // From near slot 2, rotating onto slot 1 goes the short way (backwards).
      expect(susuSnapRotation(math.pi / 2 - 0.1, 1, 4), closeTo(0, 1e-9));
    });
  });

  group('susuNearestFreeSlot', () {
    test('picks the closest free slot', () {
      final n = susuNearestFreeSlot(0, 4, {});
      expect(n, isNotNull);
      expect(n!.slot, 1);
      expect(n.delta, closeTo(0, 1e-9));
      expect(susuNearestFreeSlot(math.pi / 2, 4, {})!.slot, 4);
      expect(susuNearestFreeSlot(0, 4, {1, 4})!.slot, 2); // skips taken
    });

    test('returns null when nothing is free or total is degenerate', () {
      expect(susuNearestFreeSlot(0, 4, {1, 2, 3, 4}), isNull);
      expect(susuNearestFreeSlot(0, 0, {}), isNull);
    });
  });

  group('susuArcSweep', () {
    test('window honesty', () {
      final t = DateTime.utc(2026, 6, 21, 12);
      final end = t.add(const Duration(hours: 4));
      expect(susuArcSweep(null, end, t), 0.0);
      expect(susuArcSweep(t, null, t), 0.0);
      expect(susuArcSweep(t, t, t), 0.0);
      expect(susuArcSweep(end, t, t), 0.0); // degenerate window
      expect(susuArcSweep(t, end, t.subtract(const Duration(minutes: 1))), 0.0);
      expect(
          susuArcSweep(t, end, t.add(const Duration(hours: 2))), closeTo(0.5, 1e-9));
      expect(susuArcSweep(t, end, end.add(const Duration(minutes: 1))), 1.0);
    });
  });

  group('susuStableSeed', () {
    test('F-046: deterministic fold, not String.hashCode', () {
      expect(susuStableSeed('abc'), 304891);
      expect(susuStableSeed(''), 7);
      expect(susuStableSeed('abc'), susuStableSeed('abc'));
      expect(susuStableSeed('abc'), isNot(susuStableSeed('abd')));
    });
  });

  group('susuAvatarHue', () {
    test('stays in range and is stable', () {
      final h = susuAvatarHue('Ama');
      expect(h, inInclusiveRange(0, 359.999));
      expect(h, susuAvatarHue('Ama'));
    });
  });

  group('susuCountdownLabel', () {
    test('countdown formatting', () {
      final now = DateTime.utc(2026, 6, 21, 12);
      expect(susuCountdownLabel(null, now), '');
      expect(
          susuCountdownLabel(now.subtract(const Duration(seconds: 5)), now),
          'Due now');
      expect(susuCountdownLabel(now.add(const Duration(days: 3, hours: 2)), now),
          '3d 2h');
      expect(susuCountdownLabel(now.add(const Duration(hours: 2, minutes: 14)), now),
          '2h 14m');
      expect(susuCountdownLabel(now.add(const Duration(minutes: 4)), now), '4m');
      expect(susuCountdownLabel(now.add(const Duration(seconds: 30)), now), '<1m');
    });
  });

  group('SusuWheel', () {
    testWidgets('renders the canvas and rings the upcoming slot', (tester) async {
      await tester.pumpWidget(host(wheel(members: members(), cycles: cycles())));
      expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('susu-wheel-next-dot')), findsOneWidget);
      expect(find.byKey(const ValueKey('susu-wheel-center-label')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100)); // bounded: ticker runs
    });

    testWidgets('marks the caller slot with YOU', (tester) async {
      await tester.pumpWidget(
          host(wheel(members: members(), cycles: cycles(), meUserId: 10)));
      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('center label names the upcoming slot', (tester) async {
      await tester.pumpWidget(host(wheel(members: members(), cycles: cycles())));
      expect(find.textContaining('slot 2'), findsOneWidget);
    });

    testWidgets('terminal cycles show Done and the ticker stops', (tester) async {
      final t = DateTime.utc(2026, 6, 21, 12);
      final done = [
        SusuCycleView(
          id: 'c1',
          cycleNumber: 1,
          scheduledRunAt: t,
          status: SusuCycleStatus.paidOut,
          payoutUserId: 10,
          paidOutAt: t,
          escrowDivertedAt: null,
          payoutAmount: 100,
        ),
      ];
      await tester.pumpWidget(host(wheel(members: members(), cycles: done)));
      await tester.pumpAndSettle(); // safe: ticker never started
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('reduced motion never starts the ticker', (tester) async {
      await tester.pumpWidget(
          host(wheel(members: members(), cycles: cycles()), reduced: true));
      await tester.pumpAndSettle(); // would hang if the repeater were running
      expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsOneWidget);
    });

    testWidgets('members without a slot do not crash the wheel', (tester) async {
      const unslotted = [
        SusuMemberView(
          susuMemberId: 'm9',
          userId: 90,
          displayName: 'Kofi',
          avatar: null,
          cycleSlot: null,
          status: SusuMemberStatus.active,
          role: 'MEMBER',
        ),
      ];
      await tester.pumpWidget(host(wheel(members: unslotted, cycles: cycles())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsOneWidget);
    });

    testWidgets('an empty wheel renders without data', (tester) async {
      await tester.pumpWidget(host(wheel()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsOneWidget);
    });
  });

  group('SusuPositionWheel', () {
    testWidgets('tap selects the slot and the hub confirms it', (tester) async {
      final picks = <int>[];
      await tester.pumpWidget(host(pickerWheel(
        totalPositions: 4,
        members: const [
          {'position': 1, 'username': 'Ama'},
        ],
        onPositionSelected: picks.add,
      )));
      await tester.tap(find.byKey(const ValueKey('susu-position-slot-3')));
      await tester.pumpAndSettle(); // one-shot spring completes
      expect(picks, [3]);
      expect(find.text('Pick slot 3'), findsOneWidget);
    });

    testWidgets('taken slots stay inert', (tester) async {
      final picks = <int>[];
      await tester.pumpWidget(host(pickerWheel(
        totalPositions: 4,
        members: const [
          {'position': 1, 'username': 'Ama'},
        ],
        onPositionSelected: picks.add,
      )));
      await tester.tap(find.byKey(const ValueKey('susu-position-slot-1')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(picks, isEmpty);
    });

    testWidgets('drag springs to the nearest free slot and the hub commits',
        (tester) async {
      final picks = <int>[];
      await tester.pumpWidget(host(pickerWheel(
        totalPositions: 4,
        members: const [
          {'position': 1, 'username': 'Ama'},
        ],
        onPositionSelected: picks.add,
      )));
      await tester.drag(
          find.byKey(const ValueKey('susu-position-wheel')), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Pick slot 4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('susu-position-hub')));
      await tester.pumpAndSettle();
      expect(picks, [4]);
    });

    testWidgets('reduced motion selects instantly', (tester) async {
      final picks = <int>[];
      await tester.pumpWidget(host(pickerWheel(
        totalPositions: 4,
        onPositionSelected: picks.add,
      ), reduced: true));
      await tester.tap(find.byKey(const ValueKey('susu-position-slot-2')));
      await tester.pumpAndSettle();
      expect(picks, [2]);
    });
  });
}

// ── Fixtures and hosts ────────────────────────────────────────────────────────

List<SusuMemberView> members() => const [
      SusuMemberView(
        susuMemberId: 'm1',
        userId: 10,
        displayName: 'Ama',
        avatar: null,
        cycleSlot: 1,
        status: SusuMemberStatus.active,
        role: 'MEMBER',
      ),
      SusuMemberView(
        susuMemberId: 'm2',
        userId: 20,
        displayName: 'Kojo',
        avatar: null,
        cycleSlot: 2,
        status: SusuMemberStatus.active,
        role: 'MEMBER',
      ),
      SusuMemberView(
        susuMemberId: 'm3',
        userId: 30,
        displayName: 'Esi',
        avatar: null,
        cycleSlot: 3,
        status: SusuMemberStatus.active,
        role: 'ADMIN',
      ),
    ];

List<SusuCycleView> cycles() {
  final t = DateTime.utc(2026, 6, 21, 12);
  return [
    SusuCycleView(
      id: 'c1',
      cycleNumber: 1,
      scheduledRunAt: t.subtract(const Duration(days: 7)),
      status: SusuCycleStatus.paidOut,
      payoutUserId: 10,
      paidOutAt: t.subtract(const Duration(days: 6)),
      escrowDivertedAt: null,
      payoutAmount: 100,
    ),
    SusuCycleView(
      id: 'c2',
      cycleNumber: 2,
      scheduledRunAt: t.add(const Duration(days: 3)),
      status: SusuCycleStatus.pending,
      payoutUserId: 20,
      paidOutAt: null,
      escrowDivertedAt: null,
      payoutAmount: null,
    ),
    SusuCycleView(
      id: 'c3',
      cycleNumber: 3,
      scheduledRunAt: t.add(const Duration(days: 10)),
      status: SusuCycleStatus.pending,
      payoutUserId: 30,
      paidOutAt: null,
      escrowDivertedAt: null,
      payoutAmount: null,
    ),
  ];
}

Widget host(Widget child, {bool reduced = false}) {
  final body = Center(child: SizedBox(width: 380, child: child));
  return ProviderScope(
    child: MaterialApp(
      home: reduced
          ? MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(body: body),
            )
          : Scaffold(body: body),
    ),
  );
}

Widget wheel({
  List<SusuMemberView>? members,
  List<SusuCycleView>? cycles,
  int totalSlots = 5,
  dynamic meUserId,
}) {
  return SusuWheel(
    members: members ?? [],
    cycles: cycles ?? [],
    totalSlots: totalSlots,
    meUserId: meUserId,
  );
}

Widget pickerWheel({
  int totalPositions = 4,
  int? selectedPosition,
  List<Map<String, dynamic>> members = const [],
  required ValueChanged<int> onPositionSelected,
}) {
  return SusuPositionWheel(
    totalPositions: totalPositions,
    selectedPosition: selectedPosition,
    members: members,
    onPositionSelected: onPositionSelected,
  );
}
