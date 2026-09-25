// =============================================================================
// SUSU API CLIENT — Phase 4 (Master Sprint, 2026-05-31)
//
// Typed wrappers over every Susu / Proof-of-Residency / Liability-Contract
// endpoint shipped in Phase 2. The wrappers reuse `apiClient` for auth +
// error envelope parsing and live in the same file as their request DTOs
// so the call site is one import away. The contracts here mirror
// design.md "API Contracts" verbatim, with the deployed-name overrides
// from the Schema Reconciliation Addendum.
//
// Convention: every method returns the parsed `data` payload (the inner
// object the canonical envelope wraps) and lets the caller cast to a
// specific model. Errors come up as `ApiException` with `statusCode` and
// `message` already extracted.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:azaman/models/proof_of_residency_model.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/services/api_client.dart';

class SusuService {
  SusuService._();
  static final SusuService instance = SusuService._();

  // Helper — extract the `data` field from the canonical envelope, or the
  // top-level body if it isn't enveloped (the older `/api/susu/groups/:id`
  // endpoints predate the envelope and return `{ susu: {...} }` directly).
  Map<String, dynamic> _envelope(http.Response res) {
    final raw = jsonDecode(res.body);
    if (raw is! Map<String, dynamic>) {
      throw ApiException(
        message: 'Unexpected response shape',
        statusCode: res.statusCode,
      );
    }
    if (raw['data'] is Map<String, dynamic>) {
      return raw['data'] as Map<String, dynamic>;
    }
    return raw;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Susu lifecycle
  // ───────────────────────────────────────────────────────────────────────

  /// GET /api/susu/me → caller's own Susus.
  ///
  /// A 404 here means one of two benign things: the caller simply has no
  /// Susus, or the overlay route isn't live on this backend yet. Either
  /// way we return an empty list so the hub renders its friendly empty
  /// state instead of a scary error envelope.
  Future<List<SusuSummary>> myList({String? statusFilter}) async {
    final qs = statusFilter == null ? '' : '?status=$statusFilter';
    try {
      final res = await apiClient.get('/susu/me$qs');
      final data = _envelope(res);
      final list = (data['susus'] as List?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(SusuSummary.fromJson)
          .toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// POST /api/susu — create a new Susu (Req 8.1)
  /// Body: `{ name, contributionUsdc, frequency, invites: [...] }`
  /// (Backend `createSusuSchema` expects `contributionUsdc`, not
  /// `contributionAmount` — see services/validation/susuSchemas.js.)
  Future<SusuCreateResult> createSusu({
    required String name,
    required double contributionUsdc,
    required SusuFrequency frequency,
    required List<SusuInviteRequest> invites,
  }) async {
    final res = await apiClient.post('/susu', {
      'name': name,
      'contributionUsdc': contributionUsdc.toStringAsFixed(2),
      'frequency': frequency.wire,
      'invites': invites.map((i) => i.toJson()).toList(),
    });
    final data = _envelope(res);
    final susuJson = (data['susu'] ?? data) as Map<String, dynamic>;
    final inviteJson = (data['invites'] as List?) ?? const [];
    return SusuCreateResult(
      susu: SusuDetail.fromJson(susuJson),
      invites: inviteJson
          .whereType<Map<String, dynamic>>()
          .map(SusuInviteRow.fromJson)
          .toList(),
    );
  }

  /// POST /api/susu/:id/auto-retain — opt in/out of keeping the next
  /// contribution reserved after a payout (Phase 5 / Workstream B).
  Future<void> setAutoRetain(String susuId, bool enabled) async {
    await apiClient.post('/susu/$susuId/auto-retain', {'enabled': enabled});
  }

  /// POST /api/susu/:id/cancel — Req 8.5 / 8.6
  /// (Overlay route is `/susu/:id/cancel`, NOT `/susu/groups/:id/cancel`.)
  Future<void> cancelSusu(String susuId) async {
    await apiClient.post('/susu/$susuId/cancel', const {});
  }

  /// GET /api/susu/:id — privacy-gated detail (Req 5.2)
  Future<SusuDetail> getDetail(String susuId) async {
    final res = await apiClient.get('/susu/$susuId');
    final data = _envelope(res);
    final susuJson = (data['susu'] ?? data) as Map<String, dynamic>;
    return SusuDetail.fromJson(susuJson);
  }

  /// GET /api/susu/:id/cycles — ACTIVE-member only
  Future<List<SusuCycleView>> getCycles(String susuId) async {
    final res = await apiClient.get('/susu/$susuId/cycles');
    final data = _envelope(res);
    final list = (data['cycles'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(SusuCycleView.fromJson)
        .toList();
  }

  /// GET /api/susu/:id/members — ACTIVE-member only, privacy-projected
  Future<List<SusuMemberView>> getMembers(String susuId) async {
    final res = await apiClient.get('/susu/$susuId/members');
    final data = _envelope(res);
    final list = (data['members'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(SusuMemberView.fromJson)
        .toList();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Liability contract
  // ───────────────────────────────────────────────────────────────────────

  /// GET /api/susu/:id/contract → version pinned to this Susu (Req 4.1).
  /// Backend wraps the payload as `{ contract: {...} }`.
  Future<LiabilityContract> getSusuContract(String susuId) async {
    final res = await apiClient.get('/susu/$susuId/contract');
    final data = _envelope(res);
    final c = (data['contract'] ?? data) as Map<String, dynamic>;
    return LiabilityContract.fromJson(c);
  }

  /// GET /api/liability-contract/active — public, Req 4.1
  Future<LiabilityContract> getActiveContract() async {
    final res =
        await apiClient.get('/liability-contract/active', requireAuth: false);
    final data = _envelope(res);
    final c = (data['contract'] ?? data) as Map<String, dynamic>;
    return LiabilityContract.fromJson(c);
  }

  /// POST /api/susu/:id/contract/accept (Req 4.6, 4.7).
  ///
  /// On success: `{ acceptance, susu }`. Throws
  /// `ApiException(statusCode: 409, message: …)` for `CONTRACT_VERSION_MISMATCH`
  /// — the screen reloads the contract and shows a banner.
  Future<void> acceptContract({
    required String susuId,
    required String contractVersion,
    required String contractHash,
  }) async {
    await apiClient.post('/susu/$susuId/contract/accept', {
      'contractVersion': contractVersion,
      'contractHash': contractHash,
      'agreed': true,
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // Invites
  // ───────────────────────────────────────────────────────────────────────

  /// GET /api/susu/invites/preview/:token — public, no JWT (Req 6.7)
  Future<SusuInvitePreview> previewInvite(String token) async {
    final res = await apiClient.get(
      '/susu/invites/preview/$token',
      requireAuth: false,
    );
    final data = _envelope(res);
    return SusuInvitePreview.fromJson(data);
  }

  /// POST /api/susu/invites/:token/redeem — LINK channel (Req 6.6–6.10).
  /// Backend returns `{ member: {...} }`.
  Future<String> redeemLink(String token) async {
    final res = await apiClient.post('/susu/invites/$token/redeem', const {});
    final data = _envelope(res);
    final member = (data['member'] ?? data['susuMember']) as Map<String, dynamic>?;
    return (member?['susuGroupId'] ?? member?['susuId'] ?? data['susuId'])
        .toString();
  }

  /// POST /api/susu/invites/:id/accept — FRIEND/PHONE channel (Req 6.14).
  /// Backend returns `{ member: {...} }`.
  Future<String> acceptInvite(String inviteId) async {
    final res = await apiClient.post('/susu/invites/$inviteId/accept', const {});
    final data = _envelope(res);
    final member = (data['member'] ?? data['susuMember']) as Map<String, dynamic>?;
    return (member?['susuGroupId'] ?? member?['susuId'] ?? data['susuId'])
        .toString();
  }

  /// POST /api/susu/invites/:id/decline (Req 6.15)
  Future<void> declineInvite(String inviteId) async {
    await apiClient.post('/susu/invites/$inviteId/decline', const {});
  }

  /// POST /api/susu/invites/:id/revoke — initiator only (Req 6.11)
  Future<void> revokeInvite(String inviteId) async {
    await apiClient.post('/susu/invites/$inviteId/revoke', const {});
  }

  /// POST /api/susu/:id/invites — fan additional invites onto a
  /// CONFIGURING Susu, e.g. after a decline (Req 6.15 replacement slot).
  /// Backend returns `{ invite: {...} }`.
  Future<SusuInviteRow> addInvite({
    required String susuId,
    required SusuInviteRequest invite,
  }) async {
    final res = await apiClient.post('/susu/$susuId/invites', invite.toJson());
    final data = _envelope(res);
    final inv = (data['invite'] ?? data) as Map<String, dynamic>;
    return SusuInviteRow.fromJson(inv);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Proof of Residency
  // ───────────────────────────────────────────────────────────────────────

  /// GET /api/users/proof-of-residency/me — own status (Req 3, no URL)
  Future<ProofOfResidencyState> getOwnPoR() async {
    final res = await apiClient.get('/users/proof-of-residency/me');
    final data = _envelope(res);
    return ProofOfResidencyState.fromJson(data);
  }

  /// POST /api/users/proof-of-residency — multipart upload (Req 3.4)
  Future<ProofOfResidencyState> uploadPoR(File file) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiClient.baseUrl}/users/proof-of-residency'),
    );
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final res = await apiClient.multipart('/users/proof-of-residency', req);
    final data = _envelope(res);
    return ProofOfResidencyState.fromJson(data);
  }
}

final SusuService susuService = SusuService.instance;
