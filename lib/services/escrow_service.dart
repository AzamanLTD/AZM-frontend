// =============================================================================
// ESCROW SERVICE — Flutter V3 Marketplace Sprint (2026-06-21)
//
// REST client for the Smart Escrow engine (mounted at /api/escrow). Mirrors
// the `TicketService` style: an `ApiClient` held on the instance, `jsonDecode`
// of the body, and a thrown `EscrowServiceException` on any non-2xx status.
//
// Every escrow endpoint responds with `{ success: true, escrow: {...} }`
// (POST /satisfy additionally returns `settled`). We unwrap that envelope and
// return the parsed `SmartEscrow`. `getEscrowForTicket` returns null on 404
// (a ticket may not have an escrow yet).
// =============================================================================

import 'dart:convert';

import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

class EscrowService {
  final ApiClient _client;
  EscrowService() : _client = ApiClient();

  // r42 OPERATION-INSTANCE MODEL: the action ids name the operation TYPES
  // (per-escrow recovery namespaces). Each genuinely new action gets a
  // fresh durable INSTANCE; the per-target refs are the retry handles — a
  // re-call after a lost response RETRIES THE SAME INSTANCE (same key).
  // A lost response followed by process death can no longer fork the
  // identity of an unfinished action: the instance record persists and a
  // matching re-call resumes IT instead of opening a duplicate.
  //
  // The lifecycle nuance (which this service keeps MANUALLY, because the
  // escrow routes are not releaseOn4xx mounts — the backend conservatively
  // RETAINS their claims on 4xx):
  ///   - answered success → retire (this instance is complete);
  ///   - answered failure ≠ 409 → retire (a corrected retry is a new
  ///     action);
  ///   - 409 (same action in flight / replay conflict) → KEEP, the retry
  ///     converges on the server-side operation;
  ///   - no server answer (network error / auth failure) → KEEP, the retry
  ///     MUST reuse the same key.
  final Map<String, FinancialOperationRef> _flowRefs = {};

  Future<T> _withDurableKey<T>({
    required String operationType,
    required String endpoint,
    required Map<String, dynamic> request,
    required Future<T> Function(String key) call,
  }) async {
    // Same instance-resolution policy as ApiClient.postFinancial: retry
    // the flow ref's unfinished instance when the body matches its
    // fingerprint; otherwise begin a GENUINELY NEW instance — the old
    // record is never silently replaced, it stays recoverable.
    final ref = _flowRefs.putIfAbsent(
        operationType, () => FinancialOperationRef());
    final account = await _client.operationAccount(failClosed: true);
    final retryId = ref.operationId;
    DurableOperation op;
    if (retryId != null) {
      try {
        op = await DurableOperationRegistry.retry(retryId,
            account: account, request: request);
      } on DurableOperationException {
        op = await DurableOperationRegistry.begin(
            account: account,
            type: operationType,
            endpoint: endpoint,
            request: request);
      }
    } else {
      op = await DurableOperationRegistry.begin(
          account: account,
          type: operationType,
          endpoint: endpoint,
          request: request);
    }
    ref.operationId = op.operationId;
    try {
      final result = await call(op.key);
      await DurableOperationRegistry.retire(op.operationId, account: account);
      ref.operationId = null;
      return result;
    } on EscrowServiceException catch (e) {
      if (e.statusCode != 409) {
        await DurableOperationRegistry.retire(op.operationId, account: account);
        ref.operationId = null;
      }
      rethrow;
    }
    // Anything else (network error, timeout, auth-level ApiException) never
    // carries a server answer about the action — the durable instance
    // stays pending, so the retry reuses the SAME key.
  }

