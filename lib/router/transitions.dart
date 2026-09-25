// =============================================================================
// AZAMAN — SHARED-AXIS PAGE TRANSITIONS  (Phase I.2)
//
// Uses the `animations` package's SharedAxisTransition for GoRouter routes.
// Three transition types based on navigation hierarchy:
//   - horizontal: same-level navigation (tab content, list → detail)
//   - fadeThrough: tab switching (home → chat → marketplace)
//   - vertical: sheet-like pushes (checkout, payment confirmation)
//
// All transitions respect reduced-motion (skip to end state).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';

/// Shared-axis horizontal: for same-level navigation (tab content,
/// list → detail within a section). Matches Material Design guidance
/// for "lateral" navigation and mirrors iOS UINavigationController feel.
CustomTransitionPage<T> horizontalPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        child: child,
      );
    },
  );
}

/// Fade-through: for tab switching (home → chat → marketplace).
/// Slower than horizontal push because tab transitions should feel "ambient"
/// not "directional."
CustomTransitionPage<T> fadeThroughPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
  );
}

/// Shared-axis vertical: for sheet-like pushes (checkout, payment confirmation).
/// Feels layered — the new screen arrives from below, like a bottom sheet
/// becoming full-screen. Distinct from horizontal so the user knows "this is
/// a layer, not a new section."
CustomTransitionPage<T> verticalPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.vertical,
        child: child,
      );
    },
  );
}

// ── Legacy aliases (kept for existing app_router.dart references) ────────────
/// Horizontal shared-axis transition for same-level navigation
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
      if (MediaQuery.of(context).disableAnimations) return child;
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
CustomTransitionPage<T> sharedAxisVerticalPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return sharedAxisPage<T>(key: key, child: child, type: SharedAxisTransitionType.vertical);
}

/// Scaled shared-axis for modal-like full-screen routes
CustomTransitionPage<T> sharedAxisScaledPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return sharedAxisPage<T>(key: key, child: child, type: SharedAxisTransitionType.scaled);
}
