// =============================================================================
// PROOF OF RESIDENCY MODEL — Phase 4 (Master Sprint, 2026-05-31)
//
// Wire-format model for the caller's own PoR status returned by
// GET /api/users/proof-of-residency/me. Per Req 3.12, the actual
// `proofOfResidencyUrl` is NEVER returned to the owning user — only
// admins see it via the queue endpoint. This model therefore omits
// it on principle.
// =============================================================================

enum ProofOfResidencyStatus {
  notSubmitted,
  pendingReview,
  verified,
  rejected,
  expired;

  static ProofOfResidencyStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'PENDING_REVIEW':
        return ProofOfResidencyStatus.pendingReview;
      case 'VERIFIED':
        return ProofOfResidencyStatus.verified;
      case 'REJECTED':
        return ProofOfResidencyStatus.rejected;
      case 'EXPIRED':
        return ProofOfResidencyStatus.expired;
      case 'NOT_SUBMITTED':
      default:
        return ProofOfResidencyStatus.notSubmitted;
    }
  }

  String get wire => switch (this) {
        ProofOfResidencyStatus.notSubmitted => 'NOT_SUBMITTED',
        ProofOfResidencyStatus.pendingReview => 'PENDING_REVIEW',
        ProofOfResidencyStatus.verified => 'VERIFIED',
        ProofOfResidencyStatus.rejected => 'REJECTED',
        ProofOfResidencyStatus.expired => 'EXPIRED',
      };

  String get label => switch (this) {
        ProofOfResidencyStatus.notSubmitted => 'Not submitted',
        ProofOfResidencyStatus.pendingReview => 'Pending review',
        ProofOfResidencyStatus.verified => 'Verified',
        ProofOfResidencyStatus.rejected => 'Rejected',
        ProofOfResidencyStatus.expired => 'Expired — re-upload required',
      };

  /// True iff the caller can submit a new PoR document. Mirrors Req 3.11.
  bool get canSubmit =>
      this == ProofOfResidencyStatus.notSubmitted ||
      this == ProofOfResidencyStatus.rejected ||
      this == ProofOfResidencyStatus.expired;
}

class ProofOfResidencyState {
  final ProofOfResidencyStatus status;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final String? rejectionReason;

  const ProofOfResidencyState({
    required this.status,
    required this.submittedAt,
    required this.verifiedAt,
    required this.rejectionReason,
  });

  const ProofOfResidencyState.notSubmitted()
      : status = ProofOfResidencyStatus.notSubmitted,
        submittedAt = null,
        verifiedAt = null,
        rejectionReason = null;

  factory ProofOfResidencyState.fromJson(Map<String, dynamic> j) =>
      ProofOfResidencyState(
        status: ProofOfResidencyStatus.fromString(
            j['proofOfResidencyStatus'] ?? j['status']),
        submittedAt: j['proofOfResidencySubmittedAt'] == null
            ? null
            : DateTime.tryParse(j['proofOfResidencySubmittedAt'].toString()),
        verifiedAt: j['proofOfResidencyVerifiedAt'] == null
            ? null
            : DateTime.tryParse(j['proofOfResidencyVerifiedAt'].toString()),
        rejectionReason: j['proofOfResidencyRejectionReason']?.toString(),
      );
}
