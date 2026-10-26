// lib/services/deposit_recovery_service.dart
// =============================================================================
// INTERRUPTED-DEPOSIT RECOVERY (deposit lifecycle, PR #202 item 1)
//
// A Moolre fiat deposit is a two-party flow: the app initiates (backend
// persists a PENDING TransactionHistory row with a unique txHash), Moolre
// pushes a PIN prompt to the payer's phone, and settlement arrives by
// webhook + socket. If the app dies between initiation and settlement
// there was NO way back onto that ONE transaction: the socket event was
// missed, the reference lived only in the dead screen's memory, and the
// only honest guidance was "look at your ledger and hope".
//
// This service resolves a persisted payment reference (the backend's
// unique txHash, `MOOLRE_DEP_...`) to the durable state of its deposit:
//
//   Step 1 - GET /api/finance/transactions?q=<reference>
//            The finance history search (live on backend main) returns
//            full ledger rows. The row whose txHash EQUALS the persisted
//            reference is the interrupted deposit. A contains-match is
//            NOT enough - the query is a substring search and another
//            deposit's hash can contain the same characters.
//
//   Step 2 - GET /api/deposit/fiat/status/<transactionId>   (Backend F,
//            backend PR #375, independent). The status endpoint keys on
//            the ledger row id, which the initiate contract never
//            returns - the history row is the only owned, honest bridge
//            between the reference the app persisted and the id the
//            endpoint needs. When the endpoint is absent (a backend
//            without #375) the lookup degrades gracefully: the ledger
//            row alone still tells the truth.
//
// The service is READ-ONLY: it re-observes persisted state, never
// mutates, never re-instructs, never invents. Demo mode never reaches
// it (no backend exists there).
// =============================================================================
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';

enum DepositRecoveryStatus {
  /// Settled while the user was away. The wallet was credited; the UI
  /// shows the confirmed end state.
  settled,

  /// The instruction is still live at the provider. The user may still
  /// approve it on their phone, or it expires unapproved.
  pending,

  /// The provider reported failure. Honest outcome: start a new quote.
  failed,

  /// Money moved but is under dispute review. The user must NOT be
  /// nudged to re-initiate; the dispute flow owns it from here.
  frozen,

  /// The reference resolved to nothing the caller owns. No claim is
  /// made in either direction - the form starts fresh.
  unknown,
}

class DepositRecoveryOutcome {
  const DepositRecoveryOutcome({
    required this.status,
    this.transactionId,
    this.continuation,
  });

  final DepositRecoveryStatus status;

  /// The canonical ledger row id - the key Backend F's status endpoint
  /// accepts, resolved here from the payment reference.
  final String? transactionId;

  /// Backend F's continuation payload (provider, amountGhs,
  /// quoteExpiresAt, rateAtInitiation, payerPhoneMasked, providerRef)
  /// when the endpoint is present and the deposit is still in flight.
  /// Null is honest: the ledger row already told the truth.
  final Map<String, dynamic>? continuation;

  bool get isLive =>
      status == DepositRecoveryStatus.pending ||
      status == DepositRecoveryStatus.frozen;
}

class DepositRecoveryService {
  const DepositRecoveryService(this._client);
  final ApiClient _client;

  /// Resolve one persisted payment reference to its durable deposit
  /// state. Never throws for honest server answers; every failure maps
  /// to [DepositRecoveryStatus.unknown] - the caller starts fresh
  /// rather than trusting a guess.
  Future<DepositRecoveryOutcome> recover(String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) {
      return const DepositRecoveryOutcome(
          status: DepositRecoveryStatus.unknown);
    }

    // -- Step 1: reference -> ledger row --------------------------------
    // The history search is a CONTAINS search over txHash/providerRef;
    // only an exact txHash match is this deposit.
    final http.Response? history;
    try {
      history = await _client.get(
          '/finance/transactions?q=${Uri.encodeQueryComponent(ref)}&limit=5');
    } catch (_) {
      return const DepositRecoveryOutcome(
          status: DepositRecoveryStatus.unknown);
    }
    if (history.statusCode != 200) {
      return const DepositRecoveryOutcome(
          status: DepositRecoveryStatus.unknown);
    }

    Map<String, dynamic>? row;
    try {
      final body = jsonDecode(history.body);
      if (body is Map<String, dynamic> && body['transactions'] is List) {
        for (final t in body['transactions'] as List) {
          if (t is Map<String, dynamic> && t['txHash']?.toString() == ref) {
            row = t;
            break;
          }
        }
      }
    } catch (_) {
      return const DepositRecoveryOutcome(
          status: DepositRecoveryStatus.unknown);
    }
    if (row == null) {
      // Not found is an honest answer, not an error: the row may have
      // been pruned, or the draft outlived the deposit. Claim nothing.
      return const DepositRecoveryOutcome(
          status: DepositRecoveryStatus.unknown);
    }

    final rowId = row['id']?.toString();
    switch (row['status']?.toString()) {
      case 'COMPLETED':
        return DepositRecoveryOutcome(
          status: DepositRecoveryStatus.settled,
          transactionId: rowId,
        );
      case 'FAILED':
        return DepositRecoveryOutcome(
          status: DepositRecoveryStatus.failed,
          transactionId: rowId,
        );
      case 'PENDING':
      case 'FROZEN_DISPUTE':
        final frozen = row['status']?.toString() == 'FROZEN_DISPUTE';
        return DepositRecoveryOutcome(
          status: frozen
              ? DepositRecoveryStatus.frozen
              : DepositRecoveryStatus.pending,
          transactionId: rowId,
          continuation: await _continuation(rowId),
        );
      default:
        // An unrecognised status is never mapped onto a claim.
        return const DepositRecoveryOutcome(
            status: DepositRecoveryStatus.unknown);
    }
  }

  /// -- Step 2: Backend F's continuation payload, if the endpoint and
  /// the row id exist. Absent endpoint (404) and foreign/unknown ids
  /// degrade to null - the ledger row already answered honestly.
  Future<Map<String, dynamic>?> _continuation(String? rowId) async {
    if (rowId == null || rowId.isEmpty) return null;
    try {
      final resp = await _client
          .get('/deposit/fiat/status/${Uri.encodeComponent(rowId)}');
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic> && body['success'] == true) {
        final c = body['continuation'];
        if (c is Map<String, dynamic>) return Map<String, dynamic>.from(c);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
