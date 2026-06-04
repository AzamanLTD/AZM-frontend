// =============================================================================
// GROUP CHAT PROVIDER  (Master Sprint, 2026-05-27)
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

class GroupMember {
  final String id;
  final int userId;
  final String? username;
  final String? profilePictureUrl;
  final String role; // ADMIN | MEMBER
  final DateTime joinedAt;
  final DateTime? removedAt;

  GroupMember({
    required this.id,
    required this.userId,
    this.username,
    this.profilePictureUrl,
    required this.role,
    required this.joinedAt,
    this.removedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        id: j['id'],
        userId: (j['userId'] as num).toInt(),
        username: j['user']?['username'],
        profilePictureUrl: j['user']?['profilePictureUrl'],
        role: j['role'],
        joinedAt: DateTime.parse(j['joinedAt']),
        removedAt: j['removedAt'] != null ? DateTime.tryParse(j['removedAt']) : null,
      );
}

class GroupSummary {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String status;
  final String? susuGroupId;
  final String? susuStatus; // CONFIGURING | ACTIVE | COMPLETED | ... (null if no susu)
  final DateTime? initiationDeadline;
  final List<GroupMember> members;
  final DateTime updatedAt;

  GroupSummary({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.status,
    this.susuGroupId,
    this.susuStatus,
    this.initiationDeadline,
    required this.members,
    required this.updatedAt,
  });

  bool get isSusuEnabled => susuGroupId != null;
  bool get isSusuConfiguring => susuStatus == 'CONFIGURING';
  bool get isSusuActive => susuStatus == 'ACTIVE';

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
        id: j['id'],
        name: j['name'],
        description: j['description'],
        avatarUrl: j['avatarUrl'],
        status: j['status'],
        susuGroupId: j['susuGroupId'],
        susuStatus: j['susuGroup']?['status']?.toString(),
        initiationDeadline: j['susuGroup']?['initiationDeadline'] != null
            ? DateTime.tryParse(j['susuGroup']['initiationDeadline'].toString())
            : null,
        members: (j['members'] as List<dynamic>? ?? const [])
            .map((m) => GroupMember.fromJson(m))
            .toList(),
        updatedAt: DateTime.parse(j['updatedAt']),
      );
}

class GroupMessage {
  final String id;
  final int? senderId;
  final String? senderUsername;
  final String type;
  final String? content;
  final Map<String, dynamic>? metadata;
  final String? mediaUrl;
  final String? mediaType;
  final DateTime createdAt;

  GroupMessage({
    required this.id,
    this.senderId,
    this.senderUsername,
    required this.type,
    this.content,
    this.metadata,
    this.mediaUrl,
    this.mediaType,
    required this.createdAt,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> j) => GroupMessage(
        id: j['id'],
        senderId: j['senderId'] != null ? (j['senderId'] as num).toInt() : null,
        senderUsername: j['sender']?['username'],
        type: j['type'],
        content: j['content'],
        metadata: j['metadata'] as Map<String, dynamic>?,
        mediaUrl: j['mediaUrl'],
        mediaType: j['mediaType'],
        createdAt: DateTime.parse(j['createdAt']),
      );
}

// ── Providers ─────────────────────────────────────────────────────────────

class GroupListNotifier extends AsyncNotifier<List<GroupSummary>> {
  @override
  Future<List<GroupSummary>> build() => _fetch();

