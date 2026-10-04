// =============================================================================
// UI-CORRECTION PHASE A — ODOMETER SLOT IDENTITY (2026-10-03)
//
// The odometer was rewritten from LEFT-index character comparison to SLOTS
// COUNTED FROM THE RIGHT. These tests pin the slot rules from the handoff:
//
//   • unchanged digit      → remains still;
//   • changed existing     → rolls;
//   • new slot             → rolls in from below;
//   • deleted slot         → the outgoing digit rolls out downward;
//   • separators           → static cells that FADE, never slide;
//   • inserting a grouping comma must NOT re-roll unchanged digits.
//
// The widget-level tests fail against the pre-fix implementation:
//   • the left-index odometer rendered only current.length cells, so a
//     deleted digit VANISHED instead of rolling out (no exit animation);
//   • inserting '9,990' from '999' re-rolled the '9' that the comma
//     displaced (5 mid-roll '9' cells vs the correct 4), and carried no
//     slot-keyed cells at all.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/odometer_number.dart';

/// Test host: pumps the odometer and lets a test move its value.
class _OdometerHost extends StatefulWidget {
  const _OdometerHost({this.initial = '0'});

  final String initial;

  @override
  State<_OdometerHost> createState() => _OdometerHostState();
}

class _OdometerHostState extends State<_OdometerHost> {
  late String _value = widget.initial;

  void set(String v) => setState(() => _value = v);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: OdometerNumber(
            value: _value,
            style: AzText.money(Colors.black, size: 40),
          ),
        ),
      ),
    );
  }
}

/// Everything the odometer renders, as a single text-finder.
Finder _odometerText(String ch) =>
    find.descendant(of: find.byType(OdometerNumber), matching: find.text(ch));

/// The cell that owns right-keyed slot N (the switcher carries this key).
Finder _slotCell(int slot) => find.byKey(ValueKey<String>('odometer-slot-$slot'));

