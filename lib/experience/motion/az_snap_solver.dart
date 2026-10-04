// =============================================================================
// AZAMAN — MOTION CONTRACT: SNAP SOLVER
//
// Resolves which detent a drag should settle on. Plain Dart, deterministic,
// unit-testable without widgets. Replaces per-screen magic numbers for the
// story rail, retail tray, pull-reveals and sheet detent verification.
// =============================================================================

import 'dart:math' as math;

/// Resolves which detent a drag should settle on.
///
/// All values are in the same unit (pixels or fractions). The same inputs
/// always give the same target.
class AzSnapSolver {
  /// Ascending list of resting positions.
  final List<double> detents;

  /// 0..1 of the distance between two neighbouring detents a drag must cover
  /// (from the lower one) before it commits to the upper one.
  final double commitFraction;

  /// Velocity magnitude (units/second) at or above which direction decides.
  final double flingVelocity;

  const AzSnapSolver({
    required this.detents,
    this.commitFraction = 0.40,
    this.flingVelocity = 600,
  })  : assert(commitFraction >= 0 && commitFraction <= 1),
        assert(flingVelocity > 0);

  /// Returns the detent [position] should settle on, given the release
  /// [velocity] (positive = towards higher detents).
  double resolve(double position, double velocity) {
    // `List.length` is not usable in a const assert, so the detent-count
    // invariant is checked here instead of in the constructor.
    assert(detents.length >= 2, 'A snap solver needs at least two detents');
    final p = clamp(position);
    // 1) Fling decides direction.
    if (velocity.abs() >= flingVelocity) {
      return velocity > 0 ? _nextAbove(p, strict: true) : _nextBelow(p, strict: true);
    }
    // 2) Otherwise the nearest detent, biased by commitFraction from the lower one.
    final lower = _nextBelow(p);
    final upper = _nextAbove(p);
    if (lower == upper) return lower;
    final span = upper - lower;
    final t = (p - lower) / span;
    return t >= commitFraction ? upper : lower;
  }

  /// Nearest detent at or above [p] (strict: strictly above, unless at the top).
  double _nextAbove(double p, {bool strict = false}) {
    for (final d in detents) {
      if (strict ? d > p + _eps : d >= p - _eps) return d;
    }
    return detents.last;
  }

  /// Nearest detent at or below [p] (strict: strictly below, unless at the bottom).
  double _nextBelow(double p, {bool strict = false}) {
    for (var i = detents.length - 1; i >= 0; i--) {
      final d = detents[i];
      if (strict ? d < p - _eps : d <= p + _eps) return d;
    }
    return detents.first;
  }

  /// Clamps [p] to the detent range.
  double clamp(double p) =>
      math.max(detents.first, math.min(detents.last, p));

  static const double _eps = 1e-9;
}