  Future<List<GroupSummary>> _fetch() async {
    final res = await apiClient.get('/group-chats');
    if (res.statusCode != 200) {
      throw Exception('Failed to load groups (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['groups'] as List<dynamic>? ?? const [];
    return list.map((e) => GroupSummary.fromJson(e)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<GroupSummary> create({
    required String name,
    String? description,
    String? avatarUrl,
    List<int> initialMemberIds = const [],
    List<int> adminIds = const [],
  }) async {
    final res = await apiClient.post('/group-chats', {
      'name': name,
      if (description != null) 'description': description,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'initialMemberIds': initialMemberIds,
      'adminIds': adminIds,
    });
    if (res.statusCode != 201) {
      throw Exception(_msg(res.body));
    }
    await refresh();
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return GroupSummary.fromJson(body['group']);
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Group request failed';
    } catch (_) {
      return 'Group request failed';
    }
  }
}

final groupListProvider =
    AsyncNotifierProvider<GroupListNotifier, List<GroupSummary>>(GroupListNotifier.new);

final groupDetailProvider =
    FutureProvider.family<GroupSummary?, String>((ref, groupId) async {
  final res = await apiClient.get('/group-chats/$groupId');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return GroupSummary.fromJson(body['group']);
});

final groupMessagesProvider = FutureProvider.family<List<GroupMessage>, String>(
  (ref, groupId) async {
    final res = await apiClient.get('/group-chats/$groupId/messages?limit=50');
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['messages'] as List<dynamic>? ?? const [];
    return list.map((e) => GroupMessage.fromJson(e)).toList();
  },
);

class GroupActions {
  final Ref ref;
  GroupActions(this.ref);

  Future<void> sendMessage(String groupId, {required String content, String type = 'TEXT'}) async {
    final res = await apiClient.post('/group-chats/$groupId/messages', {
      'type': type,
      'content': content,
    });
    if (res.statusCode != 201) throw Exception('Send failed');
    ref.invalidate(groupMessagesProvider(groupId));
  }

  Future<void> addMember(
    String groupId, {
    int? userId,
    String? phone,
    Map<String, dynamic>? vouch,
  }) async {
    final res = await apiClient.post('/group-chats/$groupId/members', {
      if (userId != null) 'userId': userId,
      if (phone != null) 'phone': phone,
      if (vouch != null) 'vouch': vouch,
    });
    if (res.statusCode != 201) {
      throw Exception(_msg(res.body));
    }
    ref.invalidate(groupDetailProvider(groupId));
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Group request failed';
    } catch (_) {
      return 'Group request failed';
    }
  }
}

final groupActionsProvider = Provider<GroupActions>((ref) => GroupActions(ref));

// =============================================================================
// PHASE 5 / Workstream D — Group-chat-first Susu initiation
// =============================================================================

/// One member's verification snapshot for the group-profile chips.
class SusuInitiationMember {
  final int userId;
  final String username;
  final String? avatar;
  final String groupRole; // ADMIN | MEMBER
  final String kyc; // UNVERIFIED | PENDING | VERIFIED | REJECTED
  final String por; // NOT_SUBMITTED | PENDING_REVIEW | VERIFIED | REJECTED | EXPIRED
  final String? susuMemberStatus; // PENDING_VOUCH | PENDING_CONTRACT | ACTIVE | ...
  final bool ready;

  SusuInitiationMember({
    required this.userId,
    required this.username,
    required this.avatar,
    required this.groupRole,
    required this.kyc,
    required this.por,
    required this.susuMemberStatus,
    required this.ready,
  });

  factory SusuInitiationMember.fromJson(Map<String, dynamic> j) =>
      SusuInitiationMember(
        userId: (j['userId'] as num).toInt(),
        username: (j['username'] ?? 'Member').toString(),
        avatar: j['avatar']?.toString(),
        groupRole: (j['groupRole'] ?? 'MEMBER').toString(),
        kyc: (j['kyc'] ?? 'UNVERIFIED').toString(),
        por: (j['por'] ?? 'NOT_SUBMITTED').toString(),
        susuMemberStatus: j['susuMemberStatus']?.toString(),
        ready: j['ready'] == true,
      );

  /// Tri-state for a chip: 'green' (verified), 'yellow' (in-process),
  /// 'red' (not started / rejected / expired).
  static String chipState(String raw) {
    switch (raw.toUpperCase()) {
      case 'VERIFIED':
        return 'green';
      case 'PENDING':
      case 'PENDING_REVIEW':
        return 'yellow';
      default:
        return 'red';
    }
  }

  String get kycChip => chipState(kyc);
  String get poaChip => chipState(por);
}

/// The group's Susu-initiation status (null susuGroupId = no susu yet).
class SusuInitiationStatus {
  final String? susuGroupId;
  final String? status; // CONFIGURING | ACTIVE | ...
  final DateTime? deadline;
  final double? contributionUsdc;
  final String? frequency;
  final int? totalCycles;
  final int memberCount;
  final int readyCount;
  final List<SusuInitiationMember> members;

  SusuInitiationStatus({
    required this.susuGroupId,
    required this.status,
    required this.deadline,
    required this.contributionUsdc,
    required this.frequency,
    required this.totalCycles,
    required this.memberCount,
    required this.readyCount,
    required this.members,
  });

  bool get isConfiguring => status == 'CONFIGURING';
  bool get isActive => status == 'ACTIVE';

  /// Projected pool per cycle = contribution × member count (USDC).
  double get projectedPoolUsdc =>
      (contributionUsdc ?? 0) * (memberCount);

  factory SusuInitiationStatus.fromJson(Map<String, dynamic> j) =>
      SusuInitiationStatus(
        susuGroupId: j['susuGroupId']?.toString(),
        status: j['status']?.toString(),
        deadline: j['initiationDeadline'] != null
            ? DateTime.tryParse(j['initiationDeadline'].toString())
            : null,
        contributionUsdc: j['contributionUsdc'] == null
            ? null
            : (j['contributionUsdc'] as num).toDouble(),
        frequency: j['frequency']?.toString(),
        totalCycles: j['totalCycles'] != null
            ? (j['totalCycles'] as num).toInt()
            : null,
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        readyCount: (j['readyCount'] as num?)?.toInt() ?? 0,
        members: (j['members'] as List<dynamic>? ?? const [])
            .map((m) => SusuInitiationMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// GET /api/group-chats/:id/susu/status — drives the group-profile chips
/// and the countdown banner. Refreshable.
final susuInitiationStatusProvider =
    FutureProvider.family<SusuInitiationStatus?, String>((ref, groupId) async {
  final res = await apiClient.get('/group-chats/$groupId/susu/status');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return SusuInitiationStatus.fromJson(body);
});

extension SusuInitiationActions on GroupActions {
  /// POST /api/group-chats/:id/susu/initiate (group admin only).
  Future<void> initiateSusu(
    String groupId, {
    required double contributionUsdc,
    required String frequency,
    int windowHours = 72,
  }) async {
    final res = await apiClient.post('/group-chats/$groupId/susu/initiate', {
      'contributionUsdc': contributionUsdc.toStringAsFixed(2),
      'frequency': frequency,
      'windowHours': windowHours,
    });
    if (res.statusCode != 201) {
      throw Exception(_initMsg(res.body));
    }
    ref.invalidate(susuInitiationStatusProvider(groupId));
    ref.invalidate(groupDetailProvider(groupId));
  }

  /// POST /api/group-chats/:id/susu/cancel (group admin only).
  Future<void> cancelInitiation(String groupId) async {
    final res = await apiClient.post('/group-chats/$groupId/susu/cancel', const {});
    if (res.statusCode != 200) throw Exception(_initMsg(res.body));
    ref.invalidate(susuInitiationStatusProvider(groupId));
    ref.invalidate(groupDetailProvider(groupId));
  }

  String _initMsg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Susu initiation failed';
    } catch (_) {
      return 'Susu initiation failed';
    }
  }
}
