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
//   * Raw backend types are normalised at THIS boundary
//     ([ActivityKindNormalizer] → [ActivityRecordKind]) and the UI
//     consumes only the typed enum + typed [ActivityAction] — no
//     substring inference anywhere downstream.
//   * Unknown or incomplete activity data → Details. Never guess.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/router/route_registry.dart';
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
/// The normalised transaction kind (audit §5): raw backend type strings
/// are mapped to a CLOSED enum at THIS boundary — the single seam between
/// the backend's type vocabulary and the UI. [ActivityActionResolver]
/// switches on the enum only; an unmappable type normalises to
/// [ActivityRecordKind.other], whose action is always Details.
enum ActivityRecordKind {
  transfer,
  susu,
  deposit,
  withdrawal,
  trade,
  other,
}

class ActivityKindNormalizer {
  const ActivityKindNormalizer._();

  /// Exact backend enums — the authoritative vocabulary. New backend
  /// enums belong HERE first; the token table is the compatibility
  /// fallback, not the primary path.
  static const _exactKinds = <String, ActivityRecordKind>{
    'INTERNAL_TRANSFER': ActivityRecordKind.transfer,
    'SMART_ROUTE_RUN': ActivityRecordKind.transfer,
    'DEPOSIT_FIAT': ActivityRecordKind.deposit,
    'DEPOSIT_CRYPTO': ActivityRecordKind.deposit,
    'WITHDRAWAL_FIAT': ActivityRecordKind.withdrawal,
    'WITHDRAWAL_CRYPTO': ActivityRecordKind.withdrawal,
  };

  /// Documented token fallback for backend enums added before the
  /// frontend enumerates them. Explicit, ordered, and confined to this
  /// normalizer — string shapes are never inspected in UI code.
  static const _tokenKinds = <String, ActivityRecordKind>{
    'SUSU': ActivityRecordKind.susu,
    'DEPOSIT': ActivityRecordKind.deposit,
    'WITHDRAW': ActivityRecordKind.withdrawal,
    'TRADE': ActivityRecordKind.trade,
    'P2P': ActivityRecordKind.trade,
  };

  static ActivityRecordKind normalize(String rawType) {
    final k = rawType.toUpperCase();
    final exact = _exactKinds[k];
    if (exact != null) return exact;
    for (final token in _tokenKinds.keys) {
      if (k.contains(token)) return _tokenKinds[token]!;
    }
    return ActivityRecordKind.other;
  }

  /// UX-CORRECTION §7: does this raw backend type belong on the HOME
  /// financial-activity surface? The surface shows "things that happened
  /// to my money/account" — mapped, explicitly supported economic types
  /// only. An unmapped/unknown type is EXCLUDED from this surface (it is
  /// not presented as mysterious activity); the full transaction history
  /// screen remains the place where every record is visible.
  static bool isSupportedOnHome(String rawType) =>
      normalize(rawType) != ActivityRecordKind.other;
}

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

  static ActivityAction resolve(TransactionRecord t) {
    // AUDIT §5: the UI consumes a CLOSED enum. Raw backend type strings
    // are normalised exactly once, at this boundary; nothing downstream
    // infers an action from string shapes.
    switch (ActivityKindNormalizer.normalize(t.rawType)) {
      case ActivityRecordKind.transfer:
        // SEND AGAIN — the strictest contract in the file:
        //   1. only deliberate OUTBOUND peer transfers qualify (never
        //      credits: an incoming transfer is not a "send again"
        //      without a product contract saying so);
        //   2. the authoritative recipient must exist in the metadata — a
        //      display title never counts;
        //   3. the payload is carried explicitly into the action.
        if (t.isOutbound) {
          final recipient = _recipientFrom(t);
          if (recipient != null) {
            return ActivityAction(ActivityActionType.sendAgain,
                recipient: recipient);
          }
        }
        // Outbound transfer without an authoritative recipient, or an
        // incoming transfer: Details. Never guess who to send to.
        return const ActivityAction(ActivityActionType.viewDetails);
      case ActivityRecordKind.susu:
        final susuId = t.metadata?['susuGroupId']?.toString();
        if (susuId != null && susuId.isNotEmpty) {
          return ActivityAction(ActivityActionType.viewSusu,
              reference: susuId);
        }
        return const ActivityAction(ActivityActionType.viewSusu);
      case ActivityRecordKind.deposit:
        return const ActivityAction(ActivityActionType.viewDeposit);
      case ActivityRecordKind.withdrawal:
        return const ActivityAction(ActivityActionType.viewWithdrawal);
      case ActivityRecordKind.trade:
        // Only a REAL trade reference can open the trade route; without
        // one the safe fallback is the details surface (§13 "never guess").
        final ref = t.metadata?['tradeId']?.toString() ?? t.providerRef;
        if (ref != null && ref.isNotEmpty) {
          return ActivityAction(ActivityActionType.viewTrade, reference: ref);
        }
        return const ActivityAction(ActivityActionType.viewDetails);
      case ActivityRecordKind.other:
        // Unmappable type: Details. Never guess.
        return const ActivityAction(ActivityActionType.viewDetails);
    }
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
        // CANONICAL ROUTE: /deposit already builds DepositScreen with the
        // fiat default (its builder passes no initialTab), so this push
        // preserves the existing behavior while going through the router.
        context.push(AzRoutes.deposit());
      case ActivityActionType.viewWithdrawal:
        AzamanHaptics.nav();
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WithdrawalScreen()));
      case ActivityActionType.viewTrade:
        AzamanHaptics.nav();
        if (action.reference != null) {
          context.push(AzRoutes.trade(action.reference!));
        } else {
          // No trade reference → the safe fallback surface is the
          // canonical activity screen, reached through the router.
          context.push(AzRoutes.accountActivity);
        }
      case ActivityActionType.viewDetails:
        AzamanHaptics.nav();
        // CANONICAL ROUTE: the activity details surface is /account/activity
        // (NEW-A) — never a bare MaterialPageRoute.
        context.push(AzRoutes.accountActivity);
    }
  }
}
