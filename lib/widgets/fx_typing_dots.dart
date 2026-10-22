// =============================================================================
// FX TYPING DOTS — the honest unresolved-value placeholder
//
// A restrained three-dot "typing" indicator: three small dots that rise and
// fall in a staggered cycle, like WhatsApp's typing indicator. It occupies a
// value slot while that value is still UNRESOLVED — e.g. the GHS equivalent
// on the Home balance card while the FX rate has not loaded — instead of a
// fabricated `GH₵ 0.00` or an "unavailable" caption.
//
// It is NEVER a stand-in for a genuine loaded zero: a real 0.00 that has
// loaded is a truthful figure and renders as a figure.
//
// Accessibility / motion contract:
//  * The widget paints no text; hosts wrap it in a Semantics node naming
//    what is loading (see the Home balance card).
//  * Reduced motion: honours MediaQuery.disableAnimations — the dots sit
//    still (the controller is stopped, so no uncontrolled ticker runs).
//  * Offstage: the single ticker belongs to this State's
//    SingleTickerProviderStateMixin, so it is automatically muted whenever
//    TickerMode is disabled (the host face flipped away or offstage).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

class FxTypingDots extends StatefulWidget {
  const FxTypingDots({
    super.key,
    this.color,
    this.dotSize = 4.0,
    this.rise = 3.0,
    this.dotGap = 3.0,
    this.cycle = const Duration(milliseconds: 1080),
    this.stagger = 0.16,
  });

  /// Dot color (the dot modulates its own alpha as it rises). Defaults to
  /// the ambient DefaultTextStyle color — hosts pass their palette's
  /// tertiary ink.
  final Color? color;

  /// Diameter of each dot.
  final double dotSize;

  /// How far (px) each dot rises at the top of its bump. Small on purpose:
  /// the indicator waits quietly inside an existing value slot.
  final double rise;

  /// Horizontal gap between dots.
  final double dotGap;

  /// Length of one full cycle across all three dots.
  final Duration cycle;

  /// Phase delay between consecutive dots, as a fraction of the cycle.
  final double stagger;

  @override
  State<FxTypingDots> createState() => _FxTypingDotsState();
}

class _FxTypingDotsState extends State<FxTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _animating = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.cycle)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _animating) {
      _ctrl
        ..stop()
        ..value = 0;
      _animating = false;
    } else if (!reduceMotion && !_animating) {
      _ctrl.repeat();
      _animating = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink =
        widget.color ?? DefaultTextStyle.of(context).style.color ?? Colors.grey;
    const dotCount = 3;
    final gap = widget.dotGap;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < dotCount; i++)
            Padding(
              padding: EdgeInsets.only(right: i == dotCount - 1 ? 0 : gap),
              child: _Dot(
                bump: _bumpFor(i),
                size: widget.dotSize,
                rise: widget.rise,
                color: ink,
              ),
            ),
        ],
      ),
    );
  }

  /// 0→1→0 bump for dot [i]: mostly resting, briefly rising — the dot is at
  /// full height for a moment, not half the cycle.
  double _bumpFor(int i) {
    if (!_animating) return 0;
    final phase = (_ctrl.value + i * widget.stagger) % 1.0;
    final wave = math.sin(phase * 2 * math.pi);
    if (wave <= 0) return 0;
    // Quartic falloff keeps the bump narrow and gentle.
    return wave * wave * wave * wave;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.bump,
    required this.size,
    required this.rise,
    required this.color,
  });

  final double bump;
  final double size;
  final double rise;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -rise * bump),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The resting dot is slightly dimmer; it brightens as it rises.
          color: color.withValues(alpha: color.a * (0.55 + 0.45 * bump)),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
