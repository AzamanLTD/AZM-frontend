// =============================================================================
// AZAMAN — MARKETPLACE MIX: CATEGORY-FIRST, CROSS-STORE DISCOVERY (models)
//
// Mix is the category-first browse mode from the Marketplace Mix redesign
// (AZM-Planning, MARKETPLACE_MIX_REDESIGN_2026-10-10.md): the user picks a
// CATEGORY (Eat, Shop, Ride, Stay) and discovers items across MANY businesses
// in that category, with the offering business shown beside every item.
//
// CONTRACT AUTHORITY (backend PR #349, merged on main):
//   `GET /api/discovery/items` — the ONE canonical discovery endpoint. The
//   exploratory `/api/marketplace/mix/offers` sketch from the earlier PR
//   description is DEAD: no such endpoint exists and none is invented here.
//
// DTO (§3.1) — parsed field for field in [MixOffer.fromDiscoveryDto]:
//   id · businessId · bizId · businessName · businessCategory
//   item{name, description, imageUrl, images, tags}
//   pricing{amount, currency, displayCurrency, hasUsdcListPrice}
//   availability{isAvailable, sectionWindowOpen, preparationMins,
//                deliveryTerms, estimatedDelivery}
//   location{locationId, label, distanceKm} · section{id, name, taxonomy}
//   action · capabilities{orderable, bookable, deliverable, dineIn,
//   payableIn} · rank{score, label}
//
// HONEST PRICE RULES (pinned in tests):
//   • `pricing.amount` is an EXACT two-decimal STRING straight from the
//     server's verified effective `BusinessPrice` GHS row. It is kept as a
//     STRING end-to-end — never parsed into a double — and rendered only via
//     `AzMoney.ghsExact`.
//   • A fixed GHS price renders ONLY when the payload carries
//     `currency == 'GHS'` AND a valid `ddd.dd` amount shape. Anything else
//     (absent, malformed, non-GHS) is `MixOfferPrice.unknown` — rendered
//     "Price unavailable", NEVER `priceUsdc`, NEVER a converted/relabelled
//     USDC figure, NEVER zero. `hasUsdcListPrice` is informational only and
//     is never rendered as a price.
//   • A GHS LISTING price is display data. It is NOT a payment claim: the
//     payment rail is `capabilities.payableIn` (today `['USDC']` — GHS
//     checkout/settlement is not shipped, so the UI never claims GHS
//     payment). "Price on request" is NOT a state: the backend excludes
//     unpriced items entirely and the client never invents the state.
//   • Availability is NEVER inferred from a price or a missing field.
//
// TAXONOMY TRUTH (§4): `section.taxonomy` carries the server-owned canonical
// chip id (CatalogSectionTaxonomy). [MixTaxonomy.canonical] mirrors the
// backend's approved chip vocabulary (infra/install-marketplace-discovery-
// overlay.js TAXONOMY_ROWS) for the filter rail — the client NEVER infers a
// chip from a section NAME.
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

/// One canonical discovery taxonomy chip — a byte-exact mirror of the
/// backend's approved `TAXONOMY_ROWS` (backend PR #349 overlay). `id` is the
/// ONLY wire value (the repeatable `taxonomy` query parameter); `label` is
/// presentation. `UNMAPPED` is deliberately excluded: the backend documents
/// it as NOT requestable (its items stay in the unfiltered general feed).
class MixTaxonomy {
  final String id;
  final String label;
  final String? applicableCategory;

  const MixTaxonomy(this.id, this.label, {this.applicableCategory});

  /// The approved canonical vocabulary, wire-exact with the backend overlay.
  /// Do not add or rename entries without the backend contract changing
  /// first — an unknown chip is a 422 on the server.
  static const List<MixTaxonomy> canonical = [
    MixTaxonomy('MEALS', 'Main dishes', applicableCategory: 'FOOD_BEVERAGE'),
    MixTaxonomy('STARTERS', 'Starters', applicableCategory: 'FOOD_BEVERAGE'),
    MixTaxonomy('SIDES', 'Sides', applicableCategory: 'FOOD_BEVERAGE'),
    MixTaxonomy('DRINKS', 'Drinks', applicableCategory: 'FOOD_BEVERAGE'),
    MixTaxonomy('DESSERTS', 'Desserts', applicableCategory: 'FOOD_BEVERAGE'),
    MixTaxonomy('ROOMS', 'Rooms', applicableCategory: 'HOSPITALITY'),
    MixTaxonomy('RIDES', 'Rides', applicableCategory: 'LOGISTICS'),
    MixTaxonomy('RETAIL_ITEMS', 'Retail items', applicableCategory: 'RETAIL'),
    MixTaxonomy('SERVICES', 'Services'),
  ];

