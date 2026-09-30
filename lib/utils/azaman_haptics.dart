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

// TASK-026: the single global haptics off-switch lives in AzSensory.
import 'package:azaman/providers/sensory_provider.dart';
import 'package:vibration/vibration.dart';

class AzamanHaptics {
  const AzamanHaptics._();

  // ── THE GATE (TASK-026) ──────────────────────────────────────────────
  //
  // This file's own header promised a single global off-switch. This is it.
  // `AzSensory.hapticsEnabled` is written by exactly one place —
  // `SensoryProvider._commit` — and defaults to true, so behaviour is
  // unchanged until a user opts out in Settings.
  //
  // Every public method below must call `_allowed` first. A method that
  // skips the gate is a bug: it would vibrate for a user who asked for none.
  static bool get _allowed => AzSensory.hapticsEnabled;

  /// Light tap — every navigation push / row tile / bottom-nav switch.
  static Future<void> nav() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// Selection click — toggles, switches, picker pulls.
  static Future<void> toggle() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.selectionClick();
  }

  /// Medium tap — primary CTA, submit, accept.
  static Future<void> confirm() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.mediumImpact();
  }

  /// Heavy tap — final commit on a financial action.
  static Future<void> commit() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.heavyImpact();
  }

  /// Light tap — success feedback (payment sent, order placed, goal reached).
  static Future<void> success() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// Heavy double-tap — error / danger / unrecoverable confirm.
  /// Dart's HapticFeedback has no native "double" pulse, so we fire
  /// a heavy + a delayed second heavy. ~140ms gap reads as "two beats".
  static Future<void> warn() async {
    if (!_allowed) return Future<void>.value();
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.heavyImpact();
  }

  // ── SELECTION & THRESHOLD ─────────────────────────────────────────────

  /// Alias of [toggle]. Preferred name in new code.
  static Future<void> selection() {
    if (!_allowed) return Future<void>.value();
    return toggle();
  }

  /// Alias of [nav]. Preferred name in new code — the bottom nav and the
  /// radial launcher (TASK-018) both speak in "navigation taps".
  static Future<void> navigation() {
    if (!_allowed) return Future<void>.value();
    return nav();
  }

  /// A gesture crossed its commit point mid-drag — pull-to-refresh armed,
  /// swipe-to-reply armed, drag-to-dismiss armed.
  ///
  /// IMPORTANT: fire this EXACTLY ONCE per crossing, not on every frame past
  /// the threshold. A repeating threshold tick reads as a broken sensor.
  static Future<void> threshold() {
    if (!_allowed) return Future<void>.value();
    return HapticFeedback.mediumImpact();
  }

  // ── OUTCOMES ──────────────────────────────────────────────────────────

  /// A financial value landed — payment sent, deposit cleared, escrow released,
  /// trade settled.
  ///
  /// The "thunk-tick": a heavy beat immediately followed by a lighter one. It
  /// reads as weight landing and then settling, which is exactly the mental
  /// model of money arriving. Falls back to a single heavy beat on devices with
  /// no vibrator.
  static Future<void> moneyLanded() async {
    if (!_allowed) return Future<void>.value();
    try {
      final hasVibrator = (await Vibration.hasVibrator()) == true;
      if (hasVibrator) {
        await Vibration.vibrate(
          pattern: <int>[0, 42, 62, 22],
          intensities: <int>[0, 200, 0, 96],
        );
        return;
      }
    } catch (_) {
      // Feature detection failed (platform channel unavailable) — fall through
      // to the HapticFeedback path rather than surfacing an error.
    }
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 62));
    await HapticFeedback.lightImpact();
  }

  /// An item was added to a tray — two quick beats that read as a "clack".
  /// Used by retail `liftIntoTray` and restaurant `paperRip` commits.
  static Future<void> addToCart() async {
    if (!_allowed) return Future<void>.value();
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await HapticFeedback.lightImpact();
  }

  /// Selecting the [index]-th seat (0-based). Intensity RISES with the index so
  /// that selecting a row of seats feels like an ascending scale — the user
  /// physically feels how many they have chosen.
  ///
  /// Index is clamped to 0..3; beyond the fourth seat the sensation stays at
  /// heavy so the pattern does not become a machine-gun.
  static Future<void> seatSelected(int index) {
    if (!_allowed) return Future<void>.value();
    switch (index.clamp(0, 3)) {
      case 0:
        return HapticFeedback.selectionClick();
      case 1:
        return HapticFeedback.lightImpact();
      case 2:
        return HapticFeedback.mediumImpact();
      default:
        return HapticFeedback.heavyImpact();
    }
  }

  /// A high-value moment — vault goal hit, AZM reward received, susu cycle
  /// completed. Two ascending beats over ~120ms.
  ///
  /// Used sparingly by design: if this fires more than a few times a week the
  /// user stops noticing it, and it stops being a reward.
  static Future<void> celebration() async {
    if (!_allowed) return Future<void>.value();
    try {
      final hasVibrator = (await Vibration.hasVibrator()) == true;
      if (hasVibrator) {
        await Vibration.vibrate(
          pattern: <int>[0, 30, 90, 60],
          intensities: <int>[0, 128, 0, 220],
        );
        return;
      }
    } catch (_) {
      // Fall through.
    }
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.lightImpact();
  }

  /// Kept for backward compatibility with the retired duplicate vocabulary.
  /// Prefer [celebration] in new code.
  static Future<void> celebrationPulse() {
    if (!_allowed) return Future<void>.value();
    return celebration();
  }

  /// Kept for backward compatibility. Prefer [moneyLanded] in new code.
  static Future<void> moneyMoved() {
    if (!_allowed) return Future<void>.value();
    return moneyLanded();
  }

  // ── FAILURE ───────────────────────────────────────────────────────────

  /// Alias of [warn]. Preferred name in new code.
  static Future<void> warning() {
    if (!_allowed) return Future<void>.value();
    return warn();
  }

  /// A failure the user must notice — a decline, a validation failure, a
  /// failed network commit. Same shape as [warn] but slightly faster, so it
  /// reads as "rejected" rather than as "are you sure?".
  static Future<void> error() async {
    if (!_allowed) return Future<void>.value();
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }
}
