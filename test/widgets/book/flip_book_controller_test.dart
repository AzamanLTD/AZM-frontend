// Driven without a widget tree beyond a bare `TickerProvider`, so these run in
// milliseconds and pin the state machine rather than the pixels.
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
 
import 'package:azaman/widgets/book/flip_book_controller.dart';
import 'package:azaman/widgets/book/page_geometry.dart';
 
const _size = Size(360, 560);
 
class _Vsync implements TickerProvider {
  final tickers = <Ticker>[];
  @override
  Ticker createTicker(TickerCallback onTick) {
    final t = Ticker(onTick);
    tickers.add(t);
    return t;
  }
}
 
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
 
  late FlipBookController c;
  late _Vsync vsync;
  late List<MethodCall> haptics;
 
  setUp(() {
    haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
    vsync = _Vsync();
    c = FlipBookController()
      ..attach(vsync)
      ..updateMetrics(pageCount: 6, size: _size);
  });
 
  tearDown(() {
    for (final t in vsync.tickers) {
      if (t.isActive) t.stop(canceled: true);
    }
    c.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
 
  group('grab', () {
    test('a forward grab starts a turn and anchors to the grabbed corner', () {
      expect(c.beginDrag(const Offset(350, 20), forward: true), isTrue);
      expect(c.state, FlipState.dragging);
      expect(c.anchor, FlipAnchor.topOuter);
      expect(c.direction, FlipDirection.forward);
    });
 
    test('every anchor band is reachable', () {
      expect(c.beginDrag(const Offset(350, 20), forward: true), isTrue);
      expect(c.anchor, FlipAnchor.topOuter);
      c.cancelDrag();
      expect(c.beginDrag(const Offset(350, 280), forward: true), isTrue);
      expect(c.anchor, FlipAnchor.middleOuter);
      c.cancelDrag();
      expect(c.beginDrag(const Offset(350, 540), forward: true), isTrue);
      expect(c.anchor, FlipAnchor.bottomOuter);
    });
 
    test('a backward grab on the first page is refused so taps still land', () {
      expect(c.beginDrag(const Offset(10, 300), forward: false), isFalse);
      expect(c.state, FlipState.idle);
    });
 
    test('a forward grab on the last page is refused', () {
      final last = FlipBookController()
        ..attach(vsync)
        ..updateMetrics(pageCount: 3, size: _size);
      last.turnForward();
      // Not settled yet, so drive the state machine straight to the end.
      last.dispose();
      final single = FlipBookController(initialPage: 0)
        ..attach(vsync)
        ..updateMetrics(pageCount: 1, size: _size);
      expect(single.beginDrag(const Offset(350, 300), forward: true), isFalse);
      single.dispose();
    });
  });
 
  group('drag tracking', () {
    test('progress follows the finger 1:1 across the page', () {
      c.beginDrag(const Offset(360, 500), forward: true);
      expect(c.progress, closeTo(0.0, 1e-9));
      c.updateDrag(const Offset(180, 400));
      expect(c.progress, closeTo(0.25, 1e-9));
      c.updateDrag(const Offset(0, 300));
      expect(c.progress, closeTo(0.5, 1e-9));
      c.updateDrag(const Offset(-360, 300));
      expect(c.progress, closeTo(1.0, 1e-9));
    });
 
    test('progress is clamped — dragging past the spine cannot overshoot', () {
      c.beginDrag(const Offset(360, 500), forward: true);
      c.updateDrag(const Offset(-9999, 300));
      expect(c.progress, 1.0);
      c.updateDrag(const Offset(9999, 300));
      expect(c.progress, 0.0);
    });
 
    test('the touch point tracks the finger exactly while dragging', () {
      c.beginDrag(const Offset(360, 540), forward: true);
      c.updateDrag(const Offset(120, 220));
      expect(c.touch.dx, 120);
      expect(c.touch.dy, 220);
    });
 
    test('a wild vertical drag is clamped instead of folding to a needle', () {
      c.beginDrag(const Offset(360, 540), forward: true);
      c.updateDrag(const Offset(120, 99999));
      expect(c.touch.dy, lessThanOrEqualTo(_size.height * 1.35));
      c.updateDrag(const Offset(120, -99999));
      expect(c.touch.dy, greaterThanOrEqualTo(-_size.height * 0.35));
    });
 
    test('updates outside a drag are ignored', () {
      c.updateDrag(const Offset(10, 10));
      expect(c.state, FlipState.idle);
      expect(c.progress, 0.0);
    });
  });
 
  group('haptics', () {
    test('fire exactly once when the leaf crosses the halfway line', () {
      c.beginDrag(const Offset(360, 500), forward: true);
      c.updateDrag(const Offset(200, 500));
      expect(haptics, isEmpty);
      c.updateDrag(const Offset(-20, 500)); // just past 50%
      expect(haptics, hasLength(1));
      c.updateDrag(const Offset(-120, 500)); // still past
      expect(haptics, hasLength(1));
    });
 
    test('fire again when the leaf falls back across the line', () {
      c.beginDrag(const Offset(360, 500), forward: true);
      c.updateDrag(const Offset(-20, 500));
      c.updateDrag(const Offset(200, 500));
      expect(haptics, hasLength(2));
    });
 
    test('can be switched off', () {
      final quiet = FlipBookController(hapticsEnabled: false)
        ..attach(vsync)
        ..updateMetrics(pageCount: 4, size: _size);
      quiet.beginDrag(const Offset(360, 500), forward: true);
      quiet.updateDrag(const Offset(-20, 500));
      expect(haptics, isEmpty);
      quiet.dispose();
    });
  });
 
  group('release', () {
    testWidgets('a flick past halfway advances the page', (tester) async {
      c.beginDrag(const Offset(360, 500), forward: true);
      c.updateDrag(const Offset(60, 480));
      c.endDrag(const Offset(-2400, 0));
      expect(c.state, FlipState.settling);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.state, FlipState.idle);
      expect(c.page, 1);
      expect(c.progress, 0.0);
    });
 
    testWidgets('a lazy release below halfway keeps the page', (tester) async {
      c.beginDrag(const Offset(360, 500), forward: true);
      c.updateDrag(const Offset(300, 480));
      c.endDrag(Offset.zero);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.page, 0);
      expect(c.state, FlipState.idle);
    });
 
    testWidgets('a backward drag returns to the previous page', (tester) async {
      c.turnForward();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.page, 1);
 
      expect(c.beginDrag(const Offset(4, 300), forward: false), isTrue);
      expect(c.direction, FlipDirection.backward);
      c.updateDrag(const Offset(330, 300));
      c.endDrag(const Offset(2400, 0));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.page, 0);
    });
 
    testWidgets('the corner does not jump when the finger lets go',
        (tester) async {
      c.beginDrag(const Offset(360, 540), forward: true);
      c.updateDrag(const Offset(120, 300));
      final before = c.touch;
      c.endDrag(Offset.zero);
      // First settle frame must resume from where the finger was.
      expect((c.touch - before).distance, lessThan(1.0));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
    });
  });
 
  group('programmatic turns', () {
    testWidgets('forward then backward returns to the start', (tester) async {
      expect(c.turnForward(), isTrue);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.page, 1);
      expect(c.turnBackward(), isTrue);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.page, 0);
      expect(c.turnBackward(), isFalse);
    });
 
    testWidgets('cannot run past the end of the book', (tester) async {
      for (var i = 0; i < 5; i++) {
        expect(c.turnForward(), isTrue);
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
      }
      expect(c.page, 5);
      expect(c.turnForward(), isFalse);
    });
 
    testWidgets('are refused mid-drag so a gesture is never hijacked',
        (tester) async {
      c.beginDrag(const Offset(360, 500), forward: true);
      expect(c.turnForward(), isFalse);
      expect(c.turnBackward(), isFalse);
      c.cancelDrag();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
    });
  });
 
  group('idle hint', () {
    testWidgets('lifts the corner slightly and returns to rest', (tester) async {
      c.playHint();
      expect(c.state, FlipState.hinting);
      await tester.pump(); // first frame only starts the ticker's clock
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.progress, greaterThan(0.0));
      expect(c.progress, lessThan(0.12), reason: 'a hint, not a turn');
      expect(haptics, isEmpty, reason: 'a hint must never buzz');
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(c.state, FlipState.idle);
      expect(c.page, 0, reason: 'a hint must never change the page');
    });
 
    testWidgets('is interrupted the moment the user touches the book',
        (tester) async {
      c.playHint();
      await tester.pump(const Duration(milliseconds: 300));
      c.stopHint();
      expect(c.state, FlipState.idle);
      expect(c.progress, 0.0);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
    });
  });
 
  group('metrics', () {
    test('shrinking the book clamps the current page', () {
      c.updateMetrics(pageCount: 2, size: _size);
      expect(c.page, lessThanOrEqualTo(1));
    });
 
    test('a book with a single page can never turn', () {
      final one = FlipBookController()
        ..attach(vsync)
        ..updateMetrics(pageCount: 1, size: _size);
      expect(one.turnForward(), isFalse);
      expect(one.beginDrag(const Offset(350, 300), forward: true), isFalse);
      one.dispose();
    });
  });
}
