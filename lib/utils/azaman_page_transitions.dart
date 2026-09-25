// =============================================================================
// AZAMAN — PAGE TRANSITIONS  (Phase I)
//
// Global PageTransitionsBuilder wired into ThemeData so EVERY existing
// `Navigator.push(MaterialPageRoute(...))` call across the app picks up
// a shared-axis-horizontal style transition automatically — no need to
// rewrite 100+ call sites.
//
// The transition:
//   * Inbound page slides in from the right (6%) + fades in
//   * Outbound page drifts left (4%) + dims slightly
//   * 300ms forward, 250ms reverse (asymmetric — pops feel snappier)
//   * easeOutCubic enter, easeInCubic exit (matches MotionTokens)
//
// Respects reduced-motion: if the user has "remove animations" enabled,
// the page appears instantly with a crossfade only.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

class AzamanPageTransitionsBuilder extends PageTransitionsBuilder {
  const AzamanPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Reduced motion: crossfade only, no slide
    if (MediaQuery.of(context).disableAnimations) {
      return FadeTransition(opacity: animation, child: child);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: MotionTokens.enter,
      reverseCurve: MotionTokens.exit,
    );
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: MotionTokens.enter,
      reverseCurve: MotionTokens.exit,
    );

    // Inbound page: slide from right, fade in
    final slideIn = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(curved);

    // Outgoing page: drift left, dim slightly
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.04, 0),
    ).animate(secondaryCurved);

    final dim = Tween<double>(begin: 1.0, end: 0.92).animate(secondaryCurved);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: dim,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        ),
      ),
    );
  }
}
