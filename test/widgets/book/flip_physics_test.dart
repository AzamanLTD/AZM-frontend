// a flick always wins over position, a lazy drag always falls back, and every
// settle actually converges inside a frame budget humans notice.
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
 
import 'package:azaman/widgets/book/flip_physics.dart';
 
/// Integrates a simulation the way `AnimationController.animateWith` does and
/// returns (settleSeconds, maxOvershoot).
(double, double) run(SpringSimulation sim, {double target = 1.0}) {
  const dt = 1 / 120;
  var t = 0.0;
  var overshoot = 0.0;
  while (t < 5.0) {
    t += dt;
    final x = sim.x(t);
    final beyond = target == 1.0 ? x - 1.0 : -x;
    if (beyond > overshoot) overshoot = beyond;
    if (sim.isDone(t)) break;
  }
  return (t, overshoot);
}
 
void main() {
  const physics = FlipPhysics();
 
  group('release resolution', () {
    test('a fast flick completes the turn from only 20%', () {
      expect(physics.resolve(0.20, 4.0), FlipRelease.complete);
    });
 
    test('a slow drag at 45% falls back', () {
      expect(physics.resolve(0.45, 0.1), FlipRelease.cancel);
    });
 
    test('a drag past halfway with no velocity completes', () {
      expect(physics.resolve(0.55, 0.0), FlipRelease.complete);
    });
 
    test('a backward flick cancels even from 80%', () {
      expect(physics.resolve(0.80, -4.0), FlipRelease.cancel);
    });
 
    test('a barely-started drag always snaps back', () {
      expect(physics.resolve(0.005, 8.0), FlipRelease.cancel);
    });
 
    test('the decision is monotonic in velocity', () {
      // Once a velocity is fast enough to complete, every faster one must too.
      var seenComplete = false;
      for (var v = -6.0; v <= 6.0; v += 0.25) {
        final done = physics.resolve(0.35, v) == FlipRelease.complete;
        if (seenComplete) {
          expect(done, isTrue, reason: 'non-monotonic at v=$v');
        }
        seenComplete = seenComplete || done;
      }
      expect(seenComplete, isTrue);
    });
 
    test('the decision is monotonic in progress', () {
      var seenComplete = false;
      for (var p = 0.02; p <= 1.0; p += 0.02) {
        final done = physics.resolve(p, 0.0) == FlipRelease.complete;
        if (seenComplete) expect(done, isTrue, reason: 'non-monotonic at p=$p');
        seenComplete = seenComplete || done;
      }
      expect(seenComplete, isTrue);
    });
  });
 
  group('settle simulation', () {
    test('completes quickly and lands exactly on target', () {
      final sim = physics.settle(
        progress: 0.6,
        velocity: 1.2,
        outcome: FlipRelease.complete,
      );
      final (seconds, _) = run(sim);
      expect(seconds, lessThan(1.2));
      expect(sim.x(seconds), closeTo(1.0, 0.005));
    });
 
    test('cancels back to zero without sticking', () {
      final sim = physics.settle(
        progress: 0.4,
        velocity: -0.8,
        outcome: FlipRelease.cancel,
      );
      final (seconds, _) = run(sim, target: 0.0);
      expect(seconds, lessThan(1.2));
      expect(sim.x(seconds), closeTo(0.0, 0.005));
    });
 
    test('has a small paper bounce, never a rubbery one', () {
      final sim = physics.settle(
        progress: 0.55,
        velocity: 3.0,
        outcome: FlipRelease.complete,
      );
      final (_, overshoot) = run(sim);
      expect(overshoot, greaterThan(0.0), reason: 'should feel springy');
      expect(overshoot, lessThan(0.12), reason: 'should not feel rubbery');
    });
 
    test('carries release velocity into the spring', () {
      final slow = physics.settle(
          progress: 0.5, velocity: 0.0, outcome: FlipRelease.complete);
      final fast = physics.settle(
          progress: 0.5, velocity: 5.0, outcome: FlipRelease.complete);
      // At the same instant the flicked leaf must be further along.
      expect(fast.x(0.05), greaterThan(slow.x(0.05)));
    });
 
    test('never produces a non-finite value across the whole state space', () {
      for (var p = 0.0; p <= 1.0; p += 0.05) {
        for (var v = -12.0; v <= 12.0; v += 1.0) {
          final sim = physics.settle(
            progress: p,
            velocity: v,
            outcome: physics.resolve(p, v),
          );
          for (var t = 0.0; t < 1.0; t += 0.02) {
            expect(sim.x(t).isFinite, isTrue, reason: 'p=$p v=$v t=$t');
          }
        }
      }
    });
  });
 
  group('rubber band', () {
    test('resists progressively and never exceeds the dimension', () {
      final a = FlipPhysics.rubberBand(10, dimension: 100);
      final b = FlipPhysics.rubberBand(50, dimension: 100);
      final c = FlipPhysics.rubberBand(5000, dimension: 100);
      expect(a, lessThan(b));
      expect(b, lessThan(c));
      expect(c, lessThan(100));
      expect(FlipPhysics.rubberBand(-5), 0);
      // The first pixels of overscroll are nearly 1:1, so the edge never feels
      // dead on touch-down.
      expect(FlipPhysics.rubberBand(1, dimension: 100), closeTo(0.55, 0.02));
    });
  });
}
