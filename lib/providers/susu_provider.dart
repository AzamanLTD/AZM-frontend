// =============================================================================
// SUSU PROVIDER  (Master Sprint, 2026-05-27)
//
// Riverpod state for the Susu engine + the Vouching system.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/proof_of_residency_model.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/susu_service.dart';

double _num(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

// ── Models ─────────────────────────────────────────────────────────────────

class SusuMember {
  final String id;
  final int userId;
  final String? username;
  final int cycleSlot;
  final double trustScore;
  final String status; // PENDING_CONTRACT | ACTIVE | DEFAULTED | REMOVED
  final DateTime? contractAcceptedAt;
  final DateTime? defaultedAt;
  final double totalSeizedUsdc;

  SusuMember({
    required this.id,
    required this.userId,
    this.username,
    required this.cycleSlot,
    required this.trustScore,
    required this.status,
    this.contractAcceptedAt,
    this.defaultedAt,
    required this.totalSeizedUsdc,
  });

  factory SusuMember.fromJson(Map<String, dynamic> j) => SusuMember(
        id: j['id'],
        userId: (j['userId'] as num).toInt(),
        username: j['user']?['username'] as String?,
        cycleSlot: (j['cycleSlot'] as num).toInt(),
        trustScore: _num(j['trustScore']),
        status: j['status'],
        contractAcceptedAt: j['contractAcceptedAt'] != null
            ? DateTime.tryParse(j['contractAcceptedAt'])
            : null,
        defaultedAt:
            j['defaultedAt'] != null ? DateTime.tryParse(j['defaultedAt']) : null,
        totalSeizedUsdc: _num(j['totalSeizedUsdc']),
      );
}

class SusuCycle {
  final String id;
  final int cycleNumber;
  final DateTime collectionDate;
  final double payoutAmount;
  final int payoutUserId;
  final String status; // PENDING | COLLECTING | PAID_OUT | DEFAULTED
  final DateTime? paidOutAt;
  final int defaultsCount;

  SusuCycle({
    required this.id,
    required this.cycleNumber,
    required this.collectionDate,
    required this.payoutAmount,
    required this.payoutUserId,
    required this.status,
    this.paidOutAt,
    required this.defaultsCount,
  });

  factory SusuCycle.fromJson(Map<String, dynamic> j) => SusuCycle(
        id: j['id'],
        cycleNumber: (j['cycleNumber'] as num).toInt(),
        collectionDate: DateTime.parse(j['collectionDate']),
        payoutAmount: _num(j['payoutAmount']),
        payoutUserId: (j['payoutUserId'] as num).toInt(),
        status: j['status'],
        paidOutAt: j['paidOutAt'] != null ? DateTime.tryParse(j['paidOutAt']) : null,
        defaultsCount: (j['defaultsCount'] as num?)?.toInt() ?? 0,
      );
}

class SusuGroup {
  final String id;
  final String status; // CONFIGURING | ACTIVE | COMPLETED | CANCELLED | FROZEN_DISPUTE
  final double contributionUsdc;
  final String frequency; // WEEKLY | BIWEEKLY | MONTHLY
  final int totalCycles;
  final DateTime startDate;
  final int contractAcceptedCount;
  final int contractRequiredCount;
  final List<SusuMember> members;
  final List<SusuCycle> cycles;
  final String? groupChatName;
  final String? groupChatId;

  SusuGroup({
    required this.id,
    required this.status,
    required this.contributionUsdc,
    required this.frequency,
    required this.totalCycles,
    required this.startDate,
    required this.contractAcceptedCount,
    required this.contractRequiredCount,
    required this.members,
    required this.cycles,
    this.groupChatName,
    this.groupChatId,
  });

  factory SusuGroup.fromJson(Map<String, dynamic> j) => SusuGroup(
        id: j['id'],
        status: j['status'],
        contributionUsdc: _num(j['contributionUsdc']),
        frequency: j['frequency'],
        totalCycles: (j['totalCycles'] as num).toInt(),
        startDate: DateTime.parse(j['startDate']),
        contractAcceptedCount:
            (j['contractAcceptedCount'] as num?)?.toInt() ?? 0,
        contractRequiredCount:
            (j['contractRequiredCount'] as num?)?.toInt() ?? 0,
        members: (j['members'] as List<dynamic>? ?? const [])
            .map((m) => SusuMember.fromJson(m))
            .toList(),
        cycles: (j['cycles'] as List<dynamic>? ?? const [])
            .map((c) => SusuCycle.fromJson(c))
            .toList(),
        groupChatName: j['groupChat']?['name'],
        groupChatId: j['groupChat']?['id'],
      );
}

class PendingVouch {
  final String id;
  final String groupId;
  final String? groupName;
  final int? inviteeId;
  final String? inviteeUsername;
  final String? inviteePhone;
  final String relationship;
  final String reasonForTrust;

  PendingVouch({
    required this.id,
    required this.groupId,
    this.groupName,
    this.inviteeId,
    this.inviteeUsername,
    this.inviteePhone,
    required this.relationship,
    required this.reasonForTrust,
  });

  factory PendingVouch.fromJson(Map<String, dynamic> j) => PendingVouch(
        id: j['id'],
        groupId: j['groupId'],
        groupName: j['group']?['name'],
        inviteeId: j['inviteeId'] != null ? (j['inviteeId'] as num).toInt() : null,
        inviteeUsername: j['invitee']?['username'],
        inviteePhone: j['inviteePhone'],
        relationship: j['relationship'] ?? '',
        reasonForTrust: j['reasonForTrust'] ?? '',
      );
}

// ── Providers ──────────────────────────────────────────────────────────────

final susuDetailProvider =
    FutureProvider.family<SusuGroup?, String>((ref, susuId) async {
  final res = await apiClient.get('/susu/groups/$susuId');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return SusuGroup.fromJson(body['susu']);
});

final pendingVouchesProvider =
    FutureProvider<List<PendingVouch>>((ref) async {
  final res = await apiClient.get('/susu/vouches/pending');
  if (res.statusCode != 200) return const [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = body['vouches'] as List<dynamic>? ?? const [];
  return list.map((e) => PendingVouch.fromJson(e)).toList();
});

class SusuActions {
  final Ref ref;
  SusuActions(this.ref);

  Future<SusuGroup> createSusu({
    required String groupChatId,
    required double contributionUsdc,
    required String frequency,
    required DateTime startDate,
  }) async {
    final res = await apiClient.post('/susu/groups', {
      'groupChatId': groupChatId,
      'contributionUsdc': contributionUsdc,
      'frequency': frequency,
      'startDate': startDate.toIso8601String(),
    });
    if (res.statusCode != 201) {
      throw Exception(_msg(res.body));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return SusuGroup.fromJson({
      ...body['susu'] as Map<String, dynamic>,
      'members': const [],
      'cycles': const [],
    });
  }

  Future<void> acceptContract(String susuId) async {
    final res = await apiClient.post('/susu/groups/$susuId/contract', {
      'acceptedSeverityWarning': true,
      'acceptedSeizureClause': true,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    ref.invalidate(susuDetailProvider(susuId));
  }

  Future<void> submitVouch(String vouchRecordId, Map<String, dynamic> payload) async {
    final res = await apiClient.post('/susu/vouches', {
      'vouchRecordId': vouchRecordId,
      'payload': payload,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    ref.invalidate(pendingVouchesProvider);
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Susu request failed';
    } catch (_) {
      return 'Susu request failed';
    }
  }
}

final susuActionsProvider = Provider<SusuActions>((ref) => SusuActions(ref));


// =============================================================================
// PHASE 4 PROVIDERS — Master Sprint, 2026-05-31
//
// New Riverpod surface for the Private Susu (ROSCA) Ecosystem feature. These
// live alongside the legacy `susuDetailProvider` / `susuActionsProvider`
// above so the existing GroupChat-keyed dashboard keeps working unchanged.
//
// Naming convention for new providers (per design.md "Components and
// Interfaces" → Riverpod providers table):
//
//   • susuListProvider                  — caller's own Susus, GET /api/susu/me
//   • susuDetailV2Provider(susuId)      — GET /api/susu/groups/:id (Phase 4 model)
//   • susuCyclesProvider(susuId)        — GET /api/susu/groups/:id/cycles
//   • susuMembersProvider(susuId)       — GET /api/susu/groups/:id/members
//   • susuInvitePreviewProvider(token)  — GET /api/susu/invites/preview/:token
//   • proofOfResidencyProvider          — GET /api/users/proof-of-residency/me
//
// (`susuDetailV2Provider` is named with the `V2` suffix to avoid colliding
// with the legacy `susuDetailProvider` above. The router uses V2 because
// the new Phase 4 screens consume the new SusuDetail model.)
//
// Each detail/cycles/members provider subscribes to its `susu_${susuId}`
// socket room when first read and listens for `susu_status_changed`,
// `susu_member_status_changed`, and `susu_cycle_update`. The room is
// joined lazily; cleanup is keyed on AsyncNotifier.dispose.
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4 list provider — caller's own Susus, grouped client-side.
// ─────────────────────────────────────────────────────────────────────────────

class SusuListNotifier extends AutoDisposeAsyncNotifier<List<SusuSummary>> {
  @override
  Future<List<SusuSummary>> build() async {
    return susuService.myList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(susuService.myList);
  }
}

final susuListProvider =
    AsyncNotifierProvider.autoDispose<SusuListNotifier, List<SusuSummary>>(
  SusuListNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4 detail provider — full SusuDetail with members + cycles + status.
// Subscribes to the `susu_${susuId}` socket room on first build.
// ─────────────────────────────────────────────────────────────────────────────

class SusuDetailV2Notifier
    extends AutoDisposeFamilyAsyncNotifier<SusuDetail, String> {
  void Function(dynamic)? _onStatusChanged;
  void Function(dynamic)? _onCycleUpdate;
  void Function(dynamic)? _onMemberStatusChanged;
  String? _joinedRoom;

  @override
  Future<SusuDetail> build(String susuId) async {
    final socket = SocketService.instance.rawSocket;
    final room = 'susu_$susuId';

    _onStatusChanged = (data) {
      if (data is Map && data['susuId']?.toString() == susuId) {
        // Cheap, full re-fetch — the BE response is small.
        ref.invalidateSelf();
      }
    };
    _onCycleUpdate = (data) {
      if (data is Map && data['susuId']?.toString() == susuId) {
        ref.invalidateSelf();
        // Co-trigger the cycles provider so the dashboard's schedule
        // strip flips without the user pull-to-refreshing.
        ref.invalidate(susuCyclesProvider(susuId));
      }
    };
    _onMemberStatusChanged = (data) {
      if (data is Map && data['susuId']?.toString() == susuId) {
        ref.invalidateSelf();
        ref.invalidate(susuMembersProvider(susuId));
      }
    };

    if (socket != null) {
      socket.emit('join_susu', susuId);
      socket.on('susu_status_changed', _onStatusChanged!);
      socket.on('susu_cycle_update', _onCycleUpdate!);
      socket.on('susu_member_status_changed', _onMemberStatusChanged!);
      _joinedRoom = room;
    }

    ref.onDispose(() {
      final s = SocketService.instance.rawSocket;
      if (s == null) return;
      if (_onStatusChanged != null) {
        s.off('susu_status_changed', _onStatusChanged);
      }
      if (_onCycleUpdate != null) {
        s.off('susu_cycle_update', _onCycleUpdate);
      }
      if (_onMemberStatusChanged != null) {
        s.off('susu_member_status_changed', _onMemberStatusChanged);
      }
      if (_joinedRoom != null) {
        s.emit('leave_susu', susuId);
      }
    });

    return susuService.getDetail(susuId);
  }
}

final susuDetailV2Provider = AsyncNotifierProvider.autoDispose
    .family<SusuDetailV2Notifier, SusuDetail, String>(
  SusuDetailV2Notifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Cycles provider — schedule strip on the dashboard.
// ─────────────────────────────────────────────────────────────────────────────

class SusuCyclesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<SusuCycleView>, String> {
  @override
  Future<List<SusuCycleView>> build(String susuId) async {
    return susuService.getCycles(susuId);
  }
}

final susuCyclesProvider = AsyncNotifierProvider.autoDispose
    .family<SusuCyclesNotifier, List<SusuCycleView>, String>(
  SusuCyclesNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Members provider — privacy-projected roster.
// ─────────────────────────────────────────────────────────────────────────────

class SusuMembersNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<SusuMemberView>, String> {
  @override
  Future<List<SusuMemberView>> build(String susuId) async {
    return susuService.getMembers(susuId);
  }
}

final susuMembersProvider = AsyncNotifierProvider.autoDispose
    .family<SusuMembersNotifier, List<SusuMemberView>, String>(
  SusuMembersNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Invite preview provider — public, no JWT.
// ─────────────────────────────────────────────────────────────────────────────

class SusuInvitePreviewNotifier
    extends AutoDisposeFamilyAsyncNotifier<SusuInvitePreview, String> {
  @override
  Future<SusuInvitePreview> build(String token) async {
    return susuService.previewInvite(token);
  }
}

final susuInvitePreviewProvider = AsyncNotifierProvider.autoDispose
    .family<SusuInvitePreviewNotifier, SusuInvitePreview, String>(
  SusuInvitePreviewNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Proof of Residency provider — own status only (Req 3.12 — never URL).
// ─────────────────────────────────────────────────────────────────────────────

class ProofOfResidencyNotifier
    extends AutoDisposeAsyncNotifier<ProofOfResidencyState> {
  @override
  Future<ProofOfResidencyState> build() async {
    try {
      return await susuService.getOwnPoR();
    } on ApiException catch (e) {
      // 404 / 401 → caller has never submitted, so default to NOT_SUBMITTED.
      if (e.statusCode == 404 || e.statusCode == 401) {
        return const ProofOfResidencyState.notSubmitted();
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => susuService.getOwnPoR());
  }
}

final proofOfResidencyProvider = AsyncNotifierProvider.autoDispose<
    ProofOfResidencyNotifier, ProofOfResidencyState>(
  ProofOfResidencyNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Susu supplied-rate provider — the USDC→GHS rate Azaman supplies to users.
//
// This is the `liveRetailRate` (the rate WE give users, which already has
// our margin on top of the corporate/Kotani Pay supply rate). It is NOT
// the raw corporate rate. Sourced from the public GET /api/oracle/rates
// endpoint, same field the home screen's Live Market section reads.
//
// Used by SusuCreateScreen to render the cedis equivalence beside the
// USDC contribution input so members see what they're really committing.
// ─────────────────────────────────────────────────────────────────────────────

class SusuSuppliedRate {
  final double usdcToGhs; // liveRetailRate — the rate we supply to users
  final String source; // e.g. KOTANI_PAY
  const SusuSuppliedRate({required this.usdcToGhs, required this.source});

  static const empty = SusuSuppliedRate(usdcToGhs: 0, source: 'UNAVAILABLE');
}

final susuSuppliedRateProvider =
    FutureProvider.autoDispose<SusuSuppliedRate>((ref) async {
  try {
    final res = await apiClient.get('/oracle/rates', requireAuth: false);
    final raw = jsonDecode(res.body);
    if (raw is! Map<String, dynamic> || raw['success'] != true) {
      return SusuSuppliedRate.empty;
    }
    final data = raw['data'] as Map<String, dynamic>? ?? const {};
    double asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;
    // Prefer the retail (user-facing) rate. Fall back to the headline
    // USD→GHS rate only if retail is missing.
    final retail = asDouble(data['liveRetailRate']);
    final headline = asDouble(data['liveUsdToGhs']);
    return SusuSuppliedRate(
      usdcToGhs: retail > 0 ? retail : headline,
      source: (data['rateSource'] ?? 'UNKNOWN').toString(),
    );
  } catch (_) {
    return SusuSuppliedRate.empty;
  }
});
