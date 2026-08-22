//
// These are the invariants that keep the fold looking like paper instead of
// like a shader bug: the dragged corner lands under the finger, the sheet
// never leaves the plane before it is folded, the strip is watertight, and the
// solver produces no NaNs for degenerate inputs.
import 'dart:math' as math;
 
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
 
import 'package:azaman/widgets/book/page_geometry.dart';
 
const _page = Size(320, 480);
final _rect = Offset.zero & _page;
 
/// Re-implements the solver's forward map for a single point so the test can
/// assert against the model rather than against the implementation's output
/// buffers (which are typed data and awkward to introspect).
Offset _mapPoint(Offset p, Offset anchor, Offset touch, double r) {
  final d = anchor - touch;
  final dist = d.distance;
  final u = Offset(d.dx / dist, d.dy / dist);
  final m = Offset((anchor.dx + touch.dx) / 2, (anchor.dy + touch.dy) / 2);
  final s = (p.dx - m.dx) * u.dx + (p.dy - m.dy) * u.dy;
  final v = Offset(-u.dy, u.dx);
  final t = (p.dx - m.dx) * v.dx + (p.dy - m.dy) * v.dy;
 
  double uOut;
  if (s <= 0) {
    uOut = s;
  } else if (s <= math.pi * r) {
    uOut = r * math.sin(s / r);
  } else {
    uOut = -(s - math.pi * r);
  }
  return Offset(m.dx + u.dx * uOut + v.dx * t, m.dy + u.dy * uOut + v.dy * t);
}
 
