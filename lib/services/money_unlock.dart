// AZAMAN — MONEY UNLOCK COORDINATION
//
// One place decides which member-verified challenge unlocks the local money
// gate. Only methods the app can genuinely satisfy today are offered:
//
//   * device authentication (local_auth: enrolled biometrics, with the
//     platform's own device-credential fallback) — available now;
//   * Azaman PIN, authenticator (TOTP) and SMS OTP — NOT wired here. They
//     need backend contracts the client must not invent, so they report
//     [MoneyUnlockOutcome.unavailable] instead of pretending to work.
//
// A method is never presented as available merely because a settings screen
// exists for it.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/biometric_service.dart';

enum MoneyUnlockOutcome { unlocked, failed, cancelled, unavailable }

@immutable
class MoneyUnlockResult {
  const MoneyUnlockResult(this.outcome, {this.message});

  final MoneyUnlockOutcome outcome;
  final String? message;

  bool get isSuccess => outcome == MoneyUnlockOutcome.unlocked;
}

abstract class MoneyUnlockCoordinator {
  /// Whether this device can run this challenge at all (enrolled biometrics or
  /// a platform device credential). Never a guess about the member's account.
  Future<bool> get isAvailable;

  /// Challenge the member. Must never mutate app state itself: the caller
  /// owns the generation-checked transition.
  Future<MoneyUnlockResult> authenticate();
}

class DeviceAuthUnlockCoordinator implements MoneyUnlockCoordinator {
  DeviceAuthUnlockCoordinator({BiometricService? service})
    : _service = service ?? BiometricService();

  final BiometricService _service;

  @override
  Future<bool> get isAvailable => _service.isAvailable;

  @override
  Future<MoneyUnlockResult> authenticate() async {
    if (!await _service.isAvailable) {
      return const MoneyUnlockResult(
        MoneyUnlockOutcome.unavailable,
        message: 'Set up a screen lock on this device to unlock Azaman.',
      );
    }
    final ok = await _service.authenticate(reason: 'Unlock your Azaman money');
    return ok
        ? const MoneyUnlockResult(MoneyUnlockOutcome.unlocked)
        : const MoneyUnlockResult(
            MoneyUnlockOutcome.failed,
            message: 'Not verified. Your money stays locked.',
          );
  }
}

/// The coordinator the app uses. Tests override this provider.
final moneyUnlockCoordinatorProvider = Provider<MoneyUnlockCoordinator>(
  (ref) => DeviceAuthUnlockCoordinator(),
);
