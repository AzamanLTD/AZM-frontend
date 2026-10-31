// AZAMAN — HOME BUBBLE PRESS CHOREOGRAPHY
//
// The copy of the interaction this widget owns, in order:
//
//   REST  →  1.0, idle.
//   PRESS →  1.0 → 0.93 in 90ms on tap-down. Contact, not a slide.
//   POP   →  0.93 → 1.06 → 1.0 in 170ms on tap-up. The navigation is fired at
//            the crest of the overshoot, so the Hero flight leaves while the
//            bubble is still moving outward. Popping and then waiting for the
//            scale to settle reads as two separate events; handing off at the
//            crest reads as one.
//
// Two things this widget refuses to do:
//
//   • Push twice. A second tap while the pop is still travelling is swallowed,
//     so a double tap cannot queue two navigations (or two Hero flights on the
//     same tag).
//   • Push a bubble that was not pressed to completion. Dragging off the
//     bubble cancels: the scale returns to rest and nothing navigates.
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
    duration: MotionTokens.control,
  );

  /// The rebound itself: compressed → crest → rest, ending EXACTLY at 1.0 so
  /// the bubble cannot be left sitting slightly small after a navigation.
  late final Animation<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: widget.pressScale,
        end: widget.popScale,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      // Fast rise to the crest.
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: widget.popScale,
        end: 1.0,
      ).chain(CurveTween(curve: MotionTokens.spring)),
      // A settle that comes back through rest rather than easing into it.
      weight: 60,
    ),
  ]).animate(_pop);

  /// True between a tap-up and the navigation it will fire, so a second tap in
  /// that window cannot start a rival push.
  bool _fired = false;

  @override
  void dispose() {
    _press.dispose();
    _pop.dispose();
    super.dispose();
  }

  double _scale() {
    // Compression is the finger; the pop is the release. They never blend: a
    // rebound starts from the compressed depth, so mixing them would launch
    // from wherever the press happened to stop.
    if (_pop.isDismissed) {
      return 1 - ((1 - widget.pressScale) * _press.value);
    }
    return _popScale.value;
  }

  void _down(TapDownDetails _) {
    if (_fired) return;
    AzamanHaptics.selection();
    _press.forward();
  }

  void _up(TapUpDetails _) {
    if (_fired) return;
    _fired = true;
    _pop.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      _fired = false;
      _press.value = 0;
      _pop.value = 0;
    });
    // Hand off at the crest rather than after the settle: the Hero is already
    // carrying this bubble's size by then.
    widget.onTap();
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
