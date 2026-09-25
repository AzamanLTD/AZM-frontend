// =============================================================================
// AZAMAN — SCALE TAP MICRO-INTERACTION  (Phase 13)
//
// A tappable container that scales down ~3% on press with spring physics,
// creating a satisfying "press" micro-interaction. Respects reduced-motion
// (skips scale when MediaQuery.disableAnimations is true).
//
// Designed for cards, buttons, tiles — anything tappable that should feel
// alive. Pairs well with AzamanHaptics for combined haptic + visual feedback.
//
// Usage:
//   ScaleTap(
//     onTap: () { ... },
//     child: MyCard(),
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

class ScaleTap extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final double scaleDown;
  final Duration? duration;

  const ScaleTap({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
    this.scaleDown = 0.97,
    this.duration,
  });

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration ?? MotionTokens.fast,
    );
    _scale = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (MediaQuery.of(context).disableAnimations) return;
    _ctrl.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    _ctrl.reverse();
  }

  void _handleTapCancel() {
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
