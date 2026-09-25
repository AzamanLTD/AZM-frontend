// lib/widgets/book/flip_physics.dart
// =============================================================================
// FLIP PHYSICS — the "Swift feel" layer.
//
// Pure Dart (no widgets, no dart:ui) so it is cheap to unit-test and cheap to
// run: every value here is computed on the UI thread inside a ticker callback,
// so nothing allocates beyond a couple of doubles.
//
// The book exposes a single normalised progress value `p`:
//   p = 0.0  → leaf lies flat, unturned (page front fully visible)
//   p = 1.0  → leaf has flipped past the spine (page fully turned)
//
// A release is resolved by a *projected* landing position (current p plus the
// distance the finger would keep travelling under friction) rather than by a
// naive "is p > 0.5" test. That is what makes a fast flick complete a turn at
// 20% and a slow, deliberate drag fall back at 45% — the same rule UIKit's
// `UIScrollView` paging and SwiftUI's `interactiveSpring` use.
// =============================================================================
import 'package:flutter/physics.dart';

/// Tunable constants for the flip feel. Exposed as a const class so a caller
/// can A/B different feels without touching the engine.
class FlipPhysicsSpec {
  /// Spring stiffness for the settle animation.
  final double stiffness;

  /// Damping ratio. 1.0 = critically damped (no overshoot); slightly under 1
  /// gives the tiny "paper bounce" at the end of a turn.
  final double dampingRatio;

  /// Virtual mass of a leaf.
  final double mass;

  /// Fraction of the release velocity carried into the settle simulation.
  final double velocityTransfer;

  /// Friction used when projecting where a flick would land (per iOS
  /// `UIScrollView.decelerationRate` ≈ 0.998 per ms → 0.135 as a factor).
  final double decelerationFactor;

  /// Progress delta below which a turn is considered "not started" and any
  /// release always snaps back.
  final double deadZone;

  const FlipPhysicsSpec({
    this.stiffness = 190.0,
    this.dampingRatio = 0.86,
    this.mass = 1.0,
    this.velocityTransfer = 1.0,
    this.decelerationFactor = 0.135,
    this.deadZone = 0.012,
  });

  static const FlipPhysicsSpec standard = FlipPhysicsSpec();

  /// Snappier, less bouncy — used for the idle corner hint so the hint never
  /// wobbles after it retracts.
  static const FlipPhysicsSpec hint = FlipPhysicsSpec(
    stiffness: 120.0,
    dampingRatio: 1.0,
    velocityTransfer: 0.0,
  );

  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: dampingRatio,
      );
}

/// The outcome of a release gesture.
enum FlipRelease {
  /// Settle to p = 1.0 — the turn completes and the page index advances.
  complete,

  /// Settle to p = 0.0 — the leaf falls back where it came from.
  cancel,
}

/// Stateless helper that turns a (progress, velocity) pair into a settle
/// [SpringSimulation]. Kept separate from the controller so it can be tested
/// without a `TickerProvider`.
class FlipPhysics {
  final FlipPhysicsSpec spec;

  const FlipPhysics({this.spec = FlipPhysicsSpec.standard});

  /// Where the leaf would come to rest if the finger let go now and nothing
  /// else acted on it. `velocity` is in progress-units per second.
  double projectedLanding(double progress, double velocity) {
    return progress + velocity * spec.decelerationFactor;
  }

  /// Decide whether a release completes or cancels the turn.
  ///
  /// [progress] is the current normalised progress, [velocity] the release
  /// velocity in progress-units/second (positive = turning forward).
  FlipRelease resolve(double progress, double velocity) {
    if (progress < spec.deadZone) return FlipRelease.cancel;
    final landing = projectedLanding(progress, velocity);
    return landing >= 0.5 ? FlipRelease.complete : FlipRelease.cancel;
  }

  /// Build the settle simulation carrying the release velocity into the
  /// spring, so a flick keeps its momentum instead of restarting from zero.
  SpringSimulation settle({
    required double progress,
    required double velocity,
    required FlipRelease outcome,
  }) {
    final target = outcome == FlipRelease.complete ? 1.0 : 0.0;
    return SpringSimulation(
      spec.spring,
      progress,
      target,
      velocity * spec.velocityTransfer,
      tolerance: const Tolerance(distance: 0.0005, velocity: 0.0005),
    );
  }

  /// Simulation used for programmatic turns (arrow buttons, `jumpToPage`).
  SpringSimulation driveTo(double from, double to, {double velocity = 0.0}) {
    return SpringSimulation(
      spec.spring,
      from,
      to,
      velocity,
      tolerance: const Tolerance(distance: 0.0005, velocity: 0.0005),
    );
  }

  /// Rubber-band resistance for dragging past a book boundary (first page
  /// dragged backwards / last page dragged forwards). Mirrors the iOS
  /// `UIScrollView` overscroll curve: resistance grows with distance so the
  /// edge feels elastic, never dead.
  static double rubberBand(double overscroll, {double dimension = 1.0, double constant = 0.55}) {
    if (overscroll <= 0) return 0;
    return (1.0 - (1.0 / (overscroll * constant / dimension + 1.0))) * dimension;
  }
}
