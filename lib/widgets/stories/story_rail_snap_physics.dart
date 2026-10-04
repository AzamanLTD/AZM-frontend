/// The one owner of the inbox snap decision (Overhaul 04 §3.3).
///
/// The story rail lives at negative scroll offsets (slivers before the
/// `center`): `minScrollExtent` is "rail open", `0` is "rail closed".
/// Positive offsets (the chat list) behave like normal clamping scroll.
library;

import 'package:flutter/widgets.dart';

import 'package:azaman/experience/motion/az_snap_solver.dart';

class StoryRailSnapPhysics extends ClampingScrollPhysics {
  const StoryRailSnapPhysics({super.parent, required this.travel});

  /// From `AzMotion.of(context).travel`. When false the snap is instantaneous.
  final bool travel;

  /// Fraction of the rail that must be *pulled into view* before release
  /// commits to open. [AzSnapSolver.commitFraction] is measured from the lower
  /// detent (open, negative) towards the upper one (closed, 0), so "open past
  /// 40% pulled" is `1 - 0.40` on the solver's axis.
  static const double openFraction = 0.40;

  /// Velocity (px/s) above which direction alone decides.
  static const double flingVelocity = 600;

  /// Critically damped: no bounce past either detent.
  static final SpringDescription railSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 350, ratio: 1.0);

  @override
  StoryRailSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      StoryRailSnapPhysics(parent: buildParent(ancestor), travel: travel);

  /// Where a release at [pixels] with [velocity] settles: `open` or `0`.
  /// Exposed for tests; pure.
  static double resolveTarget({required double open, required double pixels, required double velocity}) {
    assert(open < 0);
    final solver = AzSnapSolver(
      detents: [open, 0],
      commitFraction: 1 - openFraction,
      flingVelocity: flingVelocity,
    );
    return solver.resolve(pixels, velocity);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final open = position.minScrollExtent; // negative when a rail exists
    if (open >= 0) return super.createBallisticSimulation(position, velocity);
    final p = position.pixels;
    // Only arbitrate inside the rail band. Above 0 the list behaves normally.
    final inBand = p < 0 || (p == 0 && velocity < 0);
    if (!inBand) return super.createBallisticSimulation(position, velocity);

    final target = resolveTarget(open: open, pixels: p, velocity: velocity);
    if ((target - p).abs() < toleranceFor(position).distance) return null;
    if (!travel) return _JumpSimulation(target);
    return ScrollSpringSimulation(railSpring, p, target, velocity, tolerance: toleranceFor(position));
  }

  /// Keep the list from flinging straight through the rail: motion that would
  /// cross from the list (positive) into the rail band stops at 0 (closed);
  /// the user pulls again to open.
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.pixels > 0 && value < 0) return value;
    return super.applyBoundaryConditions(position, value);
  }

  @override
  bool get allowImplicitScrolling => false;
}

class _JumpSimulation extends Simulation {
  _JumpSimulation(this.target);
  final double target;
  @override
  double x(double time) => target;
  @override
  double dx(double time) => 0;
  @override
  bool isDone(double time) => true;
}