// =============================================================================
// SUSU MODELS — Phase 4 (Master Sprint, 2026-05-31)
//
// Wire-format models for the Private Susu (ROSCA) Ecosystem. These mirror
// the backend's response envelopes after the Schema Reconciliation Addendum
// was applied: design names like `Susu` map onto the deployed `SusuGroup`,
// `payoutSlot` onto `cycleSlot`, `payoutRecipientId` onto `payoutUserId`,
// and so on. The Flutter layer always speaks the deployed names since
// that's what the JSON actually carries.
//
// These are intentionally LIGHTWEIGHT view models — only the fields the
// UI renders. AZM rank computation keys (`azmBalance`, `createdAt`, raw
// `id`) and PII (`availableBalance`, phone, email, address) are NEVER
// exposed in any /api/susu endpoint per Privacy Property 15, so they
// are absent here too.
//
// The richer `SusuGroup`/`SusuMember`/`SusuCycle` models that ship with
// the older scaffolding in `providers/susu_provider.dart` are preserved
// untouched and continue to power the existing dashboard. The Phase 4
// Susu Hub / Create / Invite Landing surfaces use the slim summaries in
// this file.
// =============================================================================

double _decimalToDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

DateTime? _maybeDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

// ─────────────────────────────────────────────────────────────────────────────
// Enums (mirror backend Susu enums per Schema Reconciliation Addendum)
// ─────────────────────────────────────────────────────────────────────────────

enum SusuStatus {
  configuring,
  active,
  completed,
  cancelled,
  frozenDispute,
  unknown;

  static SusuStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'CONFIGURING':
        return SusuStatus.configuring;
      case 'ACTIVE':
        return SusuStatus.active;
      case 'COMPLETED':
        return SusuStatus.completed;
      case 'CANCELLED':
        return SusuStatus.cancelled;
      case 'FROZEN_DISPUTE':
        return SusuStatus.frozenDispute;
      default:
        return SusuStatus.unknown;
    }
  }

  String get wire => switch (this) {
        SusuStatus.configuring => 'CONFIGURING',
        SusuStatus.active => 'ACTIVE',
        SusuStatus.completed => 'COMPLETED',
        SusuStatus.cancelled => 'CANCELLED',
        SusuStatus.frozenDispute => 'FROZEN_DISPUTE',
        SusuStatus.unknown => 'UNKNOWN',
      };

  String get label => switch (this) {
        SusuStatus.configuring => 'Pending',
        SusuStatus.active => 'Active',
        SusuStatus.completed => 'Completed',
        SusuStatus.cancelled => 'Cancelled',
        SusuStatus.frozenDispute => 'Frozen',
        SusuStatus.unknown => '—',
      };
}

enum SusuMemberStatus {
  pendingVouch,
  pendingContract,
  active,
  defaulted,
  removed,
  unknown;

  static SusuMemberStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'PENDING_VOUCH':
        return SusuMemberStatus.pendingVouch;
      case 'PENDING_CONTRACT':
        return SusuMemberStatus.pendingContract;
      case 'ACTIVE':
        return SusuMemberStatus.active;
      case 'DEFAULTED':
        return SusuMemberStatus.defaulted;
      case 'REMOVED':
        return SusuMemberStatus.removed;
      default:
        return SusuMemberStatus.unknown;
    }
  }

  String get wire => switch (this) {
        SusuMemberStatus.pendingVouch => 'PENDING_VOUCH',
        SusuMemberStatus.pendingContract => 'PENDING_CONTRACT',
        SusuMemberStatus.active => 'ACTIVE',
        SusuMemberStatus.defaulted => 'DEFAULTED',
        SusuMemberStatus.removed => 'REMOVED',
        SusuMemberStatus.unknown => 'UNKNOWN',
      };
}

enum SusuFrequency {
  daily,
  weekly,
  biweekly,
  monthly,
  unknown;

