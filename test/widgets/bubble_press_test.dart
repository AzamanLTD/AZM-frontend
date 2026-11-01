// AZAMAN — PRESS AND POP ARE ONE GESTURE.
//
// The Home bubbles are dimensional now, and a dimensional control that only
// changes colour on tap feels dead. What the owner asked for is physical:
// compress under the finger, rebound past its own size, and leave for the
// destination while it is still moving.
//
// These contracts pin the mechanics, not the pixels:
//
//   • a held bubble is measurably SMALLER than a resting one;
//   • releasing compresses → crest → rest and ends at exactly 1.0, so a
//     navigation never leaves the bubble sitting slightly small;
//   • the destination is requested exactly once per gesture, even if the
//     member taps again while the rebound is travelling;
//   • dragging off the bubble cancels: nothing navigates and the bubble
//     returns to rest;
//   • reduced motion removes the scale entirely and navigates immediately.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/bubble_press.dart';

/// The scale the bubble is currently drawn at.
double _scale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('bubble_press_scale')),
  );
  // Read the X axis, not getMaxScaleOnAxis(): Transform.scale leaves the Z
  // axis at 1.0, so the maximum is always exactly 1.0 and every assertion
  // below would pass for the wrong reason.
  return transform.transform.entry(0, 0);
}

Widget _host({required VoidCallback onTap, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 60,
            height: 60,
            child: BubblePress(
              onTap: onTap,
              // A real child with a real size: a zero-size child would make
              // the gesture area zero too, and the press would never arrive.
              child: const SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF102030),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a quick flick (released mid-press) never snaps smaller', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTap: () => taps++));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BubblePress)),
    );
    // 15ms: well inside the 90ms press, so the finger never reached 0.93.
    await tester.pump(const Duration(milliseconds: 15));
    final released = _scale(tester);
    expect(released, greaterThan(0.96), reason: 'a flick barely compresses');

    await gesture.up();

    // Sample every frame of the rebound. The scale must move continuously:
    // restarting the pop at the fully-pressed depth would jump straight back
    // down to _pressScale here, which is the bug this contract exists for.
    var previous = released;
    var sawCrest = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = _scale(tester);
      expect(
        (now - previous).abs(),
        lessThan(0.05),
        reason:
            'discontinuity between ${previous.toStringAsFixed(3)} and '
            '${now.toStringAsFixed(3)} on frame $i',
      );
      if (now > 1.0) sawCrest = true;
      previous = now;
    }

    expect(sawCrest, isTrue, reason: 'the flick must still pop past its size');
    expect(taps, 1, reason: 'one flick is one navigation');
    await tester.pumpAndSettle();
    expect(_scale(tester), 1.0);
  });

  testWidgets('a held bubble compresses, and the push waits for the crest', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTap: () => taps++));
    expect(_scale(tester), 1.0, reason: 'rest is exactly its own size');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BubblePress)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final pressed = _scale(tester);
    expect(
      pressed,
      lessThan(0.95),
      reason: 'a held bubble must reach its press depth',
    );
    expect(taps, 0, reason: 'nothing navigates while the finger is down');

    await gesture.up();
    await tester.pump();
    expect(
      taps,
      0,
      reason:
          'the release frame must NOT navigate: the pop leaves at the crest',
    );

    // Hold until the bubble is at its widest, then the push is due. The rise
    // is the first 40% of a 180ms pop, so the crest lands around 72ms.
    await tester.pump(const Duration(milliseconds: 85));
    expect(_scale(tester), greaterThan(1.0), reason: 'crest');
    expect(
      taps,
      1,
      reason: 'the navigation leaves with the bubble at its widest',
    );

    await tester.pumpAndSettle();
    expect(_scale(tester), 1.0, reason: 'the bubble must not stay small');
    expect(taps, 1);
  });

  testWidgets('a second tap during the rebound cannot push twice', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTap: () => taps++));

    await tester.tap(find.byType(BubblePress));
    // 20ms in: the pop is travelling, the crest has not arrived.
    await tester.pump(const Duration(milliseconds: 20));

    // Mid-pop: the member taps again, impatient.
    await tester.tap(find.byType(BubblePress));
    await tester.pump();

    // Past the crest of the FIRST pop: exactly one navigation, not two.
    await tester.pump(const Duration(milliseconds: 80));
    expect(taps, 1, reason: 'one gesture, one navigation');

    await tester.pumpAndSettle();
    // Once settled, the control is live again.
    await tester.tap(find.byType(BubblePress));
    await tester.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('dragging off the bubble cancels and navigates nothing', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTap: () => taps++));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BubblePress)),
    );
    await tester.pump(const Duration(milliseconds: 90));
    await gesture.moveBy(const Offset(0, 120));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(taps, 0);
    expect(_scale(tester), 1.0);
  });

  testWidgets('reduced motion skips the scale and navigates on tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTap: () => taps++, reduceMotion: true));

    expect(
      find.byKey(const ValueKey<String>('bubble_press_scale')),
      findsNothing,
      reason: 'reduced motion must not build a transforming control',
    );

    await tester.tap(find.byType(BubblePress));
    await tester.pump();
    expect(taps, 1);
  });
}
