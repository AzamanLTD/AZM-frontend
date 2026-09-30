// =============================================================================
// AZAMAN — TYPED ACTIVITY ACTIONS  (NEW-HOME §13)
//
// Activity items become interactive with EXPLICIT action semantics. The
// activity model carries the metadata; the UI renders the action from
// structured data. Actions are NEVER inferred from arbitrary title strings
// — [ActivityActionResolver] maps the structured `rawType` only, and an
// unknown/unsupported action falls back safely to the details surface.
//
// Home's summary model (TransactionSummary) gains `rawType` + `reference`
// fields in this task so the resolver has real metadata to read.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';

enum ActivityActionType {
  sendAgain,
  viewSusu,
  viewDeposit,
  viewWithdrawal,
  viewTrade,
  viewDetails,
}

class ActivityAction {
  final ActivityActionType type;

  /// Structured route payload (e.g. a trade id) when the summary carries one.
  final String? reference;
  const ActivityAction(this.type, {this.reference});

  String get label {
    switch (type) {
      case ActivityActionType.sendAgain:
        return 'Send again';
      case ActivityActionType.viewSusu:
        return 'View Susu';
      case ActivityActionType.viewDeposit:
        return 'View deposit';
      case ActivityActionType.viewWithdrawal:
        return 'View withdrawal';
      case ActivityActionType.viewTrade:
        return 'View trade';
      case ActivityActionType.viewDetails:
        return 'Details';
    }
  }
}

/// Explicit, structured mapping from the activity's own `rawType` — never
/// the title string. Unknown kinds resolve to the safe details fallback.
class ActivityActionResolver {
  const ActivityActionResolver._();

  static ActivityAction resolve(TransactionSummary t) {
    final kind = (t.rawType).toUpperCase();

    if (kind.contains('SUSU')) {
      return const ActivityAction(ActivityActionType.viewSusu);
    }
    if (kind.contains('DEPOSIT')) {
      return const ActivityAction(ActivityActionType.viewDeposit);
    }
    if (kind.contains('WITHDRAW')) {
      return const ActivityAction(ActivityActionType.viewWithdrawal);
    }
    if (kind.contains('TRADE') || kind.contains('P2P')) {
      // Only a REAL trade reference can open the trade route; without one
      // the safe fallback is the details surface (§13 "never guess").
      if (t.reference != null && t.reference!.isNotEmpty) {
        return ActivityAction(ActivityActionType.viewTrade,
            reference: t.reference);
      }
      return const ActivityAction(ActivityActionType.viewDetails);
    }
    if (kind.contains('SEND') || kind.contains('TRANSFER')) {
      return const ActivityAction(ActivityActionType.sendAgain);
    }
    return const ActivityAction(ActivityActionType.viewDetails);
  }

  /// Dispatches a resolved action. Never guesses: an action whose payload
  /// is missing falls back to the details screen.
  static void dispatch(BuildContext context, TransactionSummary t) {
    final action = resolve(t);
    switch (action.type) {
      case ActivityActionType.sendAgain:
        AzamanHaptics.nav();
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SendMoneyScreen()));
      case ActivityActionType.viewSusu:
        AzamanHaptics.nav();
        context.push('/susu');
      case ActivityActionType.viewDeposit:
        AzamanHaptics.nav();
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const DepositScreen(
                    initialTab: DepositTab.fiat)));
      case ActivityActionType.viewWithdrawal:
        AzamanHaptics.nav();
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WithdrawalScreen()));
      case ActivityActionType.viewTrade:
        AzamanHaptics.nav();
        if (action.reference != null) {
          context.push('/trade/${action.reference}');
        } else {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AccountActivityScreen()));
        }
      case ActivityActionType.viewDetails:
        AzamanHaptics.nav();
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AccountActivityScreen()));
    }
  }
}
