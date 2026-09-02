// lib/models/marketplace_extensions_models.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS MODELS (v2, 2026-07-03)
// =============================================================================


double _decimalToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _jsonInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

// ── FollowState ─────────────────────────────────────────────────────────────
class FollowState {
  final bool isFollowing;
  final int followerCount;

  FollowState({required this.isFollowing, required this.followerCount});

  factory FollowState.fromJson(Map<String, dynamic> json) => FollowState(
    isFollowing: json['isFollowing'] ?? false,
    followerCount: json['followerCount'] ?? 0,
  );
}

// ── BusinessAdPost ──────────────────────────────────────────────────────────
class BusinessAdPost {
  final String id;
  final String templateType;
  final String title;
  final String? bodyText;
  final String? mediaUrl;
  final String? ctaLabel;
  final String? ctaTarget;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String businessName;
  final String? businessLogoUrl;
  final bool isVerified;

  BusinessAdPost({
    required this.id,
    required this.templateType,
    required this.title,
    this.bodyText,
    this.mediaUrl,
    this.ctaLabel,
    this.ctaTarget,
    required this.expiresAt,
    required this.createdAt,
    required this.businessName,
    this.businessLogoUrl,
    this.isVerified = false,
  });

  factory BusinessAdPost.fromJson(Map<String, dynamic> json) => BusinessAdPost(
    id: json['id'],
    templateType: json['templateType'] ?? 'PROMO',
    title: json['title'] ?? '',
    bodyText: json['bodyText'],
    mediaUrl: json['mediaUrl'],
    ctaLabel: json['ctaLabel'],
    ctaTarget: json['ctaTarget'],
    expiresAt: DateTime.parse(json['expiresAt']),
    createdAt: DateTime.parse(json['createdAt']),
    businessName: json['businessProfile']?['businessName'] ?? '',
    businessLogoUrl: json['businessProfile']?['logoUrl'],
    isVerified: json['businessProfile']?['isVerified'] ?? false,
  );
}

// ── DineInTab ───────────────────────────────────────────────────────────────
class DineInTab {
  final String id;
  final String status;
  final DateTime openedAt;
  final double subtotal;
  final double taxTotal;
  final double tip;
  final double grandTotal;
  final String? invoiceRef;
  final String businessName;
  final String? businessProfileId;
  final String? businessBizId;
  final String? businessLogoUrl;
  final String? tableId;
  final String? tableLabel;
  final String? locationId;
  final List<DineInTabItem> items;

  DineInTab({
    required this.id,
    required this.status,
    required this.openedAt,
    required this.subtotal,
    required this.taxTotal,
    required this.tip,
    required this.grandTotal,
    this.invoiceRef,
    required this.businessName,
    this.businessProfileId,
    this.businessBizId,
    this.businessLogoUrl,
    this.tableId,
    this.tableLabel,
    this.locationId,
    required this.items,
  });

  factory DineInTab.fromJson(Map<String, dynamic> json) {
    final business = json['businessProfile'] is Map
        ? Map<String, dynamic>.from(json['businessProfile'] as Map)
        : const <String, dynamic>{};
    final table = json['table'] is Map
        ? Map<String, dynamic>.from(json['table'] as Map)
        : const <String, dynamic>{};
    return DineInTab(
      id: json['id'],
      status: json['status'] ?? 'OPEN',
      openedAt: DateTime.parse(json['openedAt']),
      subtotal: _decimalToDouble(json['subtotalUsdc']),
      taxTotal: _decimalToDouble(json['taxTotalUsdc']),
      tip: _decimalToDouble(json['tipUsdc']),
      grandTotal: _decimalToDouble(json['grandTotalUsdc']),
      invoiceRef: json['invoice']?['invoiceRef'],
      businessName: business['businessName'] ?? '',
      businessProfileId: business['id']?.toString(),
      businessBizId: business['bizId']?.toString(),
      businessLogoUrl: business['logoUrl'],
      tableId: (json['tableId'] ?? table['id'])?.toString(),
      tableLabel: table['label']?.toString(),
      locationId: (json['locationId'] ?? table['locationId'])?.toString(),
      items: (json['items'] as List?)
              ?.whereType<Map>()
              .map((e) => DineInTabItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }
}

class DineInTabItem {
  final String id;
  final String name;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final DateTime addedAt;

  DineInTabItem({
    required this.id,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.addedAt,
  });

  factory DineInTabItem.fromJson(Map<String, dynamic> json) => DineInTabItem(
    id: json['id'],
    name: json['name'] ?? '',
    unitPrice: _decimalToDouble(json['unitPriceUsdc']),
    quantity: _jsonInt(json['quantity'], fallback: 1),
    lineTotal: _decimalToDouble(json['lineTotalUsdc']),
    addedAt: DateTime.parse(json['addedAt']),
  );
}

// ── BusinessShowcase ────────────────────────────────────────────────────────
class BusinessShowcase {
  final String id;
  final String mediaUrl;
  final String mediaType;
  final String? thumbnailUrl;
  final String? caption;
  final int displayOrder;

  BusinessShowcase({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.caption,
    required this.displayOrder,
  });

  factory BusinessShowcase.fromJson(Map<String, dynamic> json) => BusinessShowcase(
    id: json['id'],
    mediaUrl: json['mediaUrl'] ?? '',
    mediaType: json['mediaType'] ?? 'IMAGE',
    thumbnailUrl: json['thumbnailUrl'],
    caption: json['caption'],
    displayOrder: json['displayOrder'] ?? 0,
  );
}

// ── TrustScore ──────────────────────────────────────────────────────────────
class TrustScore {
  final String trustLevel;
  final double noShowRate;
  final int totalBookings;
  final int noShowCount;
  final int completedBookings;

  TrustScore({
    required this.trustLevel,
    required this.noShowRate,
    required this.totalBookings,
    required this.noShowCount,
    required this.completedBookings,
  });

  factory TrustScore.fromJson(Map<String, dynamic> json) => TrustScore(
    trustLevel: json['trustLevel'] ?? 'GOOD',
    noShowRate: _decimalToDouble(json['noShowRate']),
    totalBookings: _jsonInt(json['totalBookings']),
    noShowCount: _jsonInt(json['noShowCount']),
    completedBookings: _jsonInt(json['completedBookings']),
  );

  String get colorHex {
    switch (trustLevel) {
      case 'EXCELLENT': return '#22C55E';
      case 'GOOD': return '#3B82F6';
      case 'CAUTION': return '#F59E0B';
      case 'RISK': return '#EF4444';
      default: return '#6B7280';
    }
  }
}
