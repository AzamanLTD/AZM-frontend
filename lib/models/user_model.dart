/// KYC verification status, mirrored from the backend's `KycStatus` enum
/// (UNVERIFIED / PENDING / VERIFIED / REJECTED). Default is UNVERIFIED so
/// older API responses without the field still parse safely.
enum KycStatus {
  unverified,
  pending,
  verified,
  rejected;

  /// Parse from the upstream string (case-insensitive). Falls back to
  /// [unverified] for unknown / null values.
  static KycStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'VERIFIED':
        return KycStatus.verified;
      case 'PENDING':
        return KycStatus.pending;
      case 'REJECTED':
        return KycStatus.rejected;
      case 'UNVERIFIED':
      default:
        return KycStatus.unverified;
    }
  }

  /// Wire-format string (UPPER-CASE) for outbound API calls.
  String get wire {
    switch (this) {
      case KycStatus.verified:
        return 'VERIFIED';
      case KycStatus.pending:
        return 'PENDING';
      case KycStatus.rejected:
        return 'REJECTED';
      case KycStatus.unverified:
        return 'UNVERIFIED';
    }
  }
}

/// Banned-status mirror of the backend `BanStatus` enum.
/// `active` = unrestricted. Anything else is the Ghost Ban (read-only).
enum BanStatus {
  active,
  banned24h,
  banned1w,
  bannedIndef;

  static BanStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'BANNED_24H':
        return BanStatus.banned24h;
      case 'BANNED_1W':
        return BanStatus.banned1w;
      case 'BANNED_INDEF':
        return BanStatus.bannedIndef;
      case 'ACTIVE':
      default:
        return BanStatus.active;
    }
  }

  String get wire {
    switch (this) {
      case BanStatus.banned24h:
        return 'BANNED_24H';
      case BanStatus.banned1w:
        return 'BANNED_1W';
      case BanStatus.bannedIndef:
        return 'BANNED_INDEF';
      case BanStatus.active:
        return 'ACTIVE';
    }
  }

  bool get isActive => this == BanStatus.active;
}

class User {
  final String id;
  final String username;
  final String email;
  final String token;
  final String role;

  // ── V2 Great Account Split (the Master Soul §2) ──
  final double availableBalance;
  final double vendorUnallocatedBalance;
  final double escrowLockedBalance;
  final double disputeEscrowBalance;

  // AZM token balance (1 AZM = 1 GHS, internal hologram unit).
  // Phase J (2026-05-25) dropped the legacy `lockedBalance` and `ghsBalance`
  // fields — both were write-dead V1 columns. Active escrow now lives in
  // `escrowLockedBalance`; GHS is derived as `availableBalance ×
  // yellowCardRate` on read (the hologram model).
  final double azmBalance;

  // Compliance + status
  final KycStatus kycStatus;
  final BanStatus banStatus;
  final DateTime? banUntil;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
    required this.role,
    this.availableBalance = 0.0,
    this.vendorUnallocatedBalance = 0.0,
    this.escrowLockedBalance = 0.0,
    this.disputeEscrowBalance = 0.0,
    this.azmBalance = 0.0,
    this.kycStatus = KycStatus.unverified,
    this.banStatus = BanStatus.active,
    this.banUntil,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final id = json['id'].toString();
    final role = (json['role']?.toString().toUpperCase() ?? 'USER');

    double toDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    DateTime? toDate(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    return User(
      id: id,
      username: json['username']?.toString() ?? 'Unknown',
      email: json['email']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      role: role,
      availableBalance:         toDouble(json['availableBalance']),
      vendorUnallocatedBalance: toDouble(json['vendorUnallocatedBalance']),
      escrowLockedBalance:      toDouble(json['escrowLockedBalance']),
      disputeEscrowBalance:     toDouble(json['disputeEscrowBalance']),
      azmBalance:               toDouble(json['azmBalance']),
      kycStatus:                KycStatus.fromString(json['kycStatus']),
      banStatus:                BanStatus.fromString(json['banStatus']),
      banUntil:                 toDate(json['banUntil']),
    );
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? token,
    String? role,
    double? availableBalance,
    double? vendorUnallocatedBalance,
    double? escrowLockedBalance,
    double? disputeEscrowBalance,
    double? azmBalance,
    KycStatus? kycStatus,
    BanStatus? banStatus,
    DateTime? banUntil,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      token: token ?? this.token,
      role: role ?? this.role,
      availableBalance:         availableBalance         ?? this.availableBalance,
      vendorUnallocatedBalance: vendorUnallocatedBalance ?? this.vendorUnallocatedBalance,
      escrowLockedBalance:      escrowLockedBalance      ?? this.escrowLockedBalance,
      disputeEscrowBalance:     disputeEscrowBalance     ?? this.disputeEscrowBalance,
      azmBalance:               azmBalance               ?? this.azmBalance,
      kycStatus:                kycStatus                ?? this.kycStatus,
      banStatus:                banStatus                ?? this.banStatus,
      banUntil:                 banUntil                 ?? this.banUntil,
    );
  }
}
