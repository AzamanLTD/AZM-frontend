// =============================================================================
// AZAMAN — NAVIGATION TRANSITION HELPERS  (Phase 13)
//
// Wraps Navigator.push with shared-axis transitions matching the GoRouter
// pageBuilder transitions. Use these instead of raw MaterialPageRoute
// for consistent motion across the app.
//
//   pushWithVerticalTransition(context, screen)  — for drill-downs
//   pushWithHorizontalTransition(context, screen) — for peer-level pushes
//   pushWithScaledTransition(context, screen)    — for modal-like sheets
//
// All respect reduced-motion (instant transition when disabled).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Vertical shared-axis transition for drill-down navigation
/// (e.g., tapping into a detail screen from a list).
Future<T?> pushWithVerticalTransition<T extends Object?>(
  BuildContext context,
  Widget screen, {
  bool fullscreenDialog = false,
}) {
  return Navigator.of(context).push<T>(
    _SharedAxisRoute(
      child: screen,
      axis: NavAxis.vertical,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}

/// Horizontal shared-axis transition for peer-level navigation
/// (e.g., moving between related items in a flow).
Future<T?> pushWithHorizontalTransition<T extends Object?>(
  BuildContext context,
  Widget screen, {
  bool fullscreenDialog = false,
}) {
  return Navigator.of(context).push<T>(
    _SharedAxisRoute(
      child: screen,
      axis: NavAxis.horizontal,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}

/// Scaled shared-axis transition for modal-like full-screen pushes
/// (e.g., QR code display, checkout).
Future<T?> pushWithScaledTransition<T extends Object?>(
  BuildContext context,
  Widget screen, {
  bool fullscreenDialog = false,
}) {
  return Navigator.of(context).push<T>(
    _SharedAxisRoute(
      child: screen,
      axis: NavAxis.scaled,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}

enum NavAxis { vertical, horizontal, scaled }

class _SharedAxisRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final NavAxis axis;

  _SharedAxisRoute({
    required this.child,
    required this.axis,
    bool fullscreenDialog = false,
  }) : super(
          fullscreenDialog: fullscreenDialog,
          transitionDuration: MotionTokens.standard,
          reverseTransitionDuration: MotionTokens.fast,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, c) {
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            if (reduceMotion) return c;

            final curve = Curves.easeOutCubic;
            final curved = CurvedAnimation(parent: animation, curve: curve);
            final revCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: curve,
            );

            switch (axis) {
              case NavAxis.vertical:
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(curved),
                    child: FadeTransition(
                      opacity: ReverseAnimation(revCurved),
                      child: c,
                    ),
                  ),
                );
              case NavAxis.horizontal:
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: FadeTransition(
                      opacity: ReverseAnimation(revCurved),
                      child: c,
                    ),
                  ),
                );
              case NavAxis.scaled:
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                    child: FadeTransition(
                      opacity: ReverseAnimation(revCurved),
                      child: c,
                    ),
                  ),
                );
            }
          },
        );
}
