// test/data/demo_seed_susu_contract_test.dart
// -----------------------------------------------------------------------------
// The demo Susu must be ONE Susu. Every route that serves it — the
// /susu/me summary, the Phase-4 detail, the member roster, the cycle
// schedule and the group-chat status payload — has to agree on the
// roster, the slots, the cycle position and the payout order. A demo that
// contradicts itself trains the eye to distrust the real thing.
//
// These tests parse the seed through the SAME factories the app parses
// real payloads with, then cross-check the fixture surfaces against each
// other. If any endpoint's shape drifts away from the others, this suite
// fails before the demo ever ships a contradiction.
// -----------------------------------------------------------------------------

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/widgets/susu/susu_wheel.dart';

void main() {
  group('demo susu fixtures — one susu, every route', () {
    final detail = SusuDetail.fromJson(DemoSeedData.susuDetail());
    final members = DemoSeedData.susuMembers()
        .map(SusuMemberView.fromJson)
        .toList();
    final cycles = DemoSeedData.susuCycles()
        .map(SusuCycleView.fromJson)
        .toList();
    final summary = (DemoSeedData.susuGroups()['data'] as List)
        .cast<Map<String, dynamic>>()
        .single;

    test('the detail parses as an ACTIVE weekly susu of 4 cycles', () {
      expect(detail.id, 'susu-1');
      expect(detail.status, SusuStatus.active);
      expect(detail.frequency, SusuFrequency.weekly);
      expect(detail.totalCycles, 4);
      expect(detail.contributionUsdc, 200.0);
    });

    test('four active members hold the four distinct slots exactly once', () {
      expect(members.length, 4);
      expect(members.every((m) => m.status == SusuMemberStatus.active), isTrue);
      final slots = members.map((m) => m.cycleSlot).toList()..sort();
      expect(slots, [1, 2, 3, 4]);
    });

    test('the cycle schedule is complete, ordered and honest', () {
      expect(cycles.map((c) => c.cycleNumber), [1, 2, 3, 4]);
      for (var i = 1; i < cycles.length; i++) {
        expect(
          cycles[i].scheduledRunAt.isAfter(cycles[i - 1].scheduledRunAt),
          isTrue,
        );
      }
      // Cycle 1 is the only paid one; 2 collects; 3 and 4 wait.
      expect(cycles[0].status, SusuCycleStatus.paidOut);
      expect(cycles[0].paidOutAt, isNotNull);
      expect(cycles[1].status, SusuCycleStatus.collecting);
      expect(cycles[2].status, SusuCycleStatus.pending);
      expect(cycles[3].status, SusuCycleStatus.pending);
    });

    test('every cycle pays a member who actually holds that slot', () {
      final bySlot = {for (final m in members) m.cycleSlot!: m};
      for (final c in cycles) {
        final payee = bySlot[c.cycleNumber];
        expect(
          payee,
          isNotNull,
          reason: 'cycle ${c.cycleNumber} pays an unslotted member',
        );
        expect(
          payee!.userId,
          c.payoutUserId,
          reason: 'cycle ${c.cycleNumber} pays the wrong member',
        );
      }
    });

    test('the summary agrees with the detail it summarises', () {
      expect(summary['memberCount'], members.length);
      expect(summary['totalCycles'], detail.totalCycles);
      expect(summary['status'], detail.status.wire);
      expect(summary['name'], detail.name);
      // cycle 2 of 4 = the first non-terminal cycle.
      final upcoming = cycles.firstWhere(
        (c) =>
            c.status != SusuCycleStatus.paidOut &&
            c.status != SusuCycleStatus.defaulted,
      );
      expect(upcoming.cycleNumber, summary['cycle']);
      // "next payout: Lamar" must be the member the upcoming cycle pays.
      final payee = members.singleWhere(
        (m) => m.userId == upcoming.payoutUserId,
      );
      expect(payee.displayName, summary['nextPayoutUser']);
    });

    test("the summary's next payout date matches the schedule", () {
      final upcoming = cycles[1];
      final summaryDate = DateTime.parse(summary['nextPayoutDate'] as String);
      expect(
        summaryDate.difference(upcoming.scheduledRunAt).abs(),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('the group-chat status payload parses and opens the same susu', () {
      final status = SusuInitiationStatus.fromJson(
        DemoSeedData.susuGroupStatus(),
      );
      expect(status.isActive, isTrue);
      expect(status.susuGroupId, detail.id);
      expect(status.memberCount, members.length);
      expect(status.totalCycles, detail.totalCycles);
      expect(status.contributionUsdc, detail.contributionUsdc);
      expect(status.frequency, detail.frequency.wire);
    });

    test('the wheel arc sweeps a live, honest fraction right now', () {
      final sweep = susuArcSweep(
        cycles[0].scheduledRunAt,
        cycles[1].scheduledRunAt,
        DateTime.now(),
      );
      // A weekly cadence with cycle 2 paying out in 7 days: the window
      // is 14 days wide and centred on now, so the arc sits near half.
      expect(sweep, greaterThan(0.45));
      expect(sweep, lessThan(0.55));
    });

    test('the susu roster is the susu group chat roster (grp-2)', () {
      final grp2 = DemoSeedData.groupChats().singleWhere(
        (g) => g['id'] == 'grp-2',
      );
      final roster = (grp2['members'] as List)
          .map((m) => (m as Map<String, dynamic>)['userId'] as int)
          .toSet();
      expect({for (final m in members) m.userId}, roster);
    });
  });
}
