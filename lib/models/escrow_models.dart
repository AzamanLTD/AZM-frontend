// =============================================================================
// ESCROW MODELS — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Mirrors the Smart Escrow tables in the AZM backend (prisma/schema.prisma
// `SmartEscrow`, `EscrowDispute`). Follows the `Ticket` model pattern:
// all fields final, a single `fromJson` factory, `double.tryParse` for the
// Decimal columns and `int.tryParse` for the integer foreign keys (Flutter
// `User.id` is a String, backend `User.id` is an Int — compare via
// `int.tryParse(currentUser.id) == escrow.payerId`).
//
// The backend wraps every escrow response in `{ success: true, escrow: {...} }`
// (or `{ success, settled, escrow }`). The service unwraps the envelope; these
// models parse the inner escrow object. Nested `payer` / `payee` / `dispute`
// are parsed defensively (nullable) because not every endpoint includes them.
// =============================================================================

/// Lifecycle state of a Smart Escrow. Wire values are the upper-snake enum
/// from `EscrowStatus` in the Prisma schema.
enum EscrowStatus {
  draft,
  funded,
  inProgress,
  pendingSettlement,
  settled,
  disputed,
  adminReview,
  released,
  refunded,
  expired;

  static EscrowStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'DRAFT':
        return EscrowStatus.draft;
      case 'FUNDED':
        return EscrowStatus.funded;
      case 'IN_PROGRESS':
        return EscrowStatus.inProgress;
      case 'PENDING_SETTLEMENT':
        return EscrowStatus.pendingSettlement;
      case 'SETTLED':
        return EscrowStatus.settled;
      case 'DISPUTED':
        return EscrowStatus.disputed;
      case 'ADMIN_REVIEW':
        return EscrowStatus.adminReview;
      case 'RELEASED':
        return EscrowStatus.released;
      case 'REFUNDED':
        return EscrowStatus.refunded;
      case 'EXPIRED':
        return EscrowStatus.expired;
      default:
        return EscrowStatus.draft;
    }
  }

  /// Human label for the status pill.
  String get label {
    switch (this) {
      case EscrowStatus.draft:
        return 'Draft';
      case EscrowStatus.funded:
        return 'Funded';
      case EscrowStatus.inProgress:
        return 'In Progress';
      case EscrowStatus.pendingSettlement:
        return 'Pending Settlement';
      case EscrowStatus.settled:
        return 'Settled';
      case EscrowStatus.disputed:
        return 'Disputed';
      case EscrowStatus.adminReview:
        return 'Admin Review';
      case EscrowStatus.released:
        return 'Released';
      case EscrowStatus.refunded:
        return 'Refunded';
      case EscrowStatus.expired:
        return 'Expired';
    }
  }

  /// Terminal states — no further actions possible (see Section 15 lifecycle).
  bool get isTerminal =>
      this == EscrowStatus.settled ||
      this == EscrowStatus.released ||
      this == EscrowStatus.refunded ||
      this == EscrowStatus.expired;

  /// Active states where money is locked and the deal is live.
  bool get isActive =>
      this == EscrowStatus.funded ||
      this == EscrowStatus.inProgress ||
      this == EscrowStatus.pendingSettlement;
}

/// Dispute lifecycle, from `DisputeStatus` in the schema.
enum DisputeStatus {
  pending,
  assigned,
  underReview,
  resolved;

  static DisputeStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'ASSIGNED':
        return DisputeStatus.assigned;
      case 'UNDER_REVIEW':
        return DisputeStatus.underReview;
      case 'RESOLVED':
        return DisputeStatus.resolved;
      case 'PENDING':
      default:
        return DisputeStatus.pending;
    }
  }
}

/// Final ruling on a resolved dispute, from `DisputeRuling` in the schema.
enum DisputeRuling {
  fullRelease,
  fullRefund,
  split;

  static DisputeRuling? fromString(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().toUpperCase().trim();
    switch (s) {
      case 'FULL_RELEASE':
        return DisputeRuling.fullRelease;
      case 'FULL_REFUND':
        return DisputeRuling.fullRefund;
      case 'SPLIT':
        return DisputeRuling.split;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case DisputeRuling.fullRelease:
        return 'Full Release';
      case DisputeRuling.fullRefund:
        return 'Full Refund';
      case DisputeRuling.split:
        return 'Split';
    }
  }
}

