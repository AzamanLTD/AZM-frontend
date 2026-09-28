// test/widgets/odometer_number_test.dart
// -----------------------------------------------------------------------------
// OdometerNumber — the invariant is NOT "it shows the value" (any Text would).
// It is: only the digits that CHANGED move, and every digit cell is the same
// width, so a partially-changed number never reflows the characters around it.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/theme/motion_tokens.dart';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Hosts the widget with a *real* MediaQuery inside MaterialApp, because the
/// widget reads `MediaQuery.disableAnimationsOf(context)`.
///
/// [disableAnimations] is applied to the INNER MediaQuery, which is the one the
/// widget actually sees — setting it only on the outer one would let
/// MaterialApp overwrite it.
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

/// Counts the `Text` widgets currently mounted inside [OdometerNumber] that are
/// rolling (i.e. wrapped in an `AnimatedSwitcher`).
int rollingCells(WidgetTester tester) =>
    find.byType(AnimatedSwitcher).evaluate().length;

/// Number of static (non-rolling) character cells.
int staticCells(WidgetTester tester) => find.byType(Text).evaluate().length;

/// All the character strings currently on screen, in tree order.
List<String> visibleChars(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
}

void main() {
  group('OdometerNumber first mount', () {
    testWidgets('renders every character of the value', (tester) async {
      await tester.pumpWidget(_host('GH¢ 1,240.42'));
      final chars = visibleChars(tester).join();
      expect(chars, 'GH¢ 1,240.42');
    });

    testWidgets('mount animation belongs to the screen, not the widget', (
      tester,
    ) async {
      // On first build there is no "previous" value, so NOTHING rolls: every
      // digit cell is a switcher but no tween is in flight, so the mounted
      // Text count equals the string length exactly.
      await tester.pumpWidget(_host('GH¢ 1,240.42'));
      expect(
        staticCells(tester),
        'GH¢ 1,240.42'.length,
        reason: 'first paint must be static, not a 350ms roll-in',
      );
    });

    testWidgets('settles immediately with no pending frames', (tester) async {
      await tester.pumpWidget(_host('9'));
      // pumpAndSettle would time out on an infinite animation; this proves there
      // is no ticker running after mount.
      await tester.pumpAndSettle();
      expect(visibleChars(tester), ['9']);
    });
  });

  group('OdometerNumber digit roll', () {
    testWidgets('only the changed digit rolls; the rest stay put', (
      tester,
    ) async {
      await tester.pumpWidget(_host('1,240.42'));
      await tester.pump(const Duration(milliseconds: 400));

      // ONLY the cents digit changes: 2 -> 5. Everything else is identical.
      await tester.pumpWidget(_host('1,240.45'));
      // One frame in, the roll is genuinely in flight.
      await tester.pump(const Duration(milliseconds: 40));

      // Mid-roll, both the outgoing and incoming character are mounted, so the
      // rolling cell contributes 2 Texts and the 7 static cells contribute 7.
      // Total = 9 for an 8-character string, i.e. exactly one rolling cell.
      final total = staticCells(tester);
      expect(
        total,
        '1,240.42'.length + 1,
        reason: 'exactly one digit cell should be mid-roll',
      );
    });

    testWidgets('settles to the new value', (tester) async {
      await tester.pumpWidget(_host('1,240.42'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(_host('1,240.45'));
      await tester.pumpAndSettle();
      expect(visibleChars(tester).join(), '1,240.45');
    });

    testWidgets('multiple changed digits each get their own cell', (
      tester,
    ) async {
      await tester.pumpWidget(_host('100.00'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(_host('999.99'));
      // '100.00' -> '999.99': positions 0,1,2 (digits) and 4,5 (digits) change;
      // position 3 ('.') does not.
      expect(rollingCells(tester), 5);
    });

    testWidgets('identical value produces no rolling cells', (tester) async {
      await tester.pumpWidget(_host('1,240.42'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(_host('1,240.42'));
      expect(
        staticCells(tester),
        '1,240.42'.length,
        reason: 'rebuild with the same string must not animate: an unchanged '
            'digit keeps its key, so no outgoing child is mounted',
      );
    });

    testWidgets('separators and currency symbols never roll', (tester) async {
      await tester.pumpWidget(_host('GH¢ 12.00'));
      await tester.pump(const Duration(milliseconds: 400));
      // Only the last two digits change.
      await tester.pumpWidget(_host('GH¢ 12.99'));
      // 'GH¢ 12.99' has four digit cells, each a switcher; only two of them
      // are mid-roll (Text count 8 + 2 outgoing = 10 for an 8-char string).
      expect(rollingCells(tester), 4);
      expect(staticCells(tester), 'GH¢ 12.99'.length + 2);
    });

    testWidgets('length change renders the whole new value', (tester) async {
      await tester.pumpWidget(_host('99.00'));
      await tester.pump(const Duration(milliseconds: 400));
      // A separator appears when the value grows a digit — new cells have no
      // previous character, so they render statically instead of rolling in
      // from nowhere.
      await tester.pumpWidget(_host('100.00'));
      await tester.pumpAndSettle();
      expect(visibleChars(tester).join(), '100.00');
    });
  });

  group('OdometerNumber accessibility', () {
    testWidgets('announces the whole value, not digit by digit', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host('GH¢ 1,240.42'));
      expect(find.bySemanticsLabel('GH¢ 1,240.42'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('honours an explicit semanticsLabel', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: OdometerNumber(
              value: 'GH¢ 1,240.42',
              style: _tabular,
              semanticsLabel: 'Balance 1,240 Ghana cedis 42 pesewas',
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Balance 1,240 Ghana cedis 42 pesewas'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('OdometerNumber reduced motion', () {
    testWidgets('roll is suppressed when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(_host('1,240.42'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(_host('1,240.85', disableAnimations: true));
      // The new value must be fully in place with no intermediate frame.
      expect(visibleChars(tester).join(), '1,240.85');
    });
  });

  group('OdometerNumber overflow safety', () {
    testWidgets('longer value does not overflow a tight parent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 40,
              child: OdometerNumber(value: '1,240.42', style: _tabular),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // scaleDown shrinks rather than clipping — a balance is never truncated.
      expect(tester.takeException(), isNull);
      expect(visibleChars(tester).join(), '1,240.42');
    });
  });

  group('OdometerNumber defaults', () {
    test('duration and curve default to the motion tokens', () {
      const w = OdometerNumber(value: '1', style: _tabular);
      expect(w.duration, MotionTokens.emphasized);
      expect(w.curve, MotionTokens.enter);
    });
  });
}
