// AZAMAN — MEMBER MONEY ACCESS (app-wide privacy gate)
//
// LOCKED is the initial state, set synchronously in the field initialiser so
// the very first frame can never paint a balance. It is a LOCAL privacy gate:
// it hides money behind the member's own device authentication. It does not
// replace backend authorisation, KYC, server-side 2FA, limits or idempotency.
//
// Attempts are generation-checked: a late result from an abandoned attempt
// (cancelled, backgrounded, logged out, re-locked) can never unlock the app.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MoneyAccessState { locked, authenticating, unlocked }

class MoneyAccessController extends ChangeNotifier {
  MoneyAccessState _state = MoneyAccessState.locked;
  int _generation = 0;

  MoneyAccessState get state => _state;

  bool get canViewMoney => _state == MoneyAccessState.unlocked;

  bool get isLocked => _state == MoneyAccessState.locked;

  bool get isAuthenticating => _state == MoneyAccessState.authenticating;

  /// Relock. Bumping the generation invalidates any in-flight attempt, so a
  /// biometric sheet that resolves after this call cannot unlock anything.
  void lock() {
    _generation++;
    if (_state == MoneyAccessState.locked) return;
    _state = MoneyAccessState.locked;
    notifyListeners();
  }

  /// Begin an unlock attempt and return its generation token.
  int beginUnlock() {
    _generation++;
    _state = MoneyAccessState.authenticating;
    notifyListeners();
    return _generation;
  }

  bool isCurrentAttempt(int attempt) =>
      attempt == _generation && _state == MoneyAccessState.authenticating;

  void finishUnlock(int attempt) {
    if (!isCurrentAttempt(attempt)) return;
    _state = MoneyAccessState.unlocked;
    notifyListeners();
  }

  void cancelUnlock(int attempt) {
    if (!isCurrentAttempt(attempt)) return;
    _state = MoneyAccessState.locked;
    notifyListeners();
  }
}

final moneyAccessProvider = ChangeNotifierProvider<MoneyAccessController>(
  (ref) => MoneyAccessController(),
);