  static SusuFrequency fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'DAILY':
        return SusuFrequency.daily;
      case 'WEEKLY':
        return SusuFrequency.weekly;
      case 'BIWEEKLY':
        return SusuFrequency.biweekly;
      case 'MONTHLY':
        return SusuFrequency.monthly;
      default:
        return SusuFrequency.unknown;
    }
  }

  String get wire => switch (this) {
        SusuFrequency.daily => 'DAILY',
        SusuFrequency.weekly => 'WEEKLY',
        SusuFrequency.biweekly => 'BIWEEKLY',
        SusuFrequency.monthly => 'MONTHLY',
        SusuFrequency.unknown => 'UNKNOWN',
      };

  String get label => switch (this) {
        SusuFrequency.daily => 'Daily',
        SusuFrequency.weekly => 'Weekly',
        SusuFrequency.biweekly => 'Bi-weekly',
        SusuFrequency.monthly => 'Monthly',
        SusuFrequency.unknown => '—',
      };
}

enum SusuInviteChannel {
  friend,
  phone,
  link,
  unknown;

  static SusuInviteChannel fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'FRIEND':
        return SusuInviteChannel.friend;
      case 'PHONE':
        return SusuInviteChannel.phone;
      case 'LINK':
        return SusuInviteChannel.link;
      default:
        return SusuInviteChannel.unknown;
    }
  }

  String get wire => switch (this) {
        SusuInviteChannel.friend => 'FRIEND',
        SusuInviteChannel.phone => 'PHONE',
        SusuInviteChannel.link => 'LINK',
        SusuInviteChannel.unknown => 'UNKNOWN',
      };
}

enum SusuInviteStatus {
  pending,
  accepted,
  declined,
  revoked,
  expired,
  unknown;

  static SusuInviteStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'PENDING':
        return SusuInviteStatus.pending;
      case 'ACCEPTED':
        return SusuInviteStatus.accepted;
      case 'DECLINED':
        return SusuInviteStatus.declined;
      case 'REVOKED':
        return SusuInviteStatus.revoked;
      case 'EXPIRED':
        return SusuInviteStatus.expired;
      default:
        return SusuInviteStatus.unknown;
    }
  }
}

enum SusuCycleStatus {
  pending,
  collecting,
  collectingGrace,
  paidOut,
  defaulted,
  unknown;

  static SusuCycleStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'PENDING':
        return SusuCycleStatus.pending;
      case 'COLLECTING':
        return SusuCycleStatus.collecting;
      case 'COLLECTING_GRACE':
        return SusuCycleStatus.collectingGrace;
      case 'PAID_OUT':
        return SusuCycleStatus.paidOut;
      case 'DEFAULTED':
        return SusuCycleStatus.defaulted;
      default:
        return SusuCycleStatus.unknown;
    }
  }

  String get label => switch (this) {
        SusuCycleStatus.pending => 'Pending',
        SusuCycleStatus.collecting => 'Collecting',
        SusuCycleStatus.collectingGrace => 'Grace period',
        SusuCycleStatus.paidOut => 'Paid out',
        SusuCycleStatus.defaulted => 'Defaulted',
        SusuCycleStatus.unknown => '—',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// SusuSummary — one row in the caller's "my susus" list (GET /api/susu/me)
// ─────────────────────────────────────────────────────────────────────────────

class SusuSummary {
  /// Backend SusuGroup.id
  final String id;
  final String name;
  final SusuStatus status;
  final double contributionUsdc;
  final SusuFrequency frequency;
  final int totalCycles;
  final DateTime? activatedAt;

  /// Caller's own SusuMember projection inside this Susu.
  final int? myCycleSlot;
  final SusuMemberStatus myStatus;
  final String myRole; // 'ADMIN' | 'MEMBER'

  /// Earliest pending cycle so the hub tile can render a countdown.
  final SusuCycleSummary? nextCycle;

  const SusuSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.contributionUsdc,
    required this.frequency,
    required this.totalCycles,
    this.activatedAt,
    required this.myCycleSlot,
    required this.myStatus,
    required this.myRole,
    required this.nextCycle,
  });

  factory SusuSummary.fromJson(Map<String, dynamic> j) {
    // The backend `GET /api/susu/me` (listMine) returns each row as a
    // SusuGroup with `members` filtered to the caller, `cycles` limited to
    // the first PENDING cycle, and `groupChat { id, name }`. We also keep
    // the design-doc `{ susu, me, nextCycle }` shape as a fallback so
    // either envelope parses cleanly.
    final susu = (j['susu'] ?? j) as Map<String, dynamic>;
    final meExplicit = j['me'] as Map<String, dynamic>?;
    final membersArr = (susu['members'] ?? j['members']) as List?;
    final me = meExplicit ??
        (membersArr != null && membersArr.isNotEmpty
            ? membersArr.first as Map<String, dynamic>
            : null);
    final ncExplicit = j['nextCycle'] as Map<String, dynamic>?;
    final cyclesArr = (susu['cycles'] ?? j['cycles']) as List?;
    final nc = ncExplicit ??
        (cyclesArr != null && cyclesArr.isNotEmpty
            ? cyclesArr.first as Map<String, dynamic>
            : null);

    int asInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

    return SusuSummary(
      id: susu['id'].toString(),
      name: (susu['name'] ?? susu['groupChat']?['name'] ?? 'Susu').toString(),
      status: SusuStatus.fromString(susu['status']),
      contributionUsdc: _decimalToDouble(
          susu['contributionUsdc'] ?? susu['contributionAmount']),
      frequency: SusuFrequency.fromString(susu['frequency']),
      totalCycles: asInt(susu['totalCycles'] ?? susu['cycleCount']),
      activatedAt: _maybeDate(susu['activatedAt'] ?? susu['startDate']),
      myCycleSlot: me == null
          ? null
          : (me['cycleSlot'] ?? me['payoutSlot']) is num
              ? (me['cycleSlot'] ?? me['payoutSlot'] as num).toInt()
              : null,
      myStatus: SusuMemberStatus.fromString(me?['status']),
      myRole: (me?['role'] ?? 'MEMBER').toString(),
      nextCycle: nc == null ? null : SusuCycleSummary.fromJson(nc),
    );
  }
}

