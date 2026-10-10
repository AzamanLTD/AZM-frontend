// =============================================================================
// AZAMAN — PULL-DOWN DISMISSIBLE PAGE SURFACE
//
// Shared gesture shell for full-page financial surfaces such as Add Cash and
// Receive. Uses the same resisted pull, threshold haptic, spring-back and
// committed dismissal grammar. The child remains responsible for its own
// scroll/paging interactions; this recognizer only competes for vertical drags,
// matching the established Add Cash behavior.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class PullDownDismissibleSurface extends StatefulWidget {
  const PullDownDismissibleSurface({
    super.key,
    required this.onDismiss,
    this.canDismiss,
    this.onDismissRejected,
    required this.child,
  });

  final VoidCallback onDismiss;

  /// Lets nested multi-state surfaces consume a committed downward pull before
  /// the whole route closes. Return false to reject dismissal and spring back.
  final bool Function()? canDismiss;

  /// Called when a committed pull is rejected by [canDismiss].
  final VoidCallback? onDismissRejected;

  final Widget child;

  @override
  State<PullDownDismissibleSurface> createState() =>
      _PullDownDismissibleSurfaceState();
}

class _PullDownDismissibleSurfaceState
    extends State<PullDownDismissibleSurface>
    with SingleTickerProviderStateMixin {
  double _dragDy = 0;
  double _settleFrom = 0;
  bool _armed = false;
  late final AnimationController _settle;

  static const double _dragResistance = 0.55;
  static const double _maxDragTravel = 240;
  static const double _commitThreshold = 110;
  static const double _flingVelocity = 700;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: MotionTokens.control,
      value: 1,
    )..addStatusListener(_onSettleStatus);
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_dragDy == 0 && _settleFrom == 0) return;
    if (!mounted) return;
    setState(() {
      _dragDy = 0;
      _settleFrom = 0;
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    // A new gesture may land while spring-back is running. Resume from the
    // on-screen offset, not the stale pre-spring offset.
    if (_settle.isAnimating) {
      final visual =
          _settleFrom * (1.0 - MotionTokens.enter.transform(_settle.value));
      _settle.stop();
      setState(() {
        _dragDy = visual;
        _settleFrom = 0;
        _armed = visual >= _commitThreshold;
      });
      return;
    }
    _armed = false;
    _settle.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0 && _dragDy == 0) return;
    final next = (_dragDy + details.delta.dy * _dragResistance).clamp(
      0.0,
      _maxDragTravel,
    );
    if (next == _dragDy) return;

    if (!_armed && next >= _commitThreshold) {
      _armed = true;
      AzamanHaptics.threshold();
    } else if (_armed && next < _commitThreshold) {
      _armed = false;
    }
    setState(() => _dragDy = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final committed =
        _dragDy >= _commitThreshold ||
        details.velocity.pixelsPerSecond.dy >= _flingVelocity;
    if (committed) {
      if (widget.canDismiss != null && !widget.canDismiss!()) {
        widget.onDismissRejected?.call();
        _springBack();
        return;
      }
      widget.onDismiss();
      return;
    }
    _springBack();
  }

  void _springBack() {
    if (_dragDy <= 0) return;
    _armed = false;
    if (MediaQuery.of(context).disableAnimations) {
      setState(() {
        _dragDy = 0;
        _settleFrom = 0;
      });
      return;
    }
    _settleFrom = _dragDy;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: _settle,
        builder: (context, child) {
          final double dy = _settle.isAnimating
              ? _settleFrom *
                    (1.0 - MotionTokens.enter.transform(_settle.value))
              : _dragDy;
          return Transform.translate(
            key: const ValueKey('pull-down-dismiss-transform'),
            offset: Offset(0, dy),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
