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

Widget _host({
  required VoidCallback onTap,
  bool reduceMotion = false,
}) {
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
  testWidgets('a held bubble compresses, and releasing pops it once', (
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
      lessThan(0.99),
      reason: 'a bubble under a finger must visibly give way',
    );
    expect(pressed, greaterThan(0.88), reason: 'a press is contact, not a squash');
    expect(taps, 0, reason: 'nothing navigates while the finger is down');

    await gesture.up();
    await tester.pump();
    expect(taps, 1, reason: 'the release is the navigation');

    // The crest overshoots before it settles.
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      _scale(tester),
      greaterThan(1.0),
      reason: 'the rebound must pass its own size, or it reads as a fade back',
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
    await tester.pump(const Duration(milliseconds: 20));

    // Mid-pop: the member taps again, impatient.
    await tester.tap(find.byType(BubblePress));
    await tester.pump();

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
