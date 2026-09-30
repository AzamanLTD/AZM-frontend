// =============================================================================
// AZAMAN — ROUTE TRANSITION FAMILIES  (NEW-A, Step 2)
//
// Exactly THREE semantic families, one vocabulary for the whole app:
//
//   traverse — moving ACROSS major sections or deeper in the spatial
//              hierarchy. The old screen slides out as the new one slides
//              in on the same axis. (Replaces sharedAxisPage horizontal.)
//
//   rise     — drill-down / detail / payment-style transitions that
//              conceptually RISE from a lower layer: checkout, queues,
//              confirmations. The new screen arrives from below like a
//              sheet becoming a page. (Replaces sharedAxisVerticalPage and
//              sharedAxisScaledPage — a scaled axis reads as a layer
//              arriving, which is 'rise', not 'traverse'.)
//
//   morph    — reserved for TRUE same-object transformations where the
//              destination is the continuation of an object already
//              visible on screen. No route uses it yet: the NEW-J
//              Hero/artifact system owns real morphs. This family exists
//              so NEW-J lands as a route-level vocabulary, not as
//              ad-hoc per-route transitions. Until then it renders as the
//              shortest, calmest cross-fade in the system (a morph must
//              never feel like a page change).
//
// All durations/curves come from MotionTokens — no ad-hoc ms values.
// Reduced motion (MediaQuery.disableAnimations) is authoritative for every
// family: the page renders its end state with no transition.
// =============================================================================

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Traverse: lateral movement across the hierarchy — shared-axis horizontal.
///
/// Duration: MotionTokens.standard (220ms). Enters on MotionTokens.enter,
/// exits on MotionTokens.exit.
CustomTransitionPage<T> traversePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: MotionTokens.standard,
    reverseTransitionDuration: MotionTokens.standard,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return SharedAxisTransition(
        animation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: animation,
        ),
        secondaryAnimation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: secondaryAnimation,
        ),
        transitionType: SharedAxisTransitionType.horizontal,
        child: child,
      );
    },
  );
}

/// Rise: the destination rises from a lower layer — shared-axis vertical.
///
/// Duration: MotionTokens.emphasized (350ms): layered pushes cover more
/// visual distance, and the old vertical family's cadence is preserved.
CustomTransitionPage<T> risePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: MotionTokens.emphasized,
    reverseTransitionDuration: MotionTokens.emphasized,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return SharedAxisTransition(
        animation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: animation,
        ),
        secondaryAnimation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: secondaryAnimation,
        ),
        transitionType: SharedAxisTransitionType.vertical,
        child: child,
      );
    },
  );
}

/// Morph: same-object continuation. RESERVED for NEW-J's Hero/artifact
/// system — no route should claim this family for ordinary navigation.
///
/// Duration: MotionTokens.fast (120ms) — a morph is a continuation, not a
/// page change; if the user can measure the transition, it is too long.
CustomTransitionPage<T> morphPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: MotionTokens.fast,
    reverseTransitionDuration: MotionTokens.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return FadeThroughTransition(
        animation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: animation,
        ),
        secondaryAnimation: CurvedAnimation(
          curve: MotionTokens.enter,
          reverseCurve: MotionTokens.exit,
          parent: secondaryAnimation,
        ),
        child: child,
      );
    },
  );
}
