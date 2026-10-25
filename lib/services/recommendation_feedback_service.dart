// lib/services/recommendation_feedback_service.dart
// =============================================================================
// "Show less like this" — typed client for the persistent, user-scoped
// recommendation-suppression contract (AZM-backend PR #373, "Backend D";
// docs/marketplace-recommendation-feedback-contract.md).
//
// Wire contract:
//   POST   /api/recommendation-feedback      201 new / 200 idempotent
//        body { businessProfileId }
//      -> { success, state: "SHOW_LESS", alreadyApplied, appliedAt }
//   DELETE /api/recommendation-feedback/:businessProfileId
//      -> 200 { success, state: "NONE", removed: true|false }  (idempotent)
//   GET    /api/recommendation-feedback/check/:businessProfileId
//      -> 200 { success, applied: boolean }
//   GET    /api/recommendation-feedback?limit=&offset=
//      -> 200 { success, total, suppressed: [ { businessProfileId,
//              feedbackType, appliedAt } ] }  (caller's own rows only)
//
// Honesty rules encoded here:
//  * All identifiers are canonical BusinessProfile.id values — NEVER
//    display "BIZ-..." codes.
//  * POST is idempotent: alreadyApplied:true is a SUCCESS, not an
//    error; the durable end state is SHOW_LESS either way.
//  * DELETE is idempotent: removed:false still means NONE — the row
//    was the only personalisation signal, so removal restores the
//    prior ranking (test-pinned on the backend).
//  * Suppression DEMOTES in the caller's own search ranking; it never
//    removes the business globally and is invisible to other users.
//    The frontend never re-implements demotion — the server owns
//    ranking effects for authenticated viewers.
//  * A 404 on apply means the business id is wrong: the caller must
//    NOT retry and must NOT simulate a local suppression.
// =============================================================================
import 'dart:convert';

import 'package:azaman/services/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class ShowLessApplyResult {
  /// The DURABLE end state after the call (SHOW_LESS on any 2xx).
  final bool showLess;
  final bool alreadyApplied;
  final DateTime? appliedAt;

  const ShowLessApplyResult({
    required this.showLess,
    required this.alreadyApplied,
    this.appliedAt,
  });
}

class ShowLessUndoResult {
  /// The durable end state is NONE on ANY 200 (removed:true or the
  /// idempotent removed:false).
  final bool none;

  /// Whether the server actually removed a row this call.
  final bool removed;

  const ShowLessUndoResult({required this.none, required this.removed});
}

/// Thrown for any non-2xx or malformed response — the caller surfaces
/// an honest failure and never fabricates a suppression state.
class ShowLessContractException implements Exception {
  final int statusCode;
  final String reason;
  ShowLessContractException(this.statusCode, [this.reason = '']);

  @override
  String toString() =>
      'ShowLessContractException($statusCode'
      '${reason.isEmpty ? '' : ': $reason'})';
}

class RecommendationFeedbackService {
  final ApiClient _api;

  RecommendationFeedbackService({ApiClient? client})
    : _api = client ?? apiClient;

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ShowLessContractException(r.statusCode);
    }
    final body = jsonDecode(r.body);
    if (body is! Map<String, dynamic>) {
      throw ShowLessContractException(r.statusCode, 'non-object body');
    }
    return body;
  }

  /// POST /api/recommendation-feedback — apply "Show less like this"
  /// for one business. Idempotent by contract.
  Future<ShowLessApplyResult> apply(String businessProfileId) async {
    final r = await _api.post('/recommendation-feedback', {
      'businessProfileId': businessProfileId,
    });
    final body = _decode(r);
    final state = body['state']?.toString() ?? '';
    return ShowLessApplyResult(
      showLess: state == 'SHOW_LESS' && body['success'] == true,
      alreadyApplied: body['alreadyApplied'] as bool? ?? false,
      appliedAt: body['appliedAt'] != null
          ? DateTime.tryParse(body['appliedAt'].toString())
          : null,
    );
  }

  /// DELETE /api/recommendation-feedback/:id — undo. ANY 200 means the
  /// durable end state is NONE; only transport/5xx errors (thrown)
  /// leave the suppression standing.
  Future<ShowLessUndoResult> undo(String businessProfileId) async {
    final r = await _api.delete('/recommendation-feedback/$businessProfileId');
    final body = _decode(r);
    final state = body['state']?.toString() ?? '';
    return ShowLessUndoResult(
      none: state == 'NONE' && body['success'] == true,
      removed: body['removed'] as bool? ?? false,
    );
  }

  /// GET /api/recommendation-feedback/check/:id — the authoritative
  /// per-business suppression state for THIS caller only.
  Future<bool> check(String businessProfileId) async {
    final r = await _api.get(
      '/recommendation-feedback/check/$businessProfileId',
    );
    final body = _decode(r);
    return body['applied'] as bool? ?? false;
  }
}

/// Provider seam so widgets and tests ride the SAME ApiClient
/// override (apiClientProvider) the rest of the app injects.
final recommendationFeedbackServiceProvider =
    Provider<RecommendationFeedbackService>(
      (ref) =>
          RecommendationFeedbackService(client: ref.watch(apiClientProvider)),
    );
