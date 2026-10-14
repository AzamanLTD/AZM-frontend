// =============================================================================
// AZAMAN — MARKETPLACE MIX: CATEGORY-FIRST, CROSS-STORE DISCOVERY (models)
//
// Mix is the category-first browse mode from the Marketplace Mix redesign
// (AZM-Planning, MARKETPLACE_MIX_REDESIGN_2026-10-10.md): the user picks a
// CATEGORY (Eat, Shop, Ride, Stay) and discovers items across MANY businesses
// in that category, with the offering business shown beside every item.
//
// CAPABILITY TRUTH (the gateway in
// `experience/gateways/marketplace_mix_gateway.dart` reports the same set):
//
//   SUPPORTED by today's backend contracts:
//     • Cross-store category browse — composed from the REAL public
//       endpoints `GET /api/business/search?category=…` (store discovery) and
//       `GET /api/business/:bizId/products` (per-store listings). No Mix DTO
//       exists server-side yet; this model maps those payloads only.
//     • Item identity + offering business identity together (the offer pair
//       `businessProfileId + productId`).
//     • The USDC list price (`priceUsdc`) — the only price the public
//       product payloads carry today.
//     • Availability (`isAvailable`) — present on the raw rows of
//       `/business/:bizId/products`.
//     • Item+store interaction recording — the REAL
//       `POST /api/storefront/:businessProfileId/events` contract with the
//       allow-listed `product_tap` event type.
//
//   NOT supported by today's backend contracts (never fabricated here):
//     • GHS listing prices. `BusinessPrice` (backend main) is Phase 1:
//       schema + validation, NO public surface, and the GHS contract forbids
//       converting or relabelling `priceUsdc` as GHS. Offers therefore render
//       their USDC list price via `AzMoney.usdc` and NEVER a GHS figure until
//       the backend exposes business-confirmed GHS prices (Mix P3).
//     • Price-on-request. No quotation-pricing opt-in flag exists on any
//       public payload; the state is never inferred from a missing price.
//     • Same-item-across-stores grouping. `BusinessProduct` identity is
//       per-business; there is no global item id, so offers are never merged
//       by name or slug similarity.
//     • Server-side ranking / analytics-backed labels. Mix renders offers in
//       server order (round-robin interleave across stores is presentation
//       only and never claimed as ranking).
//
// HONEST PRICE RULES (pin in tests):
//   • A missing/null price is `MixOfferPrice.unknown` — it NEVER becomes 0.
//   • Availability is never inferred from the existence of a price.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

/// One Mix category. Wire values are the SAME contract `kDiscoveryIntents`
/// (intent_rail.dart) and the category speed dial already send to
/// `/api/business/search` — do not invent new wire values.
class MixCategory {
  final String wire;
  final String label;
  final IconData icon;

  const MixCategory({
    required this.wire,
    required this.label,
    required this.icon,
  });

  static const List<MixCategory> values = [
    MixCategory(wire: 'FOOD_BEVERAGE', label: 'Eat', icon: HugeIconsSolid.restaurant01),
    MixCategory(wire: 'RETAIL', label: 'Shop', icon: HugeIconsSolid.shoppingBag01),
    MixCategory(wire: 'LOGISTICS', label: 'Ride', icon: HugeIconsSolid.bus01),
    MixCategory(wire: 'HOSPITALITY', label: 'Stay', icon: HugeIconsSolid.hotel01),
  ];

