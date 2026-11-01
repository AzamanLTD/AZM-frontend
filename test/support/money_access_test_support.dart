import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/money_access_provider.dart';

/// Starts a suite with money UNLOCKED.
///
/// Use this only where the subject under test is the card or another money
/// surface itself; the privacy gate has its own suites and must stay locked by
/// default everywhere else. It goes through the controller's real API (begin,
/// then finish with that attempt) so the override cannot express a state the
/// production controller could never reach.
Override unlockedMoneyAccess() => moneyAccessProvider.overrideWith((ref) {
  final controller = MoneyAccessController();
  final attempt = controller.beginUnlock();
  controller.finishUnlock(attempt);
  return controller;
});