  /// GET /escrow/ticket/:ticketId — returns null when the ticket has no escrow.
  Future<SmartEscrow?> getEscrowForTicket(String ticketId) async {
    try {
      final res = await _client.get('/escrow/ticket/$ticketId');
      final body = jsonDecode(res.body);
      final escrow = body['escrow'];
      if (escrow is Map<String, dynamic>) {
        return SmartEscrow.fromJson(escrow);
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /escrow/fund {escrowId}
  ///
  /// r42: funding is a money-moving mutation — one Idempotency-Key per
  /// logical fund action, reused across deliberate retries.
  Future<SmartEscrow> fundEscrow(String escrowId) => _withDurableKey(
      operationType: 'escrow.fund.$escrowId',
      endpoint: '/escrow/fund',
      request: {'escrowId': escrowId},
      call: (key) => _mutate('/escrow/fund', {'escrowId': escrowId},
          idempotencyKey: key));

  /// POST /escrow/satisfy {escrowId} — returns whether the escrow is now fully
  /// settled (both parties satisfied) plus the latest escrow snapshot.
  Future<({bool settled, SmartEscrow escrow})> markSatisfied(
          String escrowId) =>
      _withDurableKey(
          operationType: 'escrow.satisfy.$escrowId',
          endpoint: '/escrow/satisfy',
          request: {'escrowId': escrowId},
          call: (key) async {
        // r42: satisfaction commits the release — same key-lifecycle rule.
        final res = await _client.post('/escrow/satisfy',
            {'escrowId': escrowId},
            idempotencyKey: key);
        final body = jsonDecode(res.body);
        final escrow = _unwrap(body, res.statusCode);
        return (settled: body['settled'] == true, escrow: escrow);
      });

  /// POST /escrow/dispute {escrowId, reason, evidenceUrls?}
  Future<SmartEscrow> raiseDispute({
    required String escrowId,
    required String reason,
    List<String> evidenceUrls = const [],
  }) {
    // close-out review 2, finding 3: the STORED snapshot must BE the exact
    // non-secret wire request, so a recovered replay reproduces the
    // original dispute (reason + evidence) under the original key. The
    // stored body previously carried only escrowId, which would have made
    // a recovered replay a materially different request.
    final request = {
      'escrowId': escrowId,
      'reason': reason,
      if (evidenceUrls.isNotEmpty) 'evidenceUrls': evidenceUrls,
    };
    return _withDurableKey(
        operationType: 'escrow.dispute.$escrowId',
        endpoint: '/escrow/dispute',
        request: request,
        call: (key) {
      return _mutate('/escrow/dispute', request, idempotencyKey: key);
    });
  }

  /// POST /escrow/update-terms {escrowId, deliveryTerms}
  Future<SmartEscrow> updateTerms(String escrowId, String deliveryTerms) =>
      _mutate('/escrow/update-terms', {
        'escrowId': escrowId,
        'deliveryTerms': deliveryTerms,
      });

  /// POST /escrow/cancel {escrowId}
  Future<void> cancelEscrow(String escrowId) =>
      _withDurableKey(
          operationType: 'escrow.cancel.$escrowId',
          endpoint: '/escrow/cancel',
          request: {'escrowId': escrowId},
          call: (key) async {
        // r42: cancellation releases funds — same key-lifecycle rule.
        final res = await _client.post(
            '/escrow/cancel', {'escrowId': escrowId},
            idempotencyKey: key);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          _throwFrom(res.body, res.statusCode, 'Cancel failed');
        }
      });

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<SmartEscrow> _mutate(String path, Map<String, dynamic> body,
      {String? idempotencyKey}) async {
    // r42: [idempotencyKey] is set for money-moving mutations on routes
    // the backend protects with the shared idempotency authority; purely
    // editorial routes (update-terms) stay keyless.
    // Keyed path: the key is PRE-ARMED from the durable registry and the
    // lifecycle is managed by the caller (_withDurableKey) — so this goes
    // through post() directly, never minting an identity of its own.
    final res = await (idempotencyKey == null
        ? _client.post(path, body)
        : _client.post(path, body, idempotencyKey: idempotencyKey));
    final decoded = jsonDecode(res.body);
    return _unwrap(decoded, res.statusCode);
  }

  SmartEscrow _unwrap(dynamic body, int statusCode) {
    if (statusCode < 200 || statusCode >= 300 || body is! Map) {
      _throwFrom(body, statusCode, 'Escrow request failed');
    }
    final escrow = body['escrow'];
    if (escrow is! Map<String, dynamic>) {
      throw EscrowServiceException(
        statusCode: statusCode,
        message: body['message']?.toString() ?? 'Malformed escrow response',
      );
    }
    return SmartEscrow.fromJson(escrow);
  }

  Never _throwFrom(dynamic body, int statusCode, String fallback) {
    String message = fallback;
    try {
      final decoded = body is String ? jsonDecode(body) : body;
      if (decoded is Map) {
        message = decoded['message']?.toString() ?? fallback;
      }
    } catch (_) {}
    throw EscrowServiceException(statusCode: statusCode, message: message);
  }
}

class EscrowServiceException implements Exception {
  final int statusCode;
  final String message;
  const EscrowServiceException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}
