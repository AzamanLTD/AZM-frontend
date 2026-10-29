// =============================================================================
// AZAMAN — MOTION CONTRACT: PULL REVEAL
//
// Extent 0..1 for a hidden surface pulled into view by a gesture that is NOT
// owned by a scrollable (e.g. a Home card deck or a drawer handle). Scroll-
// owned reveals (story rail) use `AzSnapSolver` directly on scroll offsets.
// =============================================================================

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'package:azaman/theme/motion_tokens.dart';
import 'az_snap_solver.dart';

enum AzRevealState { closed, dragging, open }

class AzPullRevealController extends ChangeNotifier {
  AzPullRevealController({
    required TickerProvider vsync,
    required this.maxExtentPx,
    this.solver = const AzSnapSolver(detents: [0, 1]),
  })  : assert(maxExtentPx > 0),
        _anim = AnimationController(
          vsync: vsync,
          duration: MotionTokens.emphasized,
        ) {
    _anim.addListener(_onTick);
  }

  /// Pixel distance that maps to extent 1.0.
  final double maxExtentPx;
  final AzSnapSolver solver;
  final AnimationController _anim;

  double _extent = 0; // 0..1
  AzRevealState _state = AzRevealState.closed;

  /// 0 = closed, 1 = fully revealed.
  double get extent => _extent;
  AzRevealState get state => _state;
  bool get isOpen => _state == AzRevealState.open;
  bool get isDragging => _state == AzRevealState.dragging;

  void _onTick() {
    _extent = _anim.value;
    notifyListeners();
  }

  void dragStart() {
    _anim.stop();
    _state = AzRevealState.dragging;
    notifyListeners();
  }

  /// [deltaPx] positive = pulling further open.
  void dragUpdate(double deltaPx) {
    if (_state != AzRevealState.dragging) dragStart();
    _extent = (_extent + deltaPx / maxExtentPx).clamp(0.0, 1.0);
    // Keep the animation value in sync so a later settle starts from here.
    _anim.value = _extent;
    notifyListeners();
  }

  /// [velocityPxPerSec] positive = pulling further open.
  /// [travel] is `AzMotion.of(context).travel`; with reduced motion the state
  /// still changes but the surface jumps instead of animating.
  void dragEnd(double velocityPxPerSec, {required bool travel}) {
    final target = solver.resolve(_extent, velocityPxPerSec / maxExtentPx);
    settle(target, travel: travel);
  }

  void settle(double target, {required bool travel}) {
    final t = solver.clamp(target);
    _state = t >= 1 ? AzRevealState.open : AzRevealState.closed;
    if (!travel) {
      _anim.value = t; // triggers _onTick → extent + notify
      return;
    }
    _anim.animateTo(t, curve: MotionTokens.enter);
    notifyListeners(); // state changed even before the first tick lands
  }

  void open({required bool travel}) => settle(1, travel: travel);
  void close({required bool travel}) => settle(0, travel: travel);

  @override
  void dispose() {
    _anim.removeListener(_onTick);
    _anim.dispose();
    super.dispose();
  }
}