// =============================================================================
// AZAMAN — AZM SPEND SERVICE (Phase E2-FE)
//
// HTTP client for the /api/azm/spend/* endpoints:
//   GET  /api/azm/spend/options       — Available spend options + affordability
//   POST /api/azm/spend/fee-discount  — Apply fee discount (tierId)
//   POST /api/azm/spend/ad-boost      — Boost an ad (adId + boostId)
//   GET  /api/azm/spend/history       — Paginated spend history
//   GET  /api/azm/spend/card-skins        — Card skin catalog (2026-07-06)
//   POST /api/azm/spend/card-skin/purchase — Purchase a card skin (skinId)
//   POST /api/azm/spend/card-skin/equip    — Equip an owned card skin (skinId)
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class FeeDiscountTier {
  final String id;
  final String label;
  final double discount; // 0.25, 0.50, 1.00
  final double cost; // AZM cost
  final bool affordable;

  const FeeDiscountTier({
    required this.id,
    required this.label,
    required this.discount,
    required this.cost,
    required this.affordable,
  });

  factory FeeDiscountTier.fromJson(Map<String, dynamic> json) {
    return FeeDiscountTier(
      id: json['id'] as String,
      label: json['label'] as String,
      discount: (json['discount'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      affordable: json['affordable'] as bool? ?? false,
    );
  }

  /// Human-friendly description of what this tier does
  String get description {
    if (discount >= 1.0) return 'Free withdrawal (no exit fee)';
    return '${(discount * 100).toInt()}% off the 2% exit fee';
  }

  /// The effective fee percentage after this discount
  double get effectiveFeePercent => 0.02 * (1.0 - discount);
}

class AdBoostOption {
  final String id;
  final String label;
  final double cost; // AZM cost
  final bool affordable;

  const AdBoostOption({
    required this.id,
    required this.label,
    required this.cost,
    required this.affordable,
  });

  factory AdBoostOption.fromJson(Map<String, dynamic> json) {
    return AdBoostOption(
      id: json['id'] as String,
      label: json['label'] as String,
      cost: (json['cost'] as num).toDouble(),
      affordable: json['affordable'] as bool? ?? false,
    );
  }
}

class AzmSpendOptions {
  final double currentBalance;
  final List<FeeDiscountTier> feeDiscounts;
  final List<AdBoostOption> adBoosts;

  const AzmSpendOptions({
    required this.currentBalance,
    required this.feeDiscounts,
    required this.adBoosts,
  });

  factory AzmSpendOptions.fromJson(Map<String, dynamic> json) {
    return AzmSpendOptions(
      currentBalance: (json['currentBalance'] as num?)?.toDouble() ?? 0.0,
      feeDiscounts: (json['feeDiscounts'] as List? ?? [])
          .map((e) => FeeDiscountTier.fromJson(e as Map<String, dynamic>))
          .toList(),
      adBoosts: (json['adBoosts'] as List? ?? [])
          .map((e) => AdBoostOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FeeDiscountResult {
  final double discount;
  final String discountPercent;
  final double azmSpent;
  final double newAzmBalance;

  const FeeDiscountResult({
    required this.discount,
    required this.discountPercent,
    required this.azmSpent,
    required this.newAzmBalance,
  });

  factory FeeDiscountResult.fromJson(Map<String, dynamic> json) {
    return FeeDiscountResult(
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      discountPercent: json['discountPercent'] as String? ?? '',
      azmSpent: (json['azmSpent'] as num?)?.toDouble() ?? 0.0,
      newAzmBalance: (json['newAzmBalance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AdBoostResult {
  final int adId;
  final String boostDuration;
  final String boostExpiresAt;
  final double azmSpent;
  final double newAzmBalance;

  const AdBoostResult({
    required this.adId,
    required this.boostDuration,
    required this.boostExpiresAt,
    required this.azmSpent,
    required this.newAzmBalance,
  });

  factory AdBoostResult.fromJson(Map<String, dynamic> json) {
    return AdBoostResult(
      adId: (json['adId'] as num?)?.toInt() ?? 0,
      boostDuration: json['boostDuration'] as String? ?? '',
      boostExpiresAt: json['boostExpiresAt'] as String? ?? '',
      azmSpent: (json['azmSpent'] as num?)?.toDouble() ?? 0.0,
      newAzmBalance: (json['newAzmBalance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AzmSpendEntry {
  final String id;
  final double amount;
  final String reason;
  final String source;
  final Map<String, dynamic>? metadata;
  final double balanceAfter;
  final DateTime createdAt;

  const AzmSpendEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.source,
    this.metadata,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory AzmSpendEntry.fromJson(Map<String, dynamic> json) {
    return AzmSpendEntry(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String,
      source: json['source'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  String get sourceLabel {
    switch (source) {
      case 'FEE_DISCOUNT':
        return 'Fee Discount';
      case 'AD_BOOST':
        return 'Ad Boost';
      default:
        return source;
    }
  }

  String get sourceIcon {
    switch (source) {
      case 'FEE_DISCOUNT':
        return '\u{1F4B8}'; // money with wings
      case 'AD_BOOST':
        return '\u{1F680}'; // rocket
      default:
        return '\u{1F4A0}'; // diamond
    }
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

class AzmSpendService {
  /// Fetch available spend options with affordability context.
  Future<AzmSpendOptions> getSpendOptions() async {
    final response = await apiClient.get('/azm/spend/options');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AzmSpendOptions.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Apply a fee discount tier. Returns the discount result.
  /// Throws ApiException on insufficient AZM or other errors.
  Future<FeeDiscountResult> applyFeeDiscount(String tierId) async {
    final response = await apiClient.post('/azm/spend/fee-discount', {
      'tierId': tierId,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return FeeDiscountResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Boost an ad. Returns the boost result.
  /// Throws ApiException on insufficient AZM, not-owner, or inactive ad.
  Future<AdBoostResult> boostAd(int adId, String boostId) async {
    final response = await apiClient.post('/azm/spend/ad-boost', {
      'adId': adId,
      'boostId': boostId,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AdBoostResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Fetch paginated spend history.
  Future<({List<AzmSpendEntry> spends, String? nextCursor, bool hasMore})>
      getHistory({String? cursor, int limit = 20, String? source}) async {
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    if (source != null) params['source'] = source;

    final queryString =
        params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await apiClient.get('/azm/spend/history?$queryString');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;

    final spendsList = (data['spends'] as List)
        .map((s) => AzmSpendEntry.fromJson(s as Map<String, dynamic>))
        .toList();

    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

    return (
      spends: spendsList,
      nextCursor: pagination['nextCursor'] as String?,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  // ── Card skins (2026-07-06) ─────────────────────────────────────────────

  /// Fetch the card skin catalog with per-user ownership/equipped/affordability.
  Future<CardSkinCatalog> getCardSkinCatalog() async {
    final response = await apiClient.get('/azm/spend/card-skins');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CardSkinCatalog.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Purchase a card skin with AZM. Idempotent server-side — re-purchasing
  /// an already-owned skin is a no-op, not a double charge.
  /// Throws ApiException (code INSUFFICIENT_AZM) if the balance is too low.
  Future<CardSkinActionResult> purchaseCardSkin(String skinId) async {
    final response = await apiClient.post('/azm/spend/card-skin/purchase', {
      'skinId': skinId,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CardSkinActionResult.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Equip an owned card skin (or 'classic', always allowed). Free.
  /// Throws ApiException if the skin isn't owned yet.
  Future<String> equipCardSkin(String skinId) async {
    final response = await apiClient.post('/azm/spend/card-skin/equip', {
      'skinId': skinId,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    return data['equippedCardSkin'] as String? ?? skinId;
  }
}

// ── Card skins (2026-07-06) ──────────────────────────────────────────────────

class CardSkinOption {
  final String id;
  final String label;
  final double cost;
  final bool owned;
  final bool affordable;

  const CardSkinOption({
    required this.id,
    required this.label,
    required this.cost,
    required this.owned,
    required this.affordable,
  });

  factory CardSkinOption.fromJson(Map<String, dynamic> json) {
    return CardSkinOption(
      id: json['id'] as String,
      label: json['label'] as String,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      owned: json['owned'] as bool? ?? false,
      // Free skins (cost 0, e.g. classic) are always affordable.
      affordable: (json['affordable'] as bool?) ?? ((json['cost'] as num?)?.toDouble() ?? 0.0) == 0.0,
    );
  }
}

class CardSkinCatalog {
  final List<CardSkinOption> skins;
  final String equippedCardSkin;
  final double azmBalance;

  const CardSkinCatalog({
    required this.skins,
    required this.equippedCardSkin,
    required this.azmBalance,
  });

  factory CardSkinCatalog.fromJson(Map<String, dynamic> json) {
    return CardSkinCatalog(
      skins: (json['skins'] as List? ?? [])
          .map((e) => CardSkinOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      equippedCardSkin: json['equippedCardSkin'] as String? ?? 'classic',
      azmBalance: (json['azmBalance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CardSkinActionResult {
  final bool purchased;
  final List<String> ownedCardSkins;
  final double newBalance;

  const CardSkinActionResult({
    required this.purchased,
    required this.ownedCardSkins,
    required this.newBalance,
  });

  factory CardSkinActionResult.fromJson(Map<String, dynamic> json) {
    return CardSkinActionResult(
      purchased: json['purchased'] as bool? ?? false,
      ownedCardSkins: (json['ownedCardSkins'] as List? ?? []).map((e) => e.toString()).toList(),
      newBalance: (json['newBalance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Singleton instance
final AzmSpendService azmSpendService = AzmSpendService();
