// Gesture arbiter: ONE Listener-based state machine decides tap / hold /
// horizontal / vertical / pinch (Overhaul 05 §2). These tests drive real
// pointers, including two-finger pinches and page-drag forwarding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/stories/viewer/story_gesture_arbiter.dart';

void main() {
  late PageController pages;
  late List<String> log;

  Widget host(double width) => MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: StoryGestureArbiter(
          pageController: pages,
          callbacks: StoryGestureCallbacks(
            onTap: (right) => log.add('tap:${right ? 'R' : 'L'}'),
            onHoldStart: () => log.add('hold+'),
            onHoldEnd: () => log.add('hold-'),
            onVerticalUpdate: (dy) => log.add('v:$dy'),
            onVerticalEnd: (v) => log.add('vend:$v'),
            onPinchScale: (s) => log.add('pinch:${s.toStringAsFixed(2)}'),
            onPinchEnd: () => log.add('pinchEnd'),
          ),
          // A real PageView so `pages` has an attached position; the arbiter
          // forwards horizontal drags into it.
          child: PageView(
            controller: pages,
            physics: const NeverScrollableScrollPhysics(
              parent: PageScrollPhysics(),
            ),
            children: const [
              SizedBox.expand(),
              SizedBox.expand(),
              SizedBox.expand(),
            ],
          ),
        ),
      );

  setUp(() {
    pages = PageController();
    log = [];
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: host(400)));
    await tester.pump();
  }

  testWidgets('tap in the left third is previous, right side is next',
      (tester) async {
    await pumpHost(tester);
    await tester.tapAt(const Offset(50, 400));
    await tester.pump();
    await tester.tapAt(const Offset(380, 400));
    await tester.pump();
    expect(log, ['tap:L', 'tap:R']);
  });

  testWidgets('a press shorter than the hold delay stays a tap',
      (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(100, 400));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    expect(log, ['tap:L']);
  });

  testWidgets('holding past 350ms fires hold start, release fires hold end',
      (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(100, 400));
    // Baseline frame (ticker elapsed 0), then real elapsed time.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    expect(log, ['hold+']);
    await gesture.up();
    await tester.pump();
    expect(log, ['hold+', 'hold-']);
  });

  testWidgets('a slow horizontal drag forwards to the PageController',
      (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(200, 400));
    // Several small moves (real velocity) past half the 400px viewport.
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The page position followed the finger; no tap/hold/vertical fired.
    expect(pages.offset, greaterThan(0));
    expect(log, isEmpty);
    await gesture.up();
    // The ballistic snap/settle itself belongs to PageScrollPhysics (tested
    // by Flutter); the contract here is that release hands off cleanly.
    await tester.pump(const Duration(milliseconds: 300));
    expect(log.where((e) => e.startsWith('tap') || e.contains('hold')), isEmpty);
  });

  testWidgets('vertical drags route to the vertical channel only',
      (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(log, contains('v:40.0'));
    expect(log.where((e) => e.startsWith('tap')).isEmpty, true);
    expect(pages.offset, 0);
    await gesture.up();
    await tester.pump();
    expect(log.last, startsWith('vend:'));
  });

  testWidgets('two fingers become a pinch; one lifting does not flip phase',
      (tester) async {
    await pumpHost(tester);
    final g1 = await tester.startGesture(const Offset(150, 400));
    final g2 = await tester.startGesture(const Offset(250, 400));
    await g1.moveBy(const Offset(-30, 0));
    await g2.moveBy(const Offset(30, 0));
    await tester.pump();
    final pinchLogged = log.any((e) => e.startsWith('pinch:'));
    expect(pinchLogged, isTrue, reason: 'distance 100→160 → scale 1.6');

    // First finger up: still one down → NO pinch end yet.
    await g1.up();
    await tester.pump();
    expect(log.contains('pinchEnd'), isFalse);

    await g2.up();
    await tester.pump();
    expect(log.contains('pinchEnd'), isTrue);
  });

  testWidgets('a small drift inside the slop stays a tap', (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(5, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(log, ['tap:R']);
  });

  testWidgets('pointer cancel ends an in-flight hold cleanly',
      (tester) async {
    await pumpHost(tester);
    final gesture = await tester.startGesture(const Offset(100, 400));
    // Baseline frame (ticker elapsed 0), then real elapsed time.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    expect(log, ['hold+']);
    await gesture.cancel();
    await tester.pump();
    expect(log, ['hold+', 'hold-']);
  });
}
