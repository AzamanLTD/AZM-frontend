import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/motion/az_pull_reveal_controller.dart';
import 'package:azaman/theme/motion_tokens.dart';

void main() {
  AzPullRevealController make() => AzPullRevealController(
        vsync: const TestVSync(),
        maxExtentPx: 200,
      );

  test('starts closed at extent 0', () {
    final c = make();
    expect(c.extent, 0);
    expect(c.state, AzRevealState.closed);
    expect(c.isOpen, isFalse);
    c.dispose();
  });

  test('dragUpdate maps pixels to extent and clamps', () {
    final c = make();
    c.dragStart();
    expect(c.state, AzRevealState.dragging);
    c.dragUpdate(50);
    expect(c.extent, closeTo(0.25, 1e-9));
    c.dragUpdate(500);
    expect(c.extent, 1.0);
    c.dragUpdate(-1000);
    expect(c.extent, 0.0);
    c.dispose();
  });

  test('dragEnd below commit fraction closes; above opens (reduced motion)',
      () {
    final c = make();
    c.dragStart();
    c.dragUpdate(60); // 0.30 < 0.40
    c.dragEnd(0, travel: false);
    expect(c.state, AzRevealState.closed);
    expect(c.extent, 0);

    c.dragStart();
    c.dragUpdate(100); // 0.50 >= 0.40
    c.dragEnd(0, travel: false);
    expect(c.state, AzRevealState.open);
    expect(c.extent, 1);
    c.dispose();
  });

  test('fling velocity decides direction regardless of position', () {
    final c = make();
    c.dragStart();
    c.dragUpdate(20); // 0.10
    // 600 units/s in extent space = 120000 px/s with maxExtentPx 200.
    c.dragEnd(200000, travel: false);
    expect(c.isOpen, isTrue);
    c.dispose();
  });

  testWidgets('with travel the extent animates to the target over time',
      (tester) async {
    final c = AzPullRevealController(vsync: tester, maxExtentPx: 200);
    var notifications = 0;
    c.addListener(() => notifications++);

    c.open(travel: true);
    // State is semantic and flips immediately…
    expect(c.state, AzRevealState.open);
    expect(c.isOpen, isTrue);
    // …while the extent is still travelling.
    expect(c.extent, lessThan(1.0));

    // First pump starts the ticker (elapsed 0), then advance past the duration.
    await tester.pump();
    await tester.pump(MotionTokens.emphasized);
    await tester.pump(const Duration(milliseconds: 20));
    expect(c.extent, closeTo(1.0, 1e-6));
    expect(notifications, greaterThan(1));

    c.close(travel: true);
    expect(c.state, AzRevealState.closed);
    await tester.pump();
    await tester.pump(MotionTokens.emphasized);
    await tester.pump(const Duration(milliseconds: 20));
    expect(c.extent, closeTo(0.0, 1e-6));
    c.dispose();
  });

  test('reduced motion jumps in a single notification', () {
    final c = make();
    var notifications = 0;
    c.addListener(() => notifications++);
    c.open(travel: false);
    expect(c.extent, 1.0);
    expect(c.isOpen, isTrue);
    expect(notifications, 1);
    c.dispose();
  });
}