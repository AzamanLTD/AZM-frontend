// =============================================================================
// AZAMAN — REDUCED MOTION WRAPPER  (Phase 13)
//
// Honor's Flutter's accessibility setting `MediaQuery.disableAnimations`.
// When the user has "Remove Animations" enabled in system accessibility
// settings, every AzAnimatedSwitcher skips to end-state instantly.
//
// This wrapper is the single place that checks the flag so individual
// screens don't each have to remember — consistent behavior app-wide.
//
// Usage:
//   AzAnimatedSwitcher(
//     duration: MotionTokens.standard,
//     child: Text(value, key: ValueKey(value)),
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

class AzAnimatedSwitcher extends StatelessWidget {
  final Duration duration;
  final Widget child;
  final Widget? previousChild;
  final Widget Function(Widget, Animation<double>)? transitionBuilder;

  const AzAnimatedSwitcher({
    super.key,
    required this.duration,
    required this.child,
    this.previousChild,
    this.transitionBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    if (disableAnimations) {
      // Skip animation entirely — just show the current child
      return child;
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: MotionTokens.enter,
      switchOutCurve: MotionTokens.exit,
      transitionBuilder: transitionBuilder ?? ((child, animation) {
        return FadeTransition(opacity: animation, child: child);
      }),
      child: child,
    );
  }
}

/// A wrapper that respects reduced motion for slide + fade entrances.
/// When reduced motion is on, the child appears instantly.
class AzSlideFadeIn extends StatelessWidget {
  final Duration duration;
  final Offset beginOffset;
  final Widget child;

  const AzSlideFadeIn({
    super.key,
    this.duration = MotionTokens.standard,
    this.beginOffset = const Offset(0, 0.1),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    if (disableAnimations) {
      return child;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: MotionTokens.enter,
      builder: (context, value, _) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset.lerp(beginOffset, Offset.zero, value) ?? Offset.zero,
            child: child,
          ),
        );
      },
    );
  }
}
