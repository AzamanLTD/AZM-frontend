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
import 'package:azaman/utils/idempotency_key.dart';

class EscrowService {
  final ApiClient _client;
  EscrowService() : _client = ApiClient();

  // r42 key lifecycle: one Idempotency-Key per LOGICAL action, not per call.
  // Armed on the first attempt and REUSED across retries of the same action
  // (a lost response may mean the server committed — a fresh key would
  // execute the money move twice). The service instance is held by its
  // notifier, so the armed key survives across user taps.
  final _fundKey = LogicalActionKey();
  final _satisfyKey = LogicalActionKey();
  final _disputeKey = LogicalActionKey();
  final _cancelKey = LogicalActionKey();

  /// Drives a mutating call with the correct key lifecycle:
  ///   - answered success → retire (this action is complete; a new action
  ///     mints a fresh key);
  ///   - answered failure ≠ 409 → retire (a corrected retry is a new
  ///     action);
  ///   - 409 (same action in flight / replay conflict) → KEEP, the retry
  ///     converges on the server-side operation;
  ///   - no server answer (network error / auth failure) → KEEP, the retry
  ///     MUST reuse the same key.
  Future<T> _withActionKey<T>(
      LogicalActionKey key, Future<T> Function(String key) call) async {
    try {
      final result = await call(key.arm());
      key.retire();
      return result;
    } on EscrowServiceException catch (e) {
      if (e.statusCode != 409) key.retire();
      rethrow;
    }
    // Anything else (network error, timeout, auth-level ApiException) never
    // carries a server answer about the action — keep the key armed.
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
  Future<SmartEscrow> fundEscrow(String escrowId) => _withActionKey(
      _fundKey,
      (key) => _mutate('/escrow/fund', {'escrowId': escrowId},
          idempotencyKey: key));

  /// POST /escrow/satisfy {escrowId} — returns whether the escrow is now fully
  /// settled (both parties satisfied) plus the latest escrow snapshot.
  Future<({bool settled, SmartEscrow escrow})> markSatisfied(
          String escrowId) =>
      _withActionKey(_satisfyKey, (key) async {
        // r42: satisfaction commits the release — same key-lifecycle rule.
        final res = await _client.postFinancial('/escrow/satisfy',
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
    return _withActionKey(_disputeKey, (key) {
      return _mutate('/escrow/dispute', {
        'escrowId': escrowId,
        'reason': reason,
        if (evidenceUrls.isNotEmpty) 'evidenceUrls': evidenceUrls,
      }, idempotencyKey: key);
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
      _withActionKey(_cancelKey, (key) async {
        // r42: cancellation releases funds — same key-lifecycle rule.
        final res = await _client.postFinancial(
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
    final res = await (idempotencyKey == null
        ? _client.post(path, body)
        : _client.postFinancial(path, body, idempotencyKey: idempotencyKey));
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
