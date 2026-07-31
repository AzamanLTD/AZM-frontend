// =============================================================================
// AZAMAN — MOTION TOKENS  (Phase 13)
//
// Central motion constants. Every new animation in the app should pull
// duration/curve from here instead of hand-picking numbers — this is
// what makes the whole app feel like one coherent system instead of a
// patchwork of screens built in different sprints.
//
// Calibrated against WhatsApp/Telegram/iOS system feel.
// =============================================================================

import 'package:flutter/animation.dart';

class MotionTokens {
  const MotionTokens._();

  // ── Durations ────────────────────────────────────────────────────────
  /// Micro: button press, tick toggle, chip select — 120ms
  static const microInteraction = Duration(milliseconds: 120);
  /// Standard: sheet open, card expand, bottom bar appear — 220ms
  static const standard = Duration(milliseconds: 220);
  
  /// Fast — micro-interactions (button press, toggle, tap feedback)
  static const fast = Duration(milliseconds: 100);
  /// Emphasized: screen transition, hero, page push — 350ms
  static const emphasized = Duration(milliseconds: 350);
  /// Ambient: typing dots, shimmer loop, breathing — 900ms
  static const ambient = Duration(milliseconds: 900);

  // ── Curves ───────────────────────────────────────────────────────────
  /// Things arriving on screen
  static const enter = Curves.easeOutCubic;
  /// Things leaving the screen
  static const exit = Curves.easeInCubic;
  /// Playful settle — swipe-to-reply, cart bar, bounce-in
  static const spring = Curves.easeOutBack;
  /// Symmetric transitions (open/close, expand/collapse)
  static const standardCurve = Curves.easeInOutCubic;

  // ── Stagger ──────────────────────────────────────────────────────────
  /// Interval between list-entrance animations (checkout rows, onboarding)
  static const staggerStep = Duration(milliseconds: 40);
}
