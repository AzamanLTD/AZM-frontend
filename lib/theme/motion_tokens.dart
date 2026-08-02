// =============================================================================
// AZAMAN — MOTION TOKENS  (Phase I.1)
//
// Central motion constants. Every new animation in the app should pull
// duration/curve from here instead of hand-picking numbers — this is
// what makes the whole app feel like one coherent system instead of a
// patchwork of screens built in different sprints.
//
// Calibrated against WhatsApp/Telegram/iOS system feel.
// =============================================================================

import 'package:flutter/widgets.dart';

abstract class MotionTokens {
  // ── DURATIONS ────────────────────────────────────────────────────────
  /// 120ms: button press feedback, checkbox toggle, tick icon swap
  static const microInteraction = Duration(milliseconds: 120);

  /// Alias for microInteraction (backward compat)
  static const fast = microInteraction;

  /// 220ms: card expand, modal sheet entrance, badge pop
  static const standard = Duration(milliseconds: 220);

  /// 350ms: screen transition, hero element, container transform
  static const emphasized = Duration(milliseconds: 350);

  /// 900ms: typing indicator dots loop, shimmer sweep, ambient glow pulse
  static const ambient = Duration(milliseconds: 900);

  /// 1200ms: celebration/success animation (rare, high-value moments only)
  static const celebration = Duration(milliseconds: 1200);

  // ── CURVES ───────────────────────────────────────────────────────────
  /// Things arriving on screen (list items, toasts, sheets appearing)
  static const enter = Curves.easeOutCubic;

  /// Things leaving screen (dismiss, close, fade out)
  static const exit = Curves.easeInCubic;

  /// Playful settle with slight overshoot (swipe-to-reply spring back,
  /// cart bottom bar entrance, badge pop)
  static const spring = Curves.easeOutBack;

  /// Symmetric in-out (tab transitions, card flips, container transforms)
  static const symmetric = Curves.easeInOutCubic;

  /// Alias for symmetric (backward compat)
  static const standardCurve = symmetric;

  /// Deceleration for "heavy" things landing (payment confirmation modal)
  static const decelerate = Curves.decelerate;

  // ── STAGGER ──────────────────────────────────────────────────────────
  /// 40ms stagger between list items (checkout price rows, search results)
  static const staggerStep = Duration(milliseconds: 40);

  /// Maximum stagger delay — cap so a 20-item list doesn't take 800ms
  static const staggerMax = Duration(milliseconds: 300);

  static Duration staggerDelay(int index, {int cap = 8}) {
    return staggerStep * index.clamp(0, cap);
  }
}

/// Checks the system reduced-motion preference and, if true, returns zero
/// duration (skip to end state).
extension ReducedMotion on MotionTokens {
  static Duration respectReducedMotion(BuildContext context, Duration normal) {
    return MediaQuery.of(context).disableAnimations ? Duration.zero : normal;
  }
}
