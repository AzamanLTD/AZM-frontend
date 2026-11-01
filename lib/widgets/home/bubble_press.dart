// AZAMAN — HOME BUBBLE PRESS CHOREOGRAPHY
//
// The copy of the interaction this widget owns, in order:
//
//   REST  →  1.0, idle.
//   PRESS →  1.0 → 0.93 over 90ms on tap-down. Contact, not a slide.
//   POP   →  whatever the press reached → 1.06 → 1.0 over 180ms on tap-up.
//   PUSH  →  the navigation fires AT THE CREST of the pop, so the Hero flight
//            begins while the bubble is still expanding outward. Popping and
//            then navigating reads as one event; navigating on the same frame
//            as the release reads as a flat tap with an unrelated animation
//            afterwards, which is what this file used to do.
//
// The pop starts from the compression the finger actually achieved, not from
// the fully-pressed depth. A 15ms flick releases at ~0.98; restarting the pop
// at 0.93 there would snap the bubble smaller before it grew, which is the
// discontinuity a fast tap produced.
//
// Two things this widget refuses to do:
//
//   • Push twice. A second tap while the pop is travelling is swallowed, so a
//     double tap cannot queue two navigations (or two flights on one Hero tag).
//   • Push a bubble that was not pressed to completion. Dragging off cancels:
//     the scale returns to rest and nothing navigates.
//
// Reduced motion (MediaQuery.disableAnimations) skips the scale entirely and
// calls onTap on tap, because a deferred action with no visible cause is worse
// than no animation at all.
import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class BubblePress extends StatefulWidget {
  const BubblePress({
    super.key,
    required this.onTap,
    required this.child,
    this.pressScale = 0.93,
    this.popScale = 1.06,
  });

  final VoidCallback onTap;
  final Widget child;

  /// How far the bubble compresses under the finger.
  final double pressScale;

  /// The crest of the rebound, just before the Hero takes over.
  final double popScale;

  @override
  State<BubblePress> createState() => _BubblePressState();
}

class _BubblePressState extends State<BubblePress>
    with TickerProviderStateMixin {
  /// 0 → 1 while the finger holds the bubble down.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: MotionTokens.instantFeedback,
  );

  /// 0 → 1 across the rebound and settle.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// The scale the pop started from: the compression the finger reached.
  double _popStart = 1.0;

  /// Fraction of the pop devoted to the rise. The rest is the settle back.
  static const double _riseShare = 0.4;

  /// True between a tap-up and the navigation it will fire, so a second tap in
  /// that window cannot start a rival push.
  bool _fired = false;

  /// True once the navigation has actually been handed to the caller.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _pop.addListener(_fireAtCrest);
    _pop.addStatusListener(_onPopStatus);
  }

  @override
  void dispose() {
    _pop.removeListener(_fireAtCrest);
    _pop.removeStatusListener(_onPopStatus);
    _press.dispose();
    _pop.dispose();
    super.dispose();
  }

  double _compressed() => 1 - ((1 - widget.pressScale) * _press.value);

  /// The scale to draw. While the pop is running it is the pop curve; before
  /// that it is the finger's compression.
  double _scale() {
    if (_pop.isDismissed) return _compressed();
    final t = _pop.value;
    if (t < _riseShare) {
      final k = Curves.easeOutCubic.transform(t / _riseShare);
      return _popStart + (widget.popScale - _popStart) * k;
    }
    final k = Curves.easeOutCubic.transform(
      (t - _riseShare) / (1 - _riseShare),
    );
    return widget.popScale + (1.0 - widget.popScale) * k;
  }

  /// The navigation leaves with the bubble at its widest, not on the release
  /// frame. Every tick before the crest is silent.
  void _fireAtCrest() {
    if (_navigated || _pop.value < _riseShare) return;
    _navigated = true;
    widget.onTap();
  }

  void _onPopStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Rest exactly, so a completed pop can never leave the bubble slightly
    // small (and the next gesture starts from a known state).
    _fired = false;
    _navigated = false;
    _popStart = 1.0;
    _press.value = 0;
    _pop.value = 0;
  }

  void _down(TapDownDetails _) {
    if (_fired) return;
    AzamanHaptics.selection();
    _press.forward();
  }

  void _up(TapUpDetails _) {
    if (_fired) return;
    _fired = true;
    _popStart = _compressed();
    _pop.forward(from: 0);
  }

  void _cancel() {
    if (_fired) return;
    _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_press, _pop]),
        builder: (context, child) {
          return Transform.scale(
            // Named so a test can read the ONE transform this control owns
            // rather than guessing which Transform in the tree it is.
            key: const ValueKey<String>('bubble_press_scale'),
            scale: _scale(),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
