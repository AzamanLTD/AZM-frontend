// test/widgets/odometer_transition_identity_test.dart
// -----------------------------------------------------------------------------
// OdometerNumber — TRANSITION IDENTITY (UI-correction Phase A review patch).
//
// The pure planner (what each slot must do) is pinned in
// odometer_slot_identity_test.dart. These tests pin different invariants:
// an entry's transition SEMANTICS are frozen when the child ENTERS and can
// never be mutated by a later build — and a DELETED digit always rolls
// DOWN out of the slot.
//
//   * a digit that rolled in from below must exit moving downward — even if
//     a rapid second update plans the same slot in the opposite direction;
//   * an unrelated rebuild (same value, new widget instance) must not
//     rewrite an in-flight slide into a fade;
//   * a deleted digit must roll DOWN out of its slot — measured by the
//     actual SlideTransition geometry (positive dy, growing), not merely
//     by the old digit remaining visible mid-transition — whether it was
//     created at mount (would otherwise fade) or entered from above
//     (would otherwise reverse upward), and a deletion exit in flight
//     keeps rolling downward across a rapid retype into the same slot;
//   * under reduced motion the whole figure — including the outer width
//     animation — must reach its final geometry on the FIRST frame.
//
// These reproduce IN-FLIGHT transitions and then rebuild/update mid-roll,
// which is exactly where a per-build transitionBuilder closure breaks: a
// new closure identity on every build lets AnimatedSwitcher re-wrap live
// entries with the CURRENT plan's semantics. The frozen semantics and the
// deletion exit are both carried by STABLE STATE TEAR-OFF builders (see
// `_slotTransition` / `_deletedSlotTransition` in odometer_number.dart).
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/odometer_number.dart';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Hosts the widget with a real MediaQuery inside MaterialApp, because the
/// widget reads `MediaQuery.disableAnimationsOf(context)`.
Widget _host(String value, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Center(
        child: OdometerNumber(value: value, style: _tabular),
      ),
    ),
  );
}

/// The SlideTransition wrapping [text] INSIDE the odometer. Scoped to the
/// odometer's subtree: the material page route's own transition slide (and
/// its framework ancestors) must never be picked up.
Finder _slideOf(String text) => find.descendant(
      of: find.byType(OdometerNumber),
      matching: find.ancestor(
        of: find.text(text),
        matching: find.byType(SlideTransition),
      ),
    );