class SusuCycleSummary {
  final String id;
  final int cycleNumber;
  final DateTime scheduledRunAt;
  final int payoutUserId;
  final bool isMe;

  const SusuCycleSummary({
    required this.id,
    required this.cycleNumber,
    required this.scheduledRunAt,
    required this.payoutUserId,
    required this.isMe,
  });

  factory SusuCycleSummary.fromJson(Map<String, dynamic> j) => SusuCycleSummary(
        id: j['id'].toString(),
        cycleNumber: (j['cycleNumber'] as num).toInt(),
        scheduledRunAt: DateTime.parse(
            (j['scheduledRunAt'] ?? j['collectionDate']).toString()),
        payoutUserId:
            ((j['payoutUserId'] ?? j['payoutRecipientId']) as num).toInt(),
        isMe: j['isMe'] == true,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SusuDetail — GET /api/susu/groups/:id (read endpoint, ACTIVE-member gated)
// ─────────────────────────────────────────────────────────────────────────────

class SusuDetail {
  final String id;
  final String name;
  final SusuStatus status;
  final double contributionUsdc;
  final SusuFrequency frequency;
  final int totalCycles;
  final String? contractVersion;
  final String? contractHash;
  final DateTime? activatedAt;
  final DateTime? completedAt;
  final DateTime? frozenAt;
  final String? frozenReason;
  final SusuInitiator? initiator;
  final List<SusuMemberView> members;
  final List<SusuCycleView> cycles;

  const SusuDetail({
    required this.id,
    required this.name,
    required this.status,
    required this.contributionUsdc,
    required this.frequency,
    required this.totalCycles,
    required this.contractVersion,
    required this.contractHash,
    required this.activatedAt,
    required this.completedAt,
    required this.frozenAt,
    required this.frozenReason,
    required this.initiator,
    required this.members,
    required this.cycles,
  });

  factory SusuDetail.fromJson(Map<String, dynamic> j) {
    return SusuDetail(
      id: j['id'].toString(),
      name: (j['name'] ?? j['groupChat']?['name'] ?? 'Susu').toString(),
      status: SusuStatus.fromString(j['status']),
      contributionUsdc:
          _decimalToDouble(j['contributionUsdc'] ?? j['contributionAmount']),
      frequency: SusuFrequency.fromString(j['frequency']),
      totalCycles: ((j['totalCycles'] ?? j['cycleCount'] ?? 0) as num).toInt(),
      contractVersion: j['contractVersion']?.toString(),
      contractHash: j['contractHash']?.toString(),
      activatedAt: _maybeDate(j['activatedAt'] ?? j['startDate']),
      completedAt: _maybeDate(j['completedAt']),
      frozenAt: _maybeDate(j['frozenAt']),
      frozenReason: j['frozenReason']?.toString(),
      initiator: j['initiator'] is Map<String, dynamic>
          ? SusuInitiator.fromJson(j['initiator'] as Map<String, dynamic>)
          : null,
      members: ((j['members'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SusuMemberView.fromJson)
          .toList(),
      cycles: ((j['cycles'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SusuCycleView.fromJson)
          .toList(),
    );
  }
}

class SusuInitiator {
  final int id;
  final String displayName;
  const SusuInitiator({required this.id, required this.displayName});
  factory SusuInitiator.fromJson(Map<String, dynamic> j) => SusuInitiator(
        id: (j['id'] as num).toInt(),
        displayName:
            (j['displayName'] ?? j['username'] ?? 'Unknown').toString(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SusuMemberView — privacy-projected roster entry (Property 15 / Req 5.4)
// Only displayName, avatar, payoutSlot, status, role.
// ─────────────────────────────────────────────────────────────────────────────

class SusuMemberView {
  final String susuMemberId;
  final int userId; // safe — used for 'isMe' comparisons client-side
  final String displayName;
  final String? avatar;
  final int? cycleSlot;
  final SusuMemberStatus status;
  final String role;
  final bool autoRetainNextCycle;

  const SusuMemberView({
    required this.susuMemberId,
    required this.userId,
    required this.displayName,
    required this.avatar,
    required this.cycleSlot,
    required this.status,
    required this.role,
    this.autoRetainNextCycle = false,
  });

  factory SusuMemberView.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    return SusuMemberView(
      susuMemberId: (j['susuMemberId'] ?? j['id']).toString(),
      userId: ((j['userId'] ?? user?['id'] ?? 0) as num).toInt(),
      displayName: (j['displayName'] ??
              user?['displayName'] ??
              user?['username'] ??
              'Member')
          .toString(),
      avatar: (j['avatar'] ?? user?['profileImage'] ?? user?['profilePictureUrl'])
          ?.toString(),
      cycleSlot: (j['cycleSlot'] ?? j['payoutSlot']) is num
          ? (j['cycleSlot'] ?? j['payoutSlot'] as num).toInt()
          : null,
      status: SusuMemberStatus.fromString(j['status']),
      role: (j['role'] ?? 'MEMBER').toString(),
      autoRetainNextCycle: j['autoRetainNextCycle'] == true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SusuCycleView — schedule entry on the dashboard
// ─────────────────────────────────────────────────────────────────────────────

class SusuCycleView {
  final String id;
  final int cycleNumber;
  final DateTime scheduledRunAt;
  final SusuCycleStatus status;
  final int payoutUserId;
  final DateTime? paidOutAt;
  final DateTime? escrowDivertedAt;
  final double? payoutAmount;
  final DateTime? graceUntil;

  const SusuCycleView({
    required this.id,
    required this.cycleNumber,
    required this.scheduledRunAt,
    required this.status,
    required this.payoutUserId,
    required this.paidOutAt,
    required this.escrowDivertedAt,
    required this.payoutAmount,
    this.graceUntil,
  });

  factory SusuCycleView.fromJson(Map<String, dynamic> j) => SusuCycleView(
        id: j['id'].toString(),
        cycleNumber: (j['cycleNumber'] as num).toInt(),
        scheduledRunAt: DateTime.parse(
            (j['scheduledRunAt'] ?? j['collectionDate']).toString()),
        status: SusuCycleStatus.fromString(j['status']),
        payoutUserId:
            ((j['payoutUserId'] ?? j['payoutRecipientId']) as num).toInt(),
        paidOutAt: _maybeDate(j['paidOutAt']),
        escrowDivertedAt: _maybeDate(j['escrowDivertedAt']),
        payoutAmount: j['payoutAmount'] == null
            ? null
            : _decimalToDouble(j['payoutAmount']),
        graceUntil: _maybeDate(j['graceUntil']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SusuInvitePreview — the public-route /preview/:token shape (no JWT)
// ─────────────────────────────────────────────────────────────────────────────

class SusuInvitePreview {
  final String susuName;
  final double contributionUsdc;
  final SusuFrequency frequency;
  final int memberCount;
  final String inviterDisplayName;
  final String? inviterAvatar;
  final DateTime expiresAt;

  const SusuInvitePreview({
    required this.susuName,
    required this.contributionUsdc,
    required this.frequency,
    required this.memberCount,
    required this.inviterDisplayName,
    required this.inviterAvatar,
    required this.expiresAt,
  });

  factory SusuInvitePreview.fromJson(Map<String, dynamic> j) {
    final susu = j['susu'] as Map<String, dynamic>? ?? const {};
    final inviter = j['inviter'] as Map<String, dynamic>? ?? const {};
    return SusuInvitePreview(
      susuName: (susu['name'] ?? 'Susu').toString(),
      contributionUsdc: _decimalToDouble(
          susu['contributionUsdc'] ?? susu['contributionAmount']),
      frequency: SusuFrequency.fromString(susu['frequency']),
      memberCount: ((susu['memberCount'] ?? 0) as num).toInt(),
      inviterDisplayName:
          (inviter['displayName'] ?? inviter['username'] ?? 'Someone')
              .toString(),
      inviterAvatar:
          (inviter['avatar'] ?? inviter['profileImage'])?.toString(),
      expiresAt: DateTime.parse(j['expiresAt'].toString()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liability contract payload returned from GET /api/susu/groups/:id/contract
// ─────────────────────────────────────────────────────────────────────────────

class LiabilityContract {
  final String version;
  final String contractHash;
  final String body;
  final DateTime publishedAt;

  const LiabilityContract({
    required this.version,
    required this.contractHash,
    required this.body,
    required this.publishedAt,
  });

  factory LiabilityContract.fromJson(Map<String, dynamic> j) =>
      LiabilityContract(
        version: j['version'].toString(),
        contractHash: j['contractHash'].toString(),
        body: j['body'].toString(),
        publishedAt: DateTime.parse(j['publishedAt'].toString()),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Invite-builder request payload, used by SusuCreateScreen → susu_service
// ─────────────────────────────────────────────────────────────────────────────

class SusuInviteRequest {
  final SusuInviteChannel channel;
  final int? inviteeUserId;
  final String? inviteePhone;

  const SusuInviteRequest._({
    required this.channel,
    this.inviteeUserId,
    this.inviteePhone,
  });

  factory SusuInviteRequest.friend(int userId) => SusuInviteRequest._(
      channel: SusuInviteChannel.friend, inviteeUserId: userId);

  factory SusuInviteRequest.phone(String e164) => SusuInviteRequest._(
      channel: SusuInviteChannel.phone, inviteePhone: e164);

  factory SusuInviteRequest.link() =>
      const SusuInviteRequest._(channel: SusuInviteChannel.link);

  Map<String, dynamic> toJson() => switch (channel) {
        SusuInviteChannel.friend => {
            'channel': 'FRIEND',
            'inviteeUserId': inviteeUserId,
          },
        SusuInviteChannel.phone => {
            'channel': 'PHONE',
            'inviteePhone': inviteePhone,
          },
        SusuInviteChannel.link => {'channel': 'LINK'},
        SusuInviteChannel.unknown => const {},
      };
}

// Result of POST /api/susu — initial Susu + the fanned invites.
class SusuCreateResult {
  final SusuDetail susu;
  final List<SusuInviteRow> invites;

  const SusuCreateResult({required this.susu, required this.invites});
}

class SusuInviteRow {
  final String id;
  final SusuInviteChannel channel;
  final SusuInviteStatus status;
  final DateTime expiresAt;
  final String? token;
  final int? inviteeUserId;
  final String? inviteePhone;

  const SusuInviteRow({
    required this.id,
    required this.channel,
    required this.status,
    required this.expiresAt,
    required this.token,
    required this.inviteeUserId,
    required this.inviteePhone,
  });

  factory SusuInviteRow.fromJson(Map<String, dynamic> j) => SusuInviteRow(
        id: j['id'].toString(),
        channel: SusuInviteChannel.fromString(j['channel']),
        status: SusuInviteStatus.fromString(j['status']),
        expiresAt: DateTime.parse(j['expiresAt'].toString()),
        token: j['token']?.toString(),
        inviteeUserId: j['inviteeUserId'] is num
            ? (j['inviteeUserId'] as num).toInt()
            : null,
        inviteePhone: j['inviteePhone']?.toString(),
      );

  /// Public Invite_Link URL for LINK-channel invites (Req 6.6).
  String? get publicUrl =>
      token == null ? null : 'https://azaman.app/susu/invite/$token';
}
