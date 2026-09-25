// =============================================================================
// AZAMAN — ANIMATED NUMBER  (Phase 13)
//
// Smoothly counts between numeric values when they change — the kind of
// "ticking up" balance animation you see in Revolut, Cash App, and Robinhood.
//
// Respects reduced-motion (instantly jumps to target when disabled).
//
// Usage:
//   AnimatedNumber(
//     value: balance,
//     formatter: (v) => '${v.toStringAsFixed(2)} USDC',
//     style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

class AnimatedNumber extends StatefulWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration? duration;
  final Curve? curve;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration,
    this.curve,
  });

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _animation;
  double _oldValue = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration ?? MotionTokens.standard,
    );
    _animation = AlwaysStoppedAnimation(widget.value);
    _oldValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant AnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (MediaQuery.of(context).disableAnimations) {
        _animation = AlwaysStoppedAnimation(widget.value);
      } else {
        _ctrl.reset();
        _animation = Tween<double>(
          begin: _oldValue,
          end: widget.value,
        ).animate(CurvedAnimation(
          parent: _ctrl,
          curve: widget.curve ?? MotionTokens.standardCurve,
        ));
        _ctrl.forward();
      }
      _oldValue = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animation is AlwaysStoppedAnimation<double>) {
      return Text(widget.formatter(widget.value), style: widget.style);
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Text(
          widget.formatter(_animation.value),
          style: widget.style,
        );
      },
    );
  }
}
