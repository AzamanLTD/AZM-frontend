// =============================================================================
// AZAMAN — HAPTIC LANGUAGE  (Phase H)
//
// One named pattern per intent. Replaces ad-hoc `HapticFeedback.lightImpact`
// scattered across the codebase with a five-rung vocabulary that's
// consistent app-wide:
//
//   AzamanHaptics.nav()      — every navigation tap (push, bottom-nav,
//                              row tile, drawer item). LIGHT feel.
//   AzamanHaptics.toggle()   — switch flips, tab switches, picker
//                              selections. Soft selectionClick feel.
//   AzamanHaptics.confirm()  — every "this commits something" action
//                              (sign in, submit form, accept trade,
//                              tap a savings goal). MEDIUM feel.
//   AzamanHaptics.commit()   — final commit on a financial action that
//                              has just succeeded (slide-to-confirm
//                              fires, withdrawal sent, transfer sent).
//                              HEAVY feel.
//   AzamanHaptics.warn()     — error states, danger confirmations
//                              (sign-out confirm, dispute open). HEAVY
//                              double-tap feel.
//
// Why a named layer instead of using `HapticFeedback.*` directly?
//
//   * One place to globally turn it off if a user disables haptics in
//     Settings (the existing `settingsProvider.haptics` flag — wire-in
//     follow-up in Phase H2).
//   * One place to hide the platform fall-back: HapticFeedback only
//     produces output on real devices; on simulators/desktop we want
//     a no-op rather than an exception. (`HapticFeedback` already
//     no-ops, but the named layer makes future swap to `vibration`
//     package trivial — that package is already in pubspec).
//   * Premium fintech apps speak in haptic *vocabulary*, not raw
//     impacts. This file *is* the vocabulary.
// =============================================================================

import 'package:flutter/services.dart';

class AzamanHaptics {
  const AzamanHaptics._();

  /// Light tap — every navigation push / row tile / bottom-nav switch.
  static Future<void> nav() {
    return HapticFeedback.lightImpact();
  }

  /// Selection click — toggles, switches, picker pulls.
  static Future<void> toggle() {
    return HapticFeedback.selectionClick();
  }

  /// Medium tap — primary CTA, submit, accept.
  static Future<void> confirm() {
    return HapticFeedback.mediumImpact();
  }

  /// Heavy tap — final commit on a financial action.
  static Future<void> commit() {
    return HapticFeedback.heavyImpact();
  }

  /// Light tap — success feedback (payment sent, order placed, goal reached).
  static Future<void> success() {
    return HapticFeedback.lightImpact();
  }

  /// Heavy double-tap — error / danger / unrecoverable confirm.
  /// Dart's HapticFeedback has no native "double" pulse, so we fire
  /// a heavy + a delayed second heavy. ~140ms gap reads as "two beats".
  static Future<void> warn() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.heavyImpact();
  }
}
