Data models for all new v2 features: followers, ads, dine-in tabs, showcase, trust scores.
// lib/models/marketplace_extensions_models.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS MODELS (v2, 2026-07-03)
// =============================================================================

import 'dart:convert';

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
  final String templateType; // PROMO, NEW_ITEM, EVENT, ANNOUNCEMENT
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
  final String status; // OPEN, FINALIZED, PAID, CLOSED, DEFAULTED
  final DateTime openedAt;
  final double subtotal;
  final double taxTotal;
  final double tip;
  final double grandTotal;
  final String? invoiceRef;
  final String businessName;
  final String? businessLogoUrl;
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
    this.businessLogoUrl,
    required this.items,
  });

  factory DineInTab.fromJson(Map<String, dynamic> json) => DineInTab(
    id: json['id'],
    status: json['status'] ?? 'OPEN',
    openedAt: DateTime.parse(json['openedAt']),
    subtotal: (json['subtotalUsdc'] as num?)?.toDouble() ?? 0,
    taxTotal: (json['taxTotalUsdc'] as num?)?.toDouble() ?? 0,
    tip: (json['tipUsdc'] as num?)?.toDouble() ?? 0,
    grandTotal: (json['grandTotalUsdc'] as num?)?.toDouble() ?? 0,
    invoiceRef: json['invoice']?['invoiceRef'],
    businessName: json['businessProfile']?['businessName'] ?? '',
    businessLogoUrl: json['businessProfile']?['logoUrl'],
    items: (json['items'] as List?)?.map((e) => DineInTabItem.fromJson(e)).toList() ?? [],
  );
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
    unitPrice: (json['unitPriceUsdc'] as num?)?.toDouble() ?? 0,
    quantity: json['quantity'] ?? 1,
    lineTotal: (json['lineTotalUsdc'] as num?)?.toDouble() ?? 0,
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
  final String trustLevel; // EXCELLENT, GOOD, CAUTION, RISK
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
    noShowRate: (json['noShowRate'] as num?)?.toDouble() ?? 0,
    totalBookings: json['totalBookings'] ?? 0,
    noShowCount: json['noShowCount'] ?? 0,
    completedBookings: json['completedBookings'] ?? 0,
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