/// Minimal counterparty profile embedded on an escrow (when the backend
/// includes the `payer` / `payee` relation).
class EscrowParticipant {
  final int id;
  final String username;
  final String? profilePictureUrl;

  const EscrowParticipant({
    required this.id,
    required this.username,
    this.profilePictureUrl,
  });

  factory EscrowParticipant.fromJson(Map<String, dynamic> json) {
    return EscrowParticipant(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      username: (json['username'] ?? 'Unknown').toString(),
      profilePictureUrl: json['profilePictureUrl']?.toString(),
    );
  }
}

/// Dispute attached to an escrow.
class EscrowDisputeModel {
  final String id;
  final String escrowId;
  final int raisedById;
  final String reason;
  final List<String> evidenceUrls;
  final DisputeStatus status;
  final DisputeRuling? ruling;
  final String? rulingNotes;
  final DateTime createdAt;

  const EscrowDisputeModel({
    required this.id,
    required this.escrowId,
    required this.raisedById,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.evidenceUrls = const [],
    this.ruling,
    this.rulingNotes,
  });

  factory EscrowDisputeModel.fromJson(Map<String, dynamic> json) {
    final urls = json['evidenceUrls'];
    return EscrowDisputeModel(
      id: json['id'].toString(),
      escrowId: (json['escrowId'] ?? '').toString(),
      raisedById: json['raisedById'] is int
          ? json['raisedById'] as int
          : int.tryParse(json['raisedById'].toString()) ?? 0,
      reason: (json['reason'] ?? '').toString(),
      evidenceUrls:
          urls is List ? urls.map((e) => e.toString()).toList() : const [],
      status: DisputeStatus.fromString(json['status']),
      ruling: DisputeRuling.fromString(json['ruling']),
      rulingNotes: json['rulingNotes']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SmartEscrow {
  final String id;
  final String ticketId;
  final int payerId;
  final int payeeId;
  final double amountUsdc;
  final double feeUsdc;
  final EscrowStatus status;
  final bool payerSatisfied;
  final bool payeeSatisfied;
  final String? deliveryTerms;
  final DateTime? dueDate;
  final DateTime? fundedAt;
  final DateTime? settledAt;
  final DateTime? expiresAt;
  final EscrowParticipant? payer;
  final EscrowParticipant? payee;
  final EscrowDisputeModel? dispute;

  const SmartEscrow({
    required this.id,
    required this.ticketId,
    required this.payerId,
    required this.payeeId,
    required this.amountUsdc,
    required this.feeUsdc,
    required this.status,
    required this.payerSatisfied,
    required this.payeeSatisfied,
    this.deliveryTerms,
    this.dueDate,
    this.fundedAt,
    this.settledAt,
    this.expiresAt,
    this.payer,
    this.payee,
    this.dispute,
  });

  /// Total amount locked: principal + platform fee.
  double get totalLocked => amountUsdc + feeUsdc;

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory SmartEscrow.fromJson(Map<String, dynamic> json) {
    return SmartEscrow(
      id: json['id'].toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      payerId: _toInt(json['payerId']),
      payeeId: _toInt(json['payeeId']),
      amountUsdc: _toDouble(json['amountUsdc']),
      feeUsdc: _toDouble(json['feeUsdc']),
      status: EscrowStatus.fromString(json['status']),
      payerSatisfied: json['payerSatisfied'] == true,
      payeeSatisfied: json['payeeSatisfied'] == true,
      deliveryTerms: json['deliveryTerms']?.toString(),
      dueDate: _toDate(json['dueDate']),
      fundedAt: _toDate(json['fundedAt']),
      settledAt: _toDate(json['settledAt']),
      expiresAt: _toDate(json['expiresAt']),
      payer: json['payer'] is Map<String, dynamic>
          ? EscrowParticipant.fromJson(json['payer'] as Map<String, dynamic>)
          : null,
      payee: json['payee'] is Map<String, dynamic>
          ? EscrowParticipant.fromJson(json['payee'] as Map<String, dynamic>)
          : null,
      dispute: json['dispute'] is Map<String, dynamic>
          ? EscrowDisputeModel.fromJson(json['dispute'] as Map<String, dynamic>)
          : null,
    );
  }
}
