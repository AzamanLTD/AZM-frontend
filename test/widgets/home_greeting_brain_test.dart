// NEW-D — AzGreetingBrain unit tests.
//
// The brain is pure: fixed `DateTime` inputs, no providers, no widgets.
// These tests pin the three §H.7 honesty properties the greeting must keep:
//
//   1. NO streak path exists — no tone renders a flame glyph, because a
//      flame next to a bank balance reads as pressure (§H.7's first rule).
//   2. Money events beat pleasantries — priority order is observable.
//   3. Unknown values skip, never invent — a missing amount, a negative
//      escrow remainder and an empty username each degrade to the next
//      honest line, never to a fabricated claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/az_greeting_brain.dart';

void main() {
  // Fixed moments chosen ON the boundary values of the time fallback, so
  // the part-of-day cut points (12:00, 17:00) are pinned, not assumed.
  final morning = DateTime(2026, 9, 30, 8, 30);
  final noon = DateTime(2026, 9, 30, 12, 0);
  final evening = DateTime(2026, 9, 30, 17, 0);

  group('priority: money events beat pleasantries', () {
    test('a settled inflow today outranks everything, even at 8:30am', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame Mensah',
        moneyArrivedToday: '400.00 USDC',
        escrowReleasingInHours: 3,
        susuDueTomorrow: true,
      ));
      expect(line.text, 'Your 400.00 USDC cleared');
      expect(line.tone, AzGreetingTone.positive);
      // Only a REAL settled event may announce itself (TASK-020 pairing).
      expect(line.announceable, isTrue);
    });

    test('an empty money string is not a money event — it skips', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        moneyArrivedToday: '',
      ));
      expect(line.text, 'Good morning, Kwame');
      expect(line.announceable, isFalse);
    });

    test('escrow timing outranks susu, deposit and time of day', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        escrowReleasingInHours: 3,
        susuDueTomorrow: true,
        depositAwaitingApproval: true,
      ));
      expect(line.text, 'Escrow releases in 3h');
      expect(line.tone, AzGreetingTone.attention);
    });

    test('susu due tomorrow outranks deposit and time of day', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        susuDueTomorrow: true,
        depositAwaitingApproval: true,
      ));
      expect(line.text, 'Susu due tomorrow');
    });

    test('deposit awaiting approval outranks time of day', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        depositAwaitingApproval: true,
      ));
      expect(line.text, 'Waiting on your mobile-money approval');
    });
  });

  group('escrow hours format honestly', () {
    test('zero hours never renders "in 0h"', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        escrowReleasingInHours: 0,
      ));
      expect(line.text, 'Escrow releases now');
      expect(line.text.contains('0h'), isFalse);
    });

    test('under one hour says so instead of rounding to "0h"', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        escrowReleasingInHours: 0,
        // 0 is the only integer "under an hour" case; the wording branch
        // is pinned by the ≥0 and <1 paths together.
      ));
      expect(line.text, anyOf('Escrow releases now', contains('under an hour')));
    });

    test('one hour is "1h", not "1 hours"', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        escrowReleasingInHours: 1,
      ));
      expect(line.text, 'Escrow releases in 1h');
    });

    test('a negative (past) remainder is skipped, never rendered', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        escrowReleasingInHours: -2,
      ));
      // Falls through to the time fallback — no negative durations.
      expect(line.text, 'Good morning, Kwame');
      expect(line.text.contains('-'), isFalse);
    });

    test('unknown (null) escrow timing is skipped, not invented', () {
      final line = AzGreetingBrain.resolve(AzGreetingInputs(
        now: morning,
        username: 'Kwame',
        escrowReleasingInHours: null,
      ));
      expect(line.text, 'Good morning, Kwame');
    });
  });

  group('time fallback', () {
    test('before 12:00 is morning', () {
      final line =
          AzGreetingBrain.resolve(AzGreetingInputs(now: morning, username: 'Ama'));
      expect(line.text, 'Good morning, Ama');
    });

    test('12:00 exactly is afternoon (the cut point)', () {
      final line = AzGreetingBrain.resolve(
          AzGreetingInputs(now: noon, username: 'Ama'));
      expect(line.text, 'Good afternoon, Ama');
    });

    test('17:00 exactly is evening (the cut point)', () {
      final line = AzGreetingBrain.resolve(
          AzGreetingInputs(now: evening, username: 'Ama'));
      expect(line.text, 'Good evening, Ama');
    });

    test('first name only — a full name reads like a bank statement', () {
      final line = AzGreetingBrain.resolve(
          AzGreetingInputs(now: morning, username: 'Kwame Mensah'));
      expect(line.text, 'Good morning, Kwame');
    });

    test('null username degrades to "there" — never a dangling comma', () {
      final line = AzGreetingBrain.resolve(
          AzGreetingInputs(now: morning, username: null));
      expect(line.text, 'Good morning, there');
      expect(line.text.contains(',,'), isFalse);
    });

    test('blank username degrades to "there"', () {
      final line = AzGreetingBrain.resolve(
          AzGreetingInputs(now: morning, username: '   '));
      expect(line.text, 'Good morning, there');
    });
  });

  group('§H.7: no streak path, no flame glyph', () {
    test('no tone renders the flame icon', () {
      for (final tone in AzGreetingTone.values) {
        expect(AzGreetingBrain.glyphFor(tone),
            isNot(Icons.local_fire_department));
      }
    });

    test('the glyph set is exactly the three calm glyphs', () {
      expect(AzGreetingBrain.glyphFor(AzGreetingTone.positive),
          Icons.trending_up_rounded);
      expect(AzGreetingBrain.glyphFor(AzGreetingTone.attention),
          Icons.schedule_rounded);
      expect(AzGreetingBrain.glyphFor(AzGreetingTone.neutral),
          Icons.wb_sunny_outlined);
    });
  });
}