void main() {
  group('transition identity across rapid updates', () {
    testWidgets(
      'an in-flight outgoing digit exits with the direction it entered with, '
      'not the rapid second update\'s plan',
      (tester) async {
        await tester.pumpWidget(_host('12'));
        await tester.pumpAndSettle();

        // First update: slot 0 '2' → '5'. 5 > 2, so the '5' rolls UP —
        // it enters sliding from BELOW (begin offset +1).
        await tester.pumpWidget(_host('15'));
        await tester.pump(const Duration(milliseconds: 40)); // in flight

        // Rapid second update while the first roll is mid-flight: slot 0
        // '5' → '0'. The NEW plan says "rolls DOWN — enter from above"
        // (begin offset -1). The outgoing '5' must NOT inherit that: it
        // entered from below, so its exit reverses its OWN entry and it
        // leaves travelling DOWN (positive dy, growing toward +1).
        await tester.pumpWidget(_host('10'));
        await tester.pump(); // one frame, ZERO elapsed time

        final slide = _slideOf('5');
        expect(slide, findsOneWidget);
        final dy0 =
            tester.widget<SlideTransition>(slide.first).position.value.dy;

        // Buggy builder: the outgoing '5' is re-wrapped with the new plan's
        // sign (-1) at the SAME animation value — dy0 flips negative
        // immediately. Correct: dy0 stays positive (mid-exit, travelling
        // down toward +1) and strictly inside the roll, not snapped.
        expect(dy0, greaterThan(0.0));
        expect(dy0, lessThan(1.0));

        // The exit completes downward (the digit departs, it is not left
        // hanging): once settled, the outgoing digit is gone from the tree
        // and the figure shows exactly the new value.
        await tester.pumpAndSettle();
        expect(
          find.descendant(
              of: find.byType(OdometerNumber), matching: find.text('5')),
          findsNothing,
        );
        expect(find.text('0'), findsOneWidget);
      },
    );

    // NOTE: a same-value rebuild recomputes an IDENTICAL plan (the plan is a
    // pure function of the value and the previous value, and neither changes),
    // so pre-fix this scenario happened to be a visual no-op — it is an
    // INVARIANT PIN for the stable-builder architecture, not a pre-fix
    // discriminator. The observable pre-fix failure (proven above) is the
    // rapid second UPDATE case, where the new plan's semantics differ from
    // the in-flight entry's own.
    testWidgets(
      'an unrelated rebuild cannot rewrite an in-flight slide into a fade',
      (tester) async {
        await tester.pumpWidget(_host('12'));
        await tester.pumpAndSettle();

        // '2' → '5': the incoming '5' is mid-roll, sliding in from below.
        await tester.pumpWidget(_host('15'));
        await tester.pump(const Duration(milliseconds: 40)); // in flight

        // An UNRELATED rebuild: the SAME value mounted again (a parent
        // rebuilt for any reason). The value did not change, so no slot
        // planned any motion — but the incoming '5' entry is still alive
        // and must keep finishing ITS OWN slide. A re-wrapped entry would
        // have no SlideTransition at all (it would become a fade).
        await tester.pumpWidget(_host('15'));
        await tester.pump(const Duration(milliseconds: 40));

        final slide = _slideOf('5');
        expect(slide, findsOneWidget);
        final dy =
            tester.widget<SlideTransition>(slide.first).position.value.dy;
        // Still on its entry path from below (0 = arrived, 1 = below).
        expect(dy, greaterThan(0.0));
        expect(dy, lessThan(1.0));

        await tester.pumpAndSettle();
        // The roll finished at rest: the digit arrived at its final spot.
        expect(_slideOf('5'), findsOneWidget);
        expect(
          tester.widget<SlideTransition>(_slideOf('5').first).position.value,
          Offset.zero,
        );
      },
    );
  });

  group('deleted digits roll DOWN out of the slot', () {
    testWidgets(
      'a settled mount-created digit deleted by a backspace slides '
      'downward, not a fade',
      (tester) async {
        await tester.pumpWidget(_host('15'));
        await tester.pumpAndSettle();

        // Backspace: '15' → '5' deletes slot 1's '1'. That digit was
        // created at mount — it never slid, its baked entry transition
        // is a fade — so under frozen-entry semantics alone its exit
        // would be a FADE (it would just vanish). The deletion exit must
        // instead roll it DOWN: mid-transition the digit sits inside a
        // real SlideTransition with positive, growing dy.
        await tester.pumpWidget(_host('5'));
        await tester.pump(const Duration(milliseconds: 40)); // mid-exit

        expect(_slideOf('1'), findsOneWidget);
        final dy = tester
            .widget<SlideTransition>(_slideOf('1').first)
            .position
            .value
            .dy;
        // Geometry, not visibility: travelling downward through the slot.
        expect(dy, greaterThan(0.0));
        expect(dy, lessThan(1.0));
        // And it is not a fade: no FadeTransition wraps the outgoing
        // digit inside the odometer.
        expect(
          find.descendant(
            of: find.byType(OdometerNumber),
            matching: find.ancestor(
              of: find.text('1'),
              matching: find.byType(FadeTransition),
            ),
          ),
          findsNothing,
        );

        // The roll completes: the digit departs and the figure shows
        // exactly the new value.
        await tester.pumpAndSettle();
        expect(
          find.descendant(
              of: find.byType(OdometerNumber), matching: find.text('1')),
          findsNothing,
        );
        expect(find.text('5'), findsOneWidget);
      },
    );

    testWidgets(
      'a deleted digit rolls downward even when it entered from above',
      (tester) async {
        await tester.pumpWidget(_host('96'));
        await tester.pumpAndSettle();

        // '96' → '16': slot 1 '9' → '1' rolls DOWN, so the '1' ENTERS
        // FROM ABOVE (begin offset -1). Let it settle: its baked entry
        // transition now says slide-from-above.
        await tester.pumpWidget(_host('16'));
        await tester.pumpAndSettle();

        // Backspace: '16' → '6' deletes slot 1's '1'. Reversing its own
        // entry would send it OUT UPWARD (negative dy). The deletion
        // exit must override that and roll DOWN.
        await tester.pumpWidget(_host('6'));
        await tester.pump(const Duration(milliseconds: 40)); // mid-exit

        expect(_slideOf('1'), findsOneWidget);
        final dy = tester
            .widget<SlideTransition>(_slideOf('1').first)
            .position
            .value
            .dy;
        expect(dy, greaterThan(0.0));
        expect(dy, lessThan(1.0));

        await tester.pumpAndSettle();
        expect(
          find.descendant(
              of: find.byType(OdometerNumber), matching: find.text('1')),
          findsNothing,
        );
        expect(find.text('6'), findsOneWidget);
      },
    );

    testWidgets(
      'a deletion exit keeps rolling downward across a rapid retype',
      (tester) async {
        await tester.pumpWidget(_host('15'));
        await tester.pumpAndSettle();

        // Backspace, then — before the exit settles — retype a digit
        // into the SAME slot. The slot's plan moves on (newDigit) and
        // the slot's builder flips back; the in-flight deletion exit
        // must NOT be re-wrapped into anything else: it keeps sliding
        // DOWN, monotonic, never a fade.
        await tester.pumpWidget(_host('5'));
        await tester.pump(const Duration(milliseconds: 40)); // mid-exit

        expect(_slideOf('1'), findsOneWidget);
        final dy0 = tester
            .widget<SlideTransition>(_slideOf('1').first)
            .position
            .value
            .dy;
        expect(dy0, greaterThan(0.0));

        await tester.pumpWidget(_host('75'));
        await tester.pump(const Duration(milliseconds: 40)); // still exiting

        expect(_slideOf('1'), findsOneWidget);
        final dy1 = tester
            .widget<SlideTransition>(_slideOf('1').first)
            .position
            .value
            .dy;
        // Continued downward — the retype did not mutate the exit's
        // direction, and did not turn it into a fade.
        expect(dy1, greaterThan(dy0));
        expect(dy1, lessThan(1.0));

        await tester.pumpAndSettle();
        expect(
          find.descendant(
              of: find.byType(OdometerNumber), matching: find.text('1')),
          findsNothing,
        );
        // The retyped digit arrived at the vacated slot.
        expect(find.text('7'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
      },
    );
  });

  group('reduced motion — final geometry on the first frame', () {
    testWidgets(
      'a slot-count change reaches the final width immediately '
      '(no width animation under disableAnimations)',
      (tester) async {
        // Reference: the fully-settled geometry of the longer figure,
        // measured on its own mount (a mount never animates).
        await tester.pumpWidget(_host('9,999', disableAnimations: true));
        await tester.pumpAndSettle();
        final reference = tester.getSize(find.byType(OdometerNumber));

        // Start from the shorter figure, then grow it: '99' → '9,999'
        // adds a separator and two slots, so the figure wants a much
        // wider layout.
        await tester.pumpWidget(_host('99', disableAnimations: true));
        await tester.pumpAndSettle();
        final before = tester.getSize(find.byType(OdometerNumber));
        expect(before.width, lessThan(reference.width));

        await tester.pumpWidget(_host('9,999', disableAnimations: true));
        // Exactly one frame of elapsed time — NO settling. If the outer
        // width still animated under reduced motion, the geometry would
        // still be at the OLD size here, lagging the content by up to one
        // full animation duration.
        await tester.pump(const Duration(milliseconds: 1));

        final after = tester.getSize(find.byType(OdometerNumber));
        expect(after.width, reference.width);
        expect(after.height, reference.height);
      },
    );
  });
}