  static MixCategory? byWire(String? wire) {
    if (wire == null) return null;
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// The honest price states an offer can be in, from REAL payload data only.
///
/// `fixed` — the payload carried a price for this offer. Today that is always
///   the USDC list price (`priceUsdc`); the currency is carried explicitly so a
///   future GHS field maps to the same state without touching rendering.
/// `unknown` — the payload carried NO price. Rendered as "Price unavailable",
///   never as a zero amount.
///
/// `price-on-request` is deliberately absent: no public payload carries a
/// quotation-pricing opt-in today, and the GHS contract forbids inferring it
/// from a missing price. It becomes a real state when the backend ships the
/// per-item opt-in flag.
enum MixPriceStatus { fixed, unknown }

class MixOfferPrice {
  final MixPriceStatus status;
  final double amount;
  final String currency;

  const MixOfferPrice._({
    required this.status,
    this.amount = 0,
    this.currency = 'USDC',
  });

  const MixOfferPrice.fixed(this.amount, {this.currency = 'USDC'})
      : status = MixPriceStatus.fixed;

  const MixOfferPrice.unknown()
      : this._(status: MixPriceStatus.unknown);

  bool get isKnown => status == MixPriceStatus.fixed;
}

/// One item listing offered by ONE business — the atomic Mix unit.
///
/// Identity invariants (pinned in tests):
///   • [offerKey] is `<businessProfileId>:<productId>` — the item+store pair.
///     Two rows with the same product name in different stores are DIFFERENT
///     offers and are never merged.
///   • [businessProfileId], [bizId] and [productId] stay distinct fields; the
///     cart flow and the store route consume `bizId`, interaction tracking
///     consumes `businessProfileId` (its real contract), item identity is
///     `productId`.
class MixOffer {
  final String productId;
  final String businessProfileId;
  final String bizId;
  final String businessName;
  final String businessCategory;
  final String name;
  final String? description;
  final List<String> imageUrls;
  final List<String> tags;
  final MixOfferPrice price;

  /// Raw availability from the payload. `null` = the payload did not carry the
  /// field (demo seeds) — rendered with NO availability badge, never as
  /// "available" and never as "unavailable".
  final bool? isAvailable;

  final String? locationId;

  const MixOffer({
    required this.productId,
    required this.businessProfileId,
    required this.bizId,
    required this.businessName,
    required this.businessCategory,
    required this.name,
    required this.price,
    this.description,
    this.imageUrls = const [],
    this.tags = const [],
    this.isAvailable,
    this.locationId,
  });

  /// The item+store pair identity. Stable across rebuilds; used as the list
  /// key and the interaction identity.
  String get offerKey => '$businessProfileId:$productId';

  String? get primaryImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  /// Parses one raw row of `GET /api/business/:bizId/products` plus the
  /// business context from `GET /api/business/search`.
  ///
  /// Decimals arrive as numbers OR strings (Prisma Decimal serializes to a
  /// string); `_parseAmount` accepts both. A `null`/absent price parses to
  /// [MixOfferPrice.unknown] — NEVER to zero.
  static MixOffer fromJson(
    Map<String, dynamic> json, {
    required String businessProfileId,
    required String bizId,
    required String businessName,
    required String businessCategory,
  }) {
    final amount = _parseAmount(json['priceUsdc']);
    final price = amount == null
        ? const MixOfferPrice.unknown()
        : MixOfferPrice.fixed(amount, currency: 'USDC');

    return MixOffer(
      productId: (json['id'] ?? '').toString(),
      businessProfileId: businessProfileId,
      bizId: bizId,
      businessName: businessName,
      businessCategory: businessCategory,
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      imageUrls: _toStringList(json['imageUrls']),
      tags: _toStringList(json['tags']),
      price: price,
      isAvailable: json['isAvailable'] == null ? null : json['isAvailable'] == true,
      locationId: json['locationId']?.toString(),
    );
  }

  /// Accepts num or numeric string; returns null for null/absent/unparseable.
  /// A missing price must stay missing — the caller turns null into `unknown`.
  static double? _parseAmount(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed);
    }
    return null;
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      other is MixOffer &&
      other.offerKey == offerKey &&
      other.businessName == businessName &&
      other.name == name;

  @override
  int get hashCode => offerKey.hashCode;
}

/// A business participating in the current Mix feed — the store side of every
/// offer pair. `id` is `BusinessProfile.id` (what `POST /api/storefront/:id/events`
/// actually takes); `bizId` is what the store route `/business/:bizId` takes.
class MixStore {
  final String id;
  final String bizId;
  final String businessName;
  final String category;

  const MixStore({
    required this.id,
    required this.bizId,
    required this.businessName,
    required this.category,
  });

  @override
  bool operator ==(Object other) =>
      other is MixStore && other.id == id && other.bizId == bizId;

  @override
  int get hashCode => id.hashCode;
}
