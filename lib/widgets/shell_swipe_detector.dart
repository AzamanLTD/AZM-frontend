// =============================================================================
// AZAMAN — SHELL SWIPE DETECTOR (PR-B)
//
// The deliberate horizontal swipe that moves between the shell's three
// primary destinations (Home ↔ Chat ↔ Marketplace).
//
// It is NOT a PageView and owns NO navigation state: it only recognises
// a deliberate horizontal drag and reports the adjacent-direction step
// (+1 = content follows finger left → next index; −1 = swipe right →
// previous index). The shell's own tab-selection contract
// ([_MainWrapperState._onNavItemSelected]) executes it, so the active
// tab, shell bus, launcher state, compression reset, ticker budget and
// retap behaviour all stay in one place.
//
// Arena honesty — this is an ANCESTOR HorizontalDragGestureRecognizer:
//   * any deeper horizontal gesture (nested carousels, the
//     ProfileJoystick — which wins the arena at pointer-down —, sliders,
//     text fields) joins the arena FIRST and beats it;
//   * a vertical scroll keeps its vertical-dominant claim (a vertical
//     drag never commits here);
//   * [enabled] = false suspends commits (the shell uses this while the
//     + launcher owns the screen) without touching arena participation;
//   * a cancelled swipe fires nothing — there is no drag-following
//     visual state, so nothing needs unwinding (reduced motion: the
//     shell's own transition plays its control-tempo variant).
//
// No edge treatment of any kind: Android's system edge-back stays
// entirely the platform's. There is deliberately no wrap-around at the
// shell's boundaries — that clamping belongs to the shell, which knows
// the index range.
// =============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A deliberate horizontal swipe across the shell's body.
///
/// Wraps the shell's page stack. [onAdjacentSwipe] receives +1 when the
/// user's committed swipe moves content LEFT (reveal the destination to
/// the right), and −1 for a rightward swipe. Anything below the
/// deliberate thresholds ([commitDistance] travel, or a real
/// [flingVelocity] in the same direction) fires nothing.
class ShellSwipeDetector extends StatefulWidget {
  const ShellSwipeDetector({
    super.key,
    required this.child,
    required this.onAdjacentSwipe,
    this.enabled = true,
    this.commitDistance = 56.0,
    this.flingVelocity = 350.0,
  });

  final Widget child;

  /// +1 for a leftward (next-destination) swipe, −1 for a rightward
  /// (previous-destination) swipe. Only deliberate swipes reach it.
  final ValueChanged<int> onAdjacentSwipe;

  /// Whether committed swipes dispatch. Suspended while a modal
  /// (the + launcher) owns the shell's screen.
  final bool enabled;

  /// Minimum horizontal travel (logical px) for a deliberate swipe.
  final double commitDistance;

  /// Minimum fling velocity (logical px/s) for a committed flick, with
  /// any non-trivial same-direction travel.
  final double flingVelocity;

  @override
  State<ShellSwipeDetector> createState() => _ShellSwipeDetectorState();
}

class _ShellSwipeDetectorState extends State<ShellSwipeDetector> {
  /// Accumulated horizontal travel of the in-flight swipe.
  double _swipeDx = 0.0;

  void _onSwipeStart(DragStartDetails _) {
    _swipeDx = 0.0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeDx += details.primaryDelta ?? 0.0;
  }

  void _onSwipeEnd(DragEndDetails details) {
    final dx = _swipeDx;
    _swipeDx = 0.0;
    if (!widget.enabled) return;
    final v = details.primaryVelocity ?? 0.0;
    // Deliberate = far enough, or a real fling in the same direction.
    // Content follows the finger: a LEFT swipe reveals the destination
    // to the RIGHT (next index) — the PageView convention, without the
    // PageView.
    if (dx <= -widget.commitDistance ||
        (dx < 0 && v <= -widget.flingVelocity)) {
      widget.onAdjacentSwipe(1);
    } else if (dx >= widget.commitDistance ||
        (dx > 0 && v >= widget.flingVelocity)) {
      widget.onAdjacentSwipe(-1);
    }
    // Anything else: no commit, no state left behind.
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // deferToChild (the default): a pure arena participant — children
      // are never blocked, they merely win the arena first.
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.trackpad,
                },
              ),
              (HorizontalDragGestureRecognizer recognizer) => recognizer
                ..onStart = _onSwipeStart
                ..onUpdate = _onSwipeUpdate
                ..onEnd = _onSwipeEnd,
            ),
      },
      child: widget.child,
    );
  }
}