  /// Chips offered by the filter rail for one category (null applicability
  /// = available in every category).
  static List<MixTaxonomy> forCategory(String wire) => canonical
      .where((t) => t.applicableCategory == null || t.applicableCategory == wire)
      .toList(growable: false);

  static MixTaxonomy? byId(String? id) {
    if (id == null) return null;
    for (final t in canonical) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// The honest price states an offer can be in, from REAL payload data only.
///
/// `fixed` — the payload carried a verified GHS price: `currency == 'GHS'`
///   and `amount` is an exact two-decimal string. The amount stays a STRING
///   (`amountExact`); it is never floated and is rendered only through
///   `AzMoney.ghsExact`. `amountExact` is null in every other state.
/// `unknown` — no renderable price. Rendered "Price unavailable", never a
///   zero amount, never a USDC figure, never a "price on request" label.
enum MixPriceStatus { fixed, unknown }

class MixOfferPrice {
  final MixPriceStatus status;

  /// EXACT two-decimal GHS string ("25.00"), non-null ONLY in the fixed
  /// state. Money as text — see the file header; never parse this to a
  /// double for display.
  final String? amountExact;

  const MixOfferPrice._({required this.status, this.amountExact});

  const MixOfferPrice.unknown() : this._(status: MixPriceStatus.unknown);

  const MixOfferPrice.fixedGhs(this.amountExact) : status = MixPriceStatus.fixed;

  bool get isKnown => status == MixPriceStatus.fixed;

  /// Parses the DTO `pricing` object under the strict GHS invariants:
  /// a fixed price requires BOTH the expected GHS currency AND a valid
  /// exact-2dp amount shape. Everything else — absent, malformed, a non-GHS
  /// currency, a numeric amount, an empty string — is `unknown`.
  ///
  /// NEVER falls back to `priceUsdc`, never converts, never zeroes.
  static MixOfferPrice fromPricing(Map<String, dynamic>? pricing) {
    if (pricing == null) return const MixOfferPrice.unknown();
    // The CANONICAL currency must be GHS — displayCurrency is never a
    // substitute for it, so a USDC canonical currency stays unknown no
    // matter what displayCurrency claims.
    final currency = pricing['currency']?.toString();
    if (currency != 'GHS') return const MixOfferPrice.unknown();
    final displayCurrency = pricing['displayCurrency']?.toString();
    // When displayCurrency is present it must not contradict the canonical
    // currency. A contradiction (e.g. GHS vs USDC) fails closed: unknown.
    if (displayCurrency != null && displayCurrency != 'GHS') {
      return const MixOfferPrice.unknown();
    }
    final amount = pricing['amount'];
    // Exact decimal STRING only. A JSON number is a contract violation
    // (backend pesewasToGhsString emits strings) — never floated here.
    if (amount is! String) return const MixOfferPrice.unknown();
    final v = amount.trim();
    if (!RegExp(r'^\d+\.\d{2}$').hasMatch(v)) {
      return const MixOfferPrice.unknown();
    }
    // The approved contract requires a POSITIVE base GHS price — no
    // free-item model exists. Exact-string check (no double parsing): a
    // value whose every digit is zero ("0.00", "00.00", ...) is zero money
    // and fails closed to unknown.
    if (!v.replaceAll('.', '').contains(RegExp(r'[1-9]'))) {
      return const MixOfferPrice.unknown();
    }
    return MixOfferPrice.fixedGhs(v);
  }
}

/// Payment/fulfillment capabilities the SERVER computed (§5.3). The UI renders
/// only what this object says; a capability never claimed here is never
/// claimed by the card. `payableIn` is the actually-supported payment-rail
/// list (today `['USDC']`); a GHS listing price never implies GHS payment.
class MixOfferCapabilities {
  final bool orderable;
  final bool bookable;
  final bool deliverable;
  final bool dineIn;
  final List<String> payableIn;

  const MixOfferCapabilities({
    this.orderable = false,
    this.bookable = false,
    this.deliverable = false,
    this.dineIn = false,
    this.payableIn = const [],
  });

  static MixOfferCapabilities fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MixOfferCapabilities();
    List<String> rails(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return MixOfferCapabilities(
      orderable: json['orderable'] == true,
      bookable: json['bookable'] == true,
      deliverable: json['deliverable'] == true,
      dineIn: json['dineIn'] == true,
      payableIn: rails(json['payableIn']),
    );
  }
}

/// One item listing offered by ONE business — the atomic Mix unit.
///
/// Identity invariants (pinned in tests):
///   • [offerKey] is `<businessId>:<productId>` — the item+store pair.
///     Two rows with the same product name in different stores are DIFFERENT
///     offers and are never merged.
///   • [productId] (DTO `id`) is the ITEM identity; [businessId] (DTO
///     `businessId`, `BusinessProfile.id`) is the offering STORE identity —
///     kept distinct, never substituted for one another. [bizId] is the
///     navigation identifier the store route consumes; [businessId] is what
///     the interaction contract (`POST /api/storefront/:id/events`) takes.
class MixOffer {
  final String productId;
  final String businessId;
  final String bizId;
  final String businessName;
  final String businessCategory;
  final String name;
  final String? description;
  final List<String> imageUrls;
  final List<String> tags;
  final MixOfferPrice price;

  /// `availability.isAvailable` as stored truth. `null` = the payload did not
  /// carry the field — rendered with NO availability signal, never as
  /// "available" and never as "unavailable".
  final bool? isAvailable;

  /// `availability.sectionWindowOpen` — whether the item's section is inside
  /// its serving window right now (server-evaluated). `null` = absent.
  final bool? sectionWindowOpen;

  final int? preparationMins;
  final String? deliveryTerms;
  final String? estimatedDelivery;

  final String? locationLabel;

  /// `section.taxonomy` — the server-owned canonical chip id, or null when
  /// the item has no section (general feed) or the section is unmapped.
  final String? sectionTaxonomy;

  /// Server-computed action hint (ADD_TO_CART / BOOK / VIEW_SEATS /
  /// ENQUIRE). Display data only — the tap opens the offering store; no
  /// in-feed checkout is claimed.
  final String action;

  final MixOfferCapabilities capabilities;

  /// `rank.score` (0..1, pre-calibration) — informational. `rank.label` is
  /// null until P3 calibration, so the UI never renders a popularity label.
  final double? rankScore;

  const MixOffer({
    required this.productId,
    required this.businessId,
    required this.bizId,
    required this.businessName,
    required this.businessCategory,
    required this.name,
    required this.price,
    this.description,
    this.imageUrls = const [],
    this.tags = const [],
    this.isAvailable,
    this.sectionWindowOpen,
    this.preparationMins,
    this.deliveryTerms,
    this.estimatedDelivery,
    this.locationLabel,
    this.sectionTaxonomy,
    this.action = 'ENQUIRE',
    this.capabilities = const MixOfferCapabilities(),
    this.rankScore,
  });

  /// The item+store pair identity. Stable across rebuilds; used as the list
  /// key and the interaction identity.
  String get offerKey => '$businessId:$productId';

  String? get primaryImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  /// Parses one row of the canonical discovery DTO
  /// (`GET /api/discovery/items` → `items[...]`). Every field is mapped from
  /// the server contract; nothing is invented and nothing falls back to a
  /// different source (see the file header for the price rules).
  static MixOffer fromDiscoveryDto(Map<String, dynamic> json) {
    final item = json['item'] is Map<String, dynamic>
        ? json['item'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final availability = json['availability'] is Map<String, dynamic>
        ? json['availability'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final location = json['location'] is Map<String, dynamic>
        ? json['location'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final section = json['section'] is Map<String, dynamic>
        ? json['section'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final capabilities = json['capabilities'] is Map<String, dynamic>
        ? json['capabilities'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rank = json['rank'] is Map<String, dynamic>
        ? json['rank'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final pricing = json['pricing'] is Map<String, dynamic>
        ? json['pricing'] as Map<String, dynamic>
        : null;
    final prepMins = availability['preparationMins'];
    final score = rank['score'];

    return MixOffer(
      productId: (json['id'] ?? '').toString(),
      businessId: (json['businessId'] ?? '').toString(),
      bizId: (json['bizId'] ?? '').toString(),
      businessName: (json['businessName'] ?? '').toString(),
      businessCategory: (json['businessCategory'] ?? '').toString(),
      name: (item['name'] ?? '').toString(),
      description: item['description']?.toString(),
      imageUrls: _toStringList(item['images']),
      tags: _toStringList(item['tags']),
      price: MixOfferPrice.fromPricing(pricing),
      isAvailable:
          availability['isAvailable'] == null ? null : availability['isAvailable'] == true,
      sectionWindowOpen: availability['sectionWindowOpen'] == null
          ? null
          : availability['sectionWindowOpen'] == true,
      preparationMins: prepMins is num ? prepMins.toInt() : null,
      deliveryTerms: availability['deliveryTerms']?.toString(),
      estimatedDelivery: availability['estimatedDelivery']?.toString(),
      locationLabel: location['label']?.toString(),
      sectionTaxonomy: section['taxonomy']?.toString(),
      action: (json['action'] ?? 'ENQUIRE').toString(),
      capabilities: MixOfferCapabilities.fromJson(capabilities),
      rankScore: score is num ? score.toDouble() : null,
    );
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