void main() {
  // ── PURE SLOT PLAN (identity rules, no widgets) ──────────────────────────

  group('OdometerSlots.plan — slot identity from the right', () {
    test('typing a digit changes only what actually changed slots', () {
      final plan = OdometerSlots.plan('123', '12');
      // '12' → '123': slot0 '2'→'3' rolls, slot1 '1'→'2' rolls,
      // slot2 is the new '1' rolling in from below.
      expect(plan[0].kind, OdometerSlotKind.changedDigit);
      expect(plan[0].previousChar, '2');
      expect(plan[0].currentChar, '3');
      expect(plan[1].kind, OdometerSlotKind.changedDigit);
      expect(plan[2].kind, OdometerSlotKind.newDigit);
      expect(plan[2].previousChar, isNull);
    });

    test('comma insertion does not re-roll unchanged digits (999 → 9,990)',
        () {
      final plan = OdometerSlots.plan('9,990', '999');
      // The two '9's at slots 1 and 2 are UNCHANGED — they stay still.
      expect(plan[1].kind, OdometerSlotKind.unchanged);
      expect(plan[1].currentChar, '9');
      expect(plan[2].kind, OdometerSlotKind.unchanged);
      // The typed '0' rolls in at slot0; the comma fades in at slot3;
      // the new leftmost '9' rolls in at slot4.
      expect(plan[0].kind, OdometerSlotKind.changedDigit);
      expect(plan[3].kind, OdometerSlotKind.separatorFade);
      expect(plan[4].kind, OdometerSlotKind.newDigit);
    });

    test('crossing a thousands boundary keeps the zeros AND the comma '
        'still (1,000 → 10,000)', () {
      final plan = OdometerSlots.plan('10,000', '1,000');
      expect(plan[0].kind, OdometerSlotKind.unchanged); // 0
      expect(plan[1].kind, OdometerSlotKind.unchanged); // 0
      expect(plan[2].kind, OdometerSlotKind.unchanged); // 0
      // The thousands comma is ALWAYS slot 3 from the right — it does not
      // move at all. Only the '1' rolling to '0' and the new '1' roll.
      expect(plan[3].kind, OdometerSlotKind.unchanged); // ','
      expect(plan[3].currentChar, ',');
      expect(plan[4].kind, OdometerSlotKind.changedDigit); // '1' → '0'
      expect(plan[5].kind, OdometerSlotKind.newDigit); // '1'
    });

    test('backspace deletes from the RIGHT and flags emptied slots', () {
      final plan = OdometerSlots.plan('123', '1,234');
      // Slot 4 (the leftmost '1') is a DELETED digit — it must roll out
      // downward, not vanish.
      expect(plan[4].kind, OdometerSlotKind.deletedDigit);
      expect(plan[4].currentChar, isNull);
      // Slot 3 is the deleted thousands comma — separators fade out.
      expect(plan[3].kind, OdometerSlotKind.separatorFade);
      expect(plan[3].currentChar, isNull);
      // The remaining digits roll down: '4'→'3', '3'→'2', '2'→'1'.
      expect(plan[0].kind, OdometerSlotKind.changedDigit);
      expect(plan[1].kind, OdometerSlotKind.changedDigit);
      expect(plan[2].kind, OdometerSlotKind.changedDigit);
    });

    test('a separator trading places with a digit fades', () {
      final plan = OdometerSlots.plan('12', '12.');
      // '12.' → '12': the '.' slot becomes the digit '2' — fade grammar.
      expect(plan[0].kind, OdometerSlotKind.separatorFade);
      expect(plan[0].previousChar, '.');
      expect(plan[0].currentChar, '2');
    });

    test('a separator holds its slot while a digit beside it changes '
        '(12.50 → 12.55)', () {
      final plan = OdometerSlots.plan('12.55', '12.50');
      // The typed '5' rolls into slot0 ('0' → '5').
      expect(plan[0].kind, OdometerSlotKind.changedDigit);
      // The '.' keeps slot 2, the '2' keeps slot 3, the '1' keeps slot 4:
      // nothing but the changed digit moves.
      expect(plan[1].kind, OdometerSlotKind.unchanged);
      expect(plan[2].kind, OdometerSlotKind.unchanged);
      expect(plan[2].currentChar, '.');
      expect(plan[3].kind, OdometerSlotKind.unchanged);
      expect(plan[4].kind, OdometerSlotKind.unchanged);
    });
  });

  // ── WIDGET BEHAVIOUR (rolls, exits, stillness) ───────────────────────────

  group('OdometerNumber — slot rolls', () {
    testWidgets('a typed digit rolls: old and new are both on screen '
        'mid-roll', (tester) async {
      await tester.pumpWidget(const _OdometerHost(initial: '0'));
      final state = tester.state<_OdometerHostState>(find.byType(_OdometerHost));

      state.set('5');
      await tester.pump(const Duration(milliseconds: 80)); // mid-roll

      // Slot0 is switching '0' → '5': both glyphs coexist mid-roll.
      expect(_odometerText('0'), findsOneWidget);
      expect(_odometerText('5'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600)); // settle
      expect(_odometerText('5'), findsOneWidget);
      expect(_odometerText('0'), findsNothing);
    });

    testWidgets('backspace: the deleted digit rolls out downward '
        '(does not vanish)', (tester) async {
      await tester.pumpWidget(const _OdometerHost(initial: '12'));
      final state = tester.state<_OdometerHostState>(find.byType(_OdometerHost));
      await tester.pump(const Duration(milliseconds: 400));

      state.set('1');
      await tester.pump(const Duration(milliseconds: 100)); // mid-exit

      // Slot1's outgoing '1' is still on screen rolling out, and slot0 is
      // mid-roll '2'→'1'. The pre-fix implementation rendered only the
      // current string's cells — the '2' VANISHED on this frame instead of
      // rolling out.
      expect(_odometerText('2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600)); // settle
      expect(_odometerText('2'), findsNothing);
      expect(_odometerText('1'), findsOneWidget);
    });

    testWidgets('comma insertion keeps the unchanged digits still '
        '(999 → 9,990)', (tester) async {
      await tester.pumpWidget(const _OdometerHost(initial: '999'));
      final state = tester.state<_OdometerHostState>(find.byType(_OdometerHost));
      await tester.pump(const Duration(milliseconds: 400));

      state.set('9,990');
      await tester.pump(const Duration(milliseconds: 100)); // mid-roll

      // Slots 1 and 2 hold unchanged '9's: each renders EXACTLY ONE glyph
      // (no outgoing child — nothing is animating there). The pre-fix
      // odometer had no slot-keyed cells at all, so this finder missed.
      final stillOne = tester
          .widgetList<Text>(
            find.descendant(of: _slotCell(1), matching: find.text('9')),
          )
          .length;
      final stillTwo = tester
          .widgetList<Text>(
            find.descendant(of: _slotCell(2), matching: find.text('9')),
          )
          .length;
      expect(stillOne, 1);
      expect(stillTwo, 1);

      // Mid-roll the whole odometer shows exactly four '9' cells: the
      // outgoing '9' at slot0, the two still '9's, and the incoming '9' at
      // slot4. The pre-fix left-index odometer showed FIVE — it re-rolled
      // the displaced '9' as well (Expected<4> Actual<5> pre-fix).
      expect(_odometerText('9'), findsNWidgets(4));

      await tester.pump(const Duration(milliseconds: 600)); // settle
      // Final state: 9,990 — three '9's, one comma, one '0'.
      expect(_odometerText('9'), findsNWidgets(3));
      expect(_odometerText(','), findsOneWidget);
      expect(_odometerText('0'), findsOneWidget);
    });

    testWidgets('the acceptance sequence 1 → 12 → 123 → 1,234 → 12,345 '
        'rolls and never drops a glyph', (tester) async {
      await tester.pumpWidget(const _OdometerHost(initial: '1'));
      final state = tester.state<_OdometerHostState>(find.byType(_OdometerHost));
      await tester.pump(const Duration(milliseconds: 400));

      for (final v in ['12', '123', '1,234', '12,345']) {
        state.set(v);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));
      }
      // '12,345' settled: 1, 2, 3, 4, 5 + the comma.
      for (final ch in ['1', '2', '3', '4', '5', ',']) {
        expect(_odometerText(ch), findsOneWidget);
      }
    });

    testWidgets('reduced motion renders the value instantly, no switchers',
        (tester) async {
      // disableAnimations wraps MediaQuery for us.
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: _OdometerHost(initial: '0'),
        ),
      );
      final state = tester.state<_OdometerHostState>(find.byType(_OdometerHost));
      await tester.pump(const Duration(milliseconds: 400));

      state.set('500');
      await tester.pump(); // ONE frame — the new value must already be whole.
      expect(_odometerText('5'), findsOneWidget);
      expect(_odometerText('0'), findsNWidgets(2));
      // Reduced motion renders plain text — no switchers exist to animate.
      expect(
        find.descendant(
          of: find.byType(OdometerNumber),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
    });

    testWidgets('the amount width is animated (AnimatedSize present)',
        (tester) async {
      await tester.pumpWidget(const _OdometerHost(initial: '0'));
      expect(
        find.descendant(
          of: find.byType(OdometerNumber),
          matching: find.byType(AnimatedSize),
        ),
        findsOneWidget,
      );
    });
  });
}
