// =============================================================================
// AzamanBiometricGate — opt-in biometric pre-gate for financial actions
// =============================================================================
//
// Wraps any high-risk callback (slide-to-confirm fire, withdraw submit,
// trade release, etc.) so the action is gated by Face ID / Touch ID /
// device passcode whenever the user has enabled biometric lock in
// settings. If the user has *not* enabled it, the action runs as normal —
// the gate is a no-op. This keeps the flow opt-in (the user has to deliberately
// turn the lock on; we never force biometrics on devices that don't have one
// enrolled).
//
// Why a top-level helper and not a widget wrapper?
//   - SlideToConfirm.onConfirmed is `VoidCallback`, not `Future<void>`. Wrapping
//     each callsite at the widget level would force every caller to refactor.
//   - The gate has to short-circuit (skip) when biometric is disabled, which
//     is awkward to do at the widget level without prop-drilling state.
//   - A function call at the top of `onConfirmed: () { ... }` is one line
//     of change per callsite and reads exactly like the audit prescribes:
//     "biometric prompt before slide-to-confirm fires."
//
// Failure handling: if the user cancels the prompt or the device returns false,
// we show a brief snackbar so the user understands why the action didn't fire,
// then bail. We do NOT fall through to the action — that would be a security
// regression.
//
// Slide-reset on cancel: callsites that drive `SlideToConfirm` should pass a
// `onCancelled` closure that calls `_sliderKey.currentState?.reset()`. The
// slider commits to `_confirmed = true` the moment a swipe completes, so on
// auth-cancel the user would otherwise be stuck looking at a fully-dragged
// thumb that no longer responds. Resetting the slider re-arms it for retry.
// The closure is optional — non-slider callers (raw button taps) leave it
// null.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/services/biometric_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class AzamanBiometricGate {
  AzamanBiometricGate._();

  /// Runs [action] only if the biometric pre-gate passes. If the user has
  /// not enabled biometric lock in settings, [action] runs immediately.
  ///
  /// If biometric IS enabled and the prompt succeeds, [action] runs.
  /// If the prompt fails or is cancelled, we show a brief snackbar, fire
  /// [onCancelled] if provided (so any visual state — like a snapped
  /// SlideToConfirm thumb — can re-arm), and bail. [action] never fires.
  ///
  /// Returns true if [action] was executed, false otherwise.
  ///
  /// Pass [reason] to override the default "Authenticate to authorize this
  /// transaction" message shown in the system biometric prompt. Useful for
  /// distinguishing "Authenticate to release crypto" from "Authenticate to
  /// withdraw to MoMo" in the user-visible prompt.
  static Future<bool> run(
    BuildContext context,
    Future<void> Function() action, {
    String? reason,
    VoidCallback? onCancelled,
  }) async {
    final svc = BiometricService();
    final isEnabled = await svc.isEnabled;

    if (!isEnabled) {
      // Opt-in model: the user hasn't turned on biometric lock, so we trust
      // the slide gesture itself as confirmation.
      await action();
      return true;
    }

    // The user has enabled biometric lock — gate the action.
    final available = await svc.isAvailable;
    if (!available) {
      // User has the toggle on but the device no longer has biometrics
      // available (e.g., they removed all enrolled fingerprints after enabling).
      // Rather than block them out of every financial action forever, fall
      // through and run the action — but warn them to re-check settings.
      if (context.mounted) {
        _showSnack(
          context,
          'Biometrics unavailable on this device. Re-check Settings → Biometric lock.',
        );
      }
      await action();
      return true;
    }

    final ok = await svc.authenticate(reason: reason);
    if (!ok) {
      if (context.mounted) {
        AzamanHaptics.warn();
        _showSnack(context, 'Authentication failed. Action cancelled.');
      }
      // Re-arm any slide-to-confirm widget that committed before the gate.
      onCancelled?.call();
      return false;
    }

    // Biometric passed — fire the action.
    await action();
    return true;
  }

  /// Synchronous-style helper for callsites that already have a `VoidCallback`
  /// onConfirmed and don't want to refactor to async. Internally awaits the
  /// gate but the caller doesn't have to.
  static void runSync(
    BuildContext context,
    VoidCallback action, {
    String? reason,
    VoidCallback? onCancelled,
  }) {
    run(
      context,
      () async => action(),
      reason: reason,
      onCancelled: onCancelled,
    );
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
