// =============================================================================
// AZAMAN — TYPED ACTIVITY ACTIONS  (NEW-HOME §13)
//
// Activity items become interactive with EXPLICIT action semantics. The
// activity model carries the metadata; the UI renders the action from
// structured data. Actions are NEVER inferred from arbitrary title strings
// — [ActivityActionResolver] maps the structured `rawType` + the richer
// transaction metadata only, and an unknown/unsupported action falls back
// safely to the details surface.
//
// Audit contracts enforced here:
//   * SEND AGAIN is only valid when AUTHORITATIVE counterparty/recipient
//     metadata exists in the record (TransactionRecord.counterparty and
//     friends). A display title is never a recipient. Incoming transfers
//     are never Send Again — only a deliberate outbound peer transfer is.
//   * The resolved action carries an explicit payload (the recipient's
//     AZM ID + name) into the send flow; nothing is re-derived downstream.
//   * Raw backend types are normalised at THIS boundary (the resolver),
//     and the UI consumes only the typed [ActivityAction].
//   * Unknown or incomplete activity data → Details. Never guess.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/transaction_history_provider.dart';
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

  /// Structured route payload (e.g. a trade id) when the record carries one.
  final String? reference;

  /// For sendAgain: the AUTHORITATIVE recipient, copied from the record's
  /// counterparty metadata — never derived from a display title. Null
  /// means the action is not offered at all.
  final ActivityRecipient? recipient;

  const ActivityAction(this.type, {this.reference, this.recipient});

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

/// The authoritative recipient payload a Send Again action carries into the
/// send flow. Built ONLY from transaction metadata (counterparty /
/// recipientName / recipientAzamId etc.), never from a title.
class ActivityRecipient {
  /// The recipient's AZM ID — the lookup key the send flow validates
  /// against the backend before any money moves.
  final String azamanId;

  /// Display name (username or full name) when metadata carries one.
  final String displayName;

  const ActivityRecipient({required this.azamanId, required this.displayName});
}

/// Explicit, structured mapping from the record's own `rawType` and
/// metadata — never the title string. Unknown kinds, and records whose
/// action needs a payload the record does not carry, resolve to the safe
/// Details fallback.
class ActivityActionResolver {
  const ActivityActionResolver._();

  /// The authoritative recipient for a Send Again, from metadata only.
  /// Null when no AZM ID / name can be resolved — and then the action is
  /// NOT offered.
  static ActivityRecipient? _recipientFrom(TransactionRecord t) {
    final meta = t.metadata ?? const <String, dynamic>{};
    final azamId =
        meta['recipientAzamId']?.toString() ?? meta['counterpartyAzamId']?.toString() ?? '';
    if (azamId.isEmpty) return null;
    final name = meta['recipientName']?.toString() ??
        meta['counterparty']?.toString() ??
        azamId;
    return ActivityRecipient(azamanId: azamId, displayName: name);
  }

  static const _sendAgainTypes = <String>{
    'INTERNAL_TRANSFER',
    'SMART_ROUTE_RUN',
  };

  static ActivityAction resolve(TransactionRecord t) {
    final kind = t.rawType.toUpperCase();

    // SEND AGAIN — the strictest contract in the file:
    //   1. only deliberate OUTBOUND peer transfers qualify (never credits:
    //      an incoming transfer is not a "send again" without a product
    //      contract saying so);
    //   2. the authoritative recipient must exist in the metadata — a
    //      display title never counts;
    //   3. the payload is carried explicitly into the action.
    if (_sendAgainTypes.contains(kind)) {
      if (_amountIsOutbound(t)) {
        final recipient = _recipientFrom(t);
        if (recipient != null) {
          return ActivityAction(ActivityActionType.sendAgain,
              recipient: recipient);
        }
      }
      // Outbound transfer without an authoritative recipient, or an
      // incoming transfer: Details. Never guess who to send to.
      return const ActivityAction(ActivityActionType.viewDetails);
    }

    if (kind.contains('SUSU')) {
      final susuId = t.metadata?['susuGroupId']?.toString();
      if (susuId != null && susuId.isNotEmpty) {
        return ActivityAction(ActivityActionType.viewSusu,
            reference: susuId);
      }
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
      final ref = t.metadata?['tradeId']?.toString() ?? t.providerRef;
      if (ref != null && ref.isNotEmpty) {
        return ActivityAction(ActivityActionType.viewTrade, reference: ref);
      }
      return const ActivityAction(ActivityActionType.viewDetails);
    }
    return const ActivityAction(ActivityActionType.viewDetails);
  }

  /// Direction test: positive amounts are inflow (credit), negative are
  /// outflow. Records normalised to absolute amounts (some backends do)
  /// fall back to an explicit metadata direction flag when present.
  static bool _amountIsOutbound(TransactionRecord t) {
    final direction = t.metadata?['direction']?.toString().toLowerCase();
    if (direction == 'out' || direction == 'outbound') return true;
    if (direction == 'in' || direction == 'inbound') return false;
    return t.amountUsdc < 0;
  }

  /// Dispatches a resolved action. Never guesses: an action whose payload
  /// is missing falls back to the details screen.
  static void dispatch(BuildContext context, TransactionRecord t) {
    final action = resolve(t);
    switch (action.type) {
      case ActivityActionType.sendAgain:
        AzamanHaptics.nav();
        // The recipient payload is explicit — the send flow receives the
        // authoritative AZM ID, it does not re-derive anything.
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    SendMoneyScreen(initialRecipient: action.recipient)));
      case ActivityActionType.viewSusu:
        AzamanHaptics.nav();
        if (action.reference != null) {
          context.push('/susu/${action.reference}');
        } else {
          context.push('/susu');
        }
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
