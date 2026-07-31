// =============================================================================
// AZAMAN — SHARED-AXIS PAGE TRANSITIONS  (Phase 13)
//
// Uses the `animations` package's SharedAxisTransition for top-level
// tab routes (Home / Chats / Marketplace / Wallet / Profile) so
// navigating between tabs feels like moving along a horizontal axis —
// Material Design's "shared-axis horizontal" pattern.
//
// Modal/sheet-like pushes should keep using MaterialPageRoute with a
// bottom-sheet-style transition instead of this — don't apply one
// transition to every route or hierarchy cues get lost.
//
// Usage in app_router.dart:
//   GoRoute(
//     path: '/marketplace',
//     pageBuilder: (context, state) => sharedAxisPage(
//       key: state.pageKey,
//       child: const MarketplaceScreen(),
//     ),
//   ),
// =============================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';

/// Horizontal shared-axis transition for same-level navigation
/// (tab-to-tab, list-to-detail within a tab).
CustomTransitionPage<T> sharedAxisPage<T>({
  required LocalKey key,
  required Widget child,
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: type,
        child: child,
      );
    },
  );
}

/// Vertical shared-axis for drill-down within a tab
/// (e.g. Marketplace → Order Tracking)
CustomTransitionPage<T> sharedAxisVerticalPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return sharedAxisPage<T>(key: key, child: child, type: SharedAxisTransitionType.vertical);
}

/// Scaled shared-axis for modal-like full-screen routes
/// (e.g. Media Viewer)
CustomTransitionPage<T> sharedAxisScaledPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return sharedAxisPage<T>(key: key, child: child, type: SharedAxisTransitionType.scaled);
}
