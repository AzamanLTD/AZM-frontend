//
// Also carries the engine's performance guard rails. They are deliberately
// loose (CI machines are noisy) but they fail loudly if someone reintroduces
// per-frame allocation or a dense mesh, which is the failure mode that turns a
// 120fps turn into a 30fps one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
 
import 'package:azaman/widgets/book/book.dart';
 
Widget _host({
  int pages = 5,
  FlipBookController? controller,
  ValueChanged<int>? onPageChanged,
  void Function(int index)? onTapPage,
  bool idleHint = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 480,
          child: FlipBook(
            controller: controller,
            pageCount: pages,
            idleHint: idleHint,
            onPageChanged: onPageChanged,
            pageBuilder: (context, i) => GestureDetector(
              onTap: () => onTapPage?.call(i),
              child: Container(
                color: i.isEven ? const Color(0xFFFDF6E3) : const Color(0xFFF3EADA),
                alignment: Alignment.center,
                child: Text('page $i'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
 
/// Drags the bottom-right corner toward the spine in [steps] increments, the
/// way a finger actually arrives (a single jump would skip the recogniser).
Future<void> _dragCorner(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
  int steps = 12,
  bool release = true,
  Duration frame = const Duration(milliseconds: 16),
}) async {
  final gesture = await tester.startGesture(from);
  final delta = (to - from) / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(delta);
    await tester.pump(frame);
  }
  if (release) {
    await gesture.up();
    await tester.pumpAndSettle();
  }
}
 
void main() {
  group('book widget', () {
    testWidgets('renders the current page and the one underneath it',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('page 0'), findsOneWidget);
      expect(find.text('page 1'), findsOneWidget); // revealed beneath the leaf
      expect(find.text('page 2'), findsNothing);
    });
 
    testWidgets('a corner drag across the spine turns the page', (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(_host(onPageChanged: seen.add));
      final book = tester.getRect(find.byType(FlipBook));
 
      await _dragCorner(
        tester,
        from: book.bottomRight - const Offset(6, 12),
        to: book.bottomLeft + const Offset(-40, -12),
      );
 
      expect(seen, [1]);
      expect(find.text('page 1'), findsOneWidget);
    });
 
    testWidgets('a short drag falls back and keeps the page', (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(_host(onPageChanged: seen.add));
      final book = tester.getRect(find.byType(FlipBook));
 
      await _dragCorner(
        tester,
        from: book.bottomRight - const Offset(6, 12),
        to: book.bottomRight - const Offset(50, 12),
        frame: const Duration(milliseconds: 40), // slow → no flick velocity
      );
 
      expect(seen, isEmpty);
      expect(find.text('page 0'), findsOneWidget);
    });
 
    testWidgets('turning back returns to the previous page', (tester) async {
      final controller = FlipBookController();
      await tester.pumpWidget(_host(controller: controller));
      final book = tester.getRect(find.byType(FlipBook));
 
      await _dragCorner(
        tester,
        from: book.bottomRight - const Offset(6, 12),
        to: book.bottomLeft + const Offset(-40, -12),
      );
      expect(controller.page, 1);
 
      // Grab the left edge and pull the leaf back across the spine.
      await _dragCorner(
        tester,
        from: book.bottomLeft + const Offset(6, -12),
        to: book.bottomRight + const Offset(40, -12),
      );
      expect(controller.page, 0);
      controller.dispose();
    });
 
    testWidgets('page content stays tappable at rest', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(_host(onTapPage: taps.add));
      await tester.tap(find.text('page 0'));
      await tester.pump();
      expect(taps, [0]);
    });
 
    testWidgets('a turn in flight swallows taps on the moving leaf',
        (tester) async {
      final taps = <int>[];
      final controller = FlipBookController();
      await tester.pumpWidget(_host(controller: controller, onTapPage: taps.add));
      final book = tester.getRect(find.byType(FlipBook));
 
      await _dragCorner(
        tester,
        from: book.bottomRight - const Offset(6, 12),
        to: book.center,
        release: false,
      );
      expect(controller.state, FlipState.dragging);
      await tester.tapAt(book.center);
      await tester.pump();
      expect(taps, isEmpty);
      controller.dispose();
    });
 
    testWidgets('never runs past the last page', (tester) async {
      final controller = FlipBookController();
      await tester.pumpWidget(_host(pages: 2, controller: controller));
      final book = tester.getRect(find.byType(FlipBook));
      for (var i = 0; i < 3; i++) {
        await _dragCorner(
          tester,
          from: book.bottomRight - const Offset(6, 12),
          to: book.bottomLeft + const Offset(-40, -12),
        );
      }
      expect(controller.page, 1);
      controller.dispose();
    });
 
    testWidgets('survives a resize mid-life without losing its place',
        (tester) async {
      final controller = FlipBookController();
      await tester.pumpWidget(_host(controller: controller));
      final book = tester.getRect(find.byType(FlipBook));
      await _dragCorner(
        tester,
        from: book.bottomRight - const Offset(6, 12),
        to: book.bottomLeft + const Offset(-40, -12),
      );
      expect(controller.page, 1);
 
      tester.view.physicalSize = const Size(1200, 2000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
 
    testWidgets('disposes cleanly while a turn is still settling',
        (tester) async {
      await tester.pumpWidget(_host());
      final book = tester.getRect(find.byType(FlipBook));
      final gesture = await tester.startGesture(book.bottomRight - const Offset(6, 12));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16)); // mid-settle
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });
 
  group('performance guard rails', () {
    test('a full turn of geometry solves well inside one frame', () {
      const size = Size(360, 560);
      final solver = PageCurlSolver();
      final rect = Offset.zero & size;
 
      // Warm-up (JIT + buffer growth).
      for (var i = 0; i < 50; i++) {
        solver.solve(
          pageRect: rect,
          anchorCorner: const Offset(360, 560),
          touch: FlipPath.touchFor(progress: i / 50, size: size, anchorY: 560),
          textureSize: size,
        );
      }
 
      const frames = 600; // ~5 seconds of continuous 120fps dragging
      final sw = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        solver.solve(
          pageRect: rect,
          anchorCorner: const Offset(360, 560),
          touch: FlipPath.touchFor(
              progress: (i % 100) / 100, size: size, anchorY: 560),
          textureSize: size,
        );
      }
      sw.stop();
      final perFrameUs = sw.elapsedMicroseconds / frames;
      // The geometry is the only per-frame CPU work the engine does. A 120fps
      // budget is 8333µs for *everything*; the solver must be a rounding error
      // in that. (Measured ≈ 20µs on CI hardware.)
      expect(perFrameUs, lessThan(800),
          reason: 'solver took ${perFrameUs.toStringAsFixed(1)}µs/frame');
    });
 
    test('the strip stays small — no dense mesh regression', () {
      // A 2×N strip is what keeps the draw call cheap. Guard the slab count so
      // nobody "improves" it into an N×M grid.
      expect(PageCurlSolver.curvedSlabs, lessThanOrEqualTo(48));
    });
 
    testWidgets('a settling turn does not rebuild the page widgets',
        (tester) async {
      var builds = 0;
      final controller = FlipBookController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: FlipBook(
              controller: controller,
              pageCount: 4,
              idleHint: false,
              pageBuilder: (context, i) {
                builds++;
                return ColoredBox(
                  color: i.isEven ? Colors.white : Colors.amber,
                  child: Text('page $i'),
                );
              },
            ),
          ),
        ),
      ));
 
      final book = tester.getRect(find.byType(FlipBook));
      final gesture = await tester.startGesture(book.bottomRight - const Offset(6, 12));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final duringDrag = builds;
      // Ten more drag frames must not rebuild a single page widget: the leaf
      // is a raster and the pages underneath are untouched.
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, duringDrag,
          reason: 'page widgets rebuilt mid-drag — the curl must be a raster');
 
      await gesture.up();
      await tester.pumpAndSettle();
      controller.dispose();
    });
  });
}