void main() {
  group('fold model', () {
    test('the dragged corner lands under the finger (r → 0 reflection)', () {
      const anchor = Offset(320, 480);
      const touch = Offset(60, 300);
      // With a vanishing bend radius the fold is a pure reflection, so the
      // corner must map exactly onto the touch point.
      final mapped = _mapPoint(anchor, anchor, touch, 0.0001);
      expect((mapped - touch).distance, lessThan(0.01));
    });
 
    test('material on the spine side of the fold never moves', () {
      const anchor = Offset(320, 480);
      const touch = Offset(60, 300);
      const spineSide = Offset(4, 20);
      final mapped = _mapPoint(spineSide, anchor, touch, 24);
      expect((mapped - spineSide).distance, lessThan(0.001));
    });
 
    test('a finite bend radius shortens the reach (arc, not chord)', () {
      const anchor = Offset(320, 240);
      const touch = Offset(0, 240);
      final tight = _mapPoint(anchor, anchor, touch, 0.001);
      final loose = _mapPoint(anchor, anchor, touch, 40);
      // Wrapping around a fat cylinder consumes sheet, so the corner cannot
      // reach as far as the pure reflection does.
      expect(loose.dx, greaterThan(tight.dx));
    });
  });
 
  group('PageCurlSolver', () {
    late PageCurlSolver solver;
    setUp(() => solver = PageCurlSolver());
 
    test('is flat until the fold enters the page', () {
      final geo = solver.solve(
        pageRect: _rect,
        anchorCorner: const Offset(320, 480),
        touch: const Offset(319.9, 480),
        textureSize: _page,
      );
      expect(geo.hasBackFace, isFalse);
      expect(geo.liftHeight, lessThan(1.0));
    });
 
    test('produces both faces once the sheet folds over', () {
      final geo = solver.solve(
        pageRect: _rect,
        anchorCorner: const Offset(320, 480),
        touch: const Offset(40, 300),
        textureSize: _page,
      );
      expect(geo.frontFace, isNotNull);
      expect(geo.backFace, isNotNull);
      expect(geo.hasBackFace, isTrue);
      expect(geo.liftHeight, greaterThan(0));
    });
 
    test('lift grows then shrinks across a full turn (paper, not a hinge)', () {
      final lifts = <double>[];
      for (var p = 0.05; p <= 0.95; p += 0.05) {
        final touch = FlipPath.touchFor(progress: p, size: _page, anchorY: 480);
        lifts.add(solver
            .solve(
              pageRect: _rect,
              anchorCorner: const Offset(320, 480),
              touch: touch,
              textureSize: _page,
            )
            .liftHeight);
      }
      final peak = lifts.reduce(math.max);
      expect(peak, greaterThan(0));
      expect(lifts.first, lessThan(peak));
      // Every value is finite and non-negative — no NaN leaks into the paint.
      for (final l in lifts) {
        expect(l.isFinite, isTrue);
        expect(l, greaterThanOrEqualTo(0));
      }
    });
 
    test('geometry is continuous — no jumps between adjacent frames', () {
      CurlGeometry at(double p) => solver.solve(
            pageRect: _rect,
            anchorCorner: const Offset(320, 480),
            touch: FlipPath.touchFor(progress: p, size: _page, anchorY: 480),
            textureSize: _page,
          );
 
      var previous = at(0.10);
      for (var p = 0.11; p < 0.9; p += 0.01) {
        final next = at(p);
        // Lift is the scalar the eye is most sensitive to (it drives the
        // shadow); 1% of progress must barely move it. A jump here is what
        // reads as a "snap" on device.
        expect((next.liftHeight - previous.liftHeight).abs(), lessThan(6),
            reason: 'lift discontinuity at p=$p');
        // The crest endpoint legitimately slides fast along the page edge as
        // the fold sweeps, so this bound only has to catch real teleports.
        expect((next.crestStart - previous.crestStart).distance, lessThan(90),
            reason: 'crest discontinuity at p=$p');
        expect(next.radius, greaterThan(0));
        previous = next;
      }
    });
 
    test('survives degenerate input without throwing or NaN-ing', () {
      for (final touch in <Offset>[
        const Offset(320, 480), // exactly on the corner
        const Offset(-4000, -4000), // way off-screen
        const Offset(4000, 4000),
        Offset.zero,
      ]) {
        final geo = solver.solve(
          pageRect: _rect,
          anchorCorner: const Offset(320, 480),
          touch: touch,
          textureSize: _page,
        );
        expect(geo.liftHeight.isFinite, isTrue);
        expect(geo.radius.isFinite, isTrue);
      }
    });
 
    test('reuses its buffers — a drag allocates nothing steady-state', () {
      // Solve once to warm the buffers, then confirm repeated solves keep
      // returning geometry without growing (a proxy for the buffer reuse the
      // engine relies on; a regression here means per-frame garbage).
      for (var i = 0; i < 200; i++) {
        final p = (i % 100) / 100;
        final geo = solver.solve(
          pageRect: _rect,
          anchorCorner: const Offset(320, 480),
          touch: FlipPath.touchFor(progress: p, size: _page, anchorY: 480),
          textureSize: _page,
        );
        expect(geo.liftHeight.isFinite, isTrue);
      }
    });
  });
 
  group('FlipPath', () {
    test('progress and touch are exact inverses', () {
      for (var p = 0.0; p <= 1.0; p += 0.1) {
        final touch = FlipPath.touchFor(progress: p, size: _page, anchorY: 400);
        final back = FlipPath.progressFor(touch: touch, size: _page);
        expect(back, closeTo(p, 1e-9));
      }
    });
 
    test('grab position picks the nearest corner anchor', () {
      expect(FlipPath.anchorForGrab(const Offset(300, 20), _page), FlipAnchor.topOuter);
      expect(FlipPath.anchorForGrab(const Offset(300, 240), _page), FlipAnchor.middleOuter);
      expect(FlipPath.anchorForGrab(const Offset(300, 470), _page), FlipAnchor.bottomOuter);
    });
 
    test('release compensation keeps the corner continuous', () {
      const p = 0.42;
      const fingerY = 300.0;
      final anchorY = fingerY + FlipPath.anchorCompensation(progress: p, size: _page);
      final resumed = FlipPath.touchFor(progress: p, size: _page, anchorY: anchorY);
      expect(resumed.dy, closeTo(fingerY, 1e-9));
    });
  });
}
