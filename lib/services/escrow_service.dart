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

class EscrowService {
  final ApiClient _client;
  EscrowService() : _client = ApiClient();

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
  Future<SmartEscrow> fundEscrow(String escrowId) =>
      _mutate('/escrow/fund', {'escrowId': escrowId});

  /// POST /escrow/satisfy {escrowId} — returns whether the escrow is now fully
  /// settled (both parties satisfied) plus the latest escrow snapshot.
  Future<({bool settled, SmartEscrow escrow})> markSatisfied(
      String escrowId) async {
    final res = await _client.post('/escrow/satisfy', {'escrowId': escrowId});
    final body = jsonDecode(res.body);
    final escrow = _unwrap(body, res.statusCode);
    return (settled: body['settled'] == true, escrow: escrow);
  }

  /// POST /escrow/dispute {escrowId, reason, evidenceUrls?}
  Future<SmartEscrow> raiseDispute({
    required String escrowId,
    required String reason,
    List<String> evidenceUrls = const [],
  }) {
    return _mutate('/escrow/dispute', {
      'escrowId': escrowId,
      'reason': reason,
      if (evidenceUrls.isNotEmpty) 'evidenceUrls': evidenceUrls,
    });
  }

  /// POST /escrow/update-terms {escrowId, deliveryTerms}
  Future<SmartEscrow> updateTerms(String escrowId, String deliveryTerms) =>
      _mutate('/escrow/update-terms', {
        'escrowId': escrowId,
        'deliveryTerms': deliveryTerms,
      });

  /// POST /escrow/cancel {escrowId}
  Future<void> cancelEscrow(String escrowId) async {
    final res = await _client.post('/escrow/cancel', {'escrowId': escrowId});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throwFrom(res.body, res.statusCode, 'Cancel failed');
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<SmartEscrow> _mutate(String path, Map<String, dynamic> body) async {
    final res = await _client.post(path, body);
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
