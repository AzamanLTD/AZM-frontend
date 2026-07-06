// =============================================================================
// BUSINESS MODELS — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Every model for the Premium Marketplace lives in this one file (both the
// customer-facing browse/order flow and the owner-facing dashboard use it).
// Mirrors the Prisma tables: BusinessProfile, BusinessProduct,
// BusinessLocation, BusinessTable, BusinessInvoice (+ line/tax lines),
// BusinessReview, BusinessOrder, BusinessNotification.
//
// Parsing notes (the backend is the source of truth, NOT the spec sketch):
//   • Decimals arrive as numbers OR strings → `_toDouble`.
//   • The related User is nested under json["user"] → { id, username,
//     profilePictureUrl }.
//   • Invoice line items use `unitPrice` / `lineTotal` (no Usdc suffix);
//     tax lines use `name` / `computedAmount` and type PERCENTAGE|FLAT.
//   • Image / gallery URL arrays are JSON arrays of Cloudinary strings.
// =============================================================================

import 'package:flutter/material.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Shared parse helpers
// ─────────────────────────────────────────────────────────────────────────────

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _toInt(dynamic v) {
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

DateTime _toDateOr0(dynamic v) =>
    _toDate(v) ?? DateTime.fromMillisecondsSinceEpoch(0);

List<String> _toStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

// ─────────────────────────────────────────────────────────────────────────────
// Category catalogue — single source of truth for wire value ↔ label ↔ icon.
// Used by the marketplace home carousel, the registration form dropdown and
// any chip that displays a category. `all` is a UI-only pseudo-category (no
// wire value) used to clear the filter.
// ─────────────────────────────────────────────────────────────────────────────

class BusinessCategory {
  /// Backend enum value (e.g. "RETAIL"). Empty for the "All" pseudo-category.
  final String wire;

  /// Human label shown in the UI.
  final String label;

  /// Outline icon used in the category carousel.
  final IconData icon;

  /// Brand color for this category (used in cards, badges, hero sections).
  final Color color;

  /// Whether this is a primary marketplace category (gets a hero card).
  final bool isPrimary;

  /// Optional subtitle for hero cards.
  final String? subtitle;

  const BusinessCategory({
    required this.wire,
    required this.label,
    required this.icon,
    this.color = const Color(0xFF7B7B9A),
    this.isPrimary = false,
    this.subtitle,
  });
}

class BusinessCategories {
  BusinessCategories._();

  /// UI-only "clear filter" entry — has no wire value.
  static const all = BusinessCategory(
    wire: '',
    label: 'All',
    icon: Icons.grid_view_outlined,
  );

  /// The 11 real backend categories — reorganized with proper icons,
  /// colors, and primary/secondary priority. Wire values are unchanged
  /// so no backend migration is needed.
  static const List<BusinessCategory> values = [
    // ── PRIMARY: Transit, Restaurants, Hotels ──────────────────────────
    BusinessCategory(
        wire: 'LOGISTICS',
        label: 'Transit & Transport',
        icon: Icons.directions_bus,
        color: Color(0xFF4F8EF7),
        isPrimary: true,
        subtitle: 'Book seats on scheduled trips'),
    BusinessCategory(
        wire: 'FOOD_BEVERAGE',
        label: 'Restaurants',
        icon: Icons.restaurant_outlined,
        color: Color(0xFFF59E0B),
        isPrimary: true,
        subtitle: 'Reserve tables & order meals'),
    BusinessCategory(
        wire: 'REAL_ESTATE',
        label: 'Hotels & Stays',
        icon: Icons.hotel_outlined,
        color: Color(0xFFA78BFA),
        isPrimary: true,
        subtitle: 'Book rooms & check availability'),
    // ── SECONDARY ───────────────────────────────────────────────────────
    BusinessCategory(
        wire: 'RETAIL',
        label: 'Retail',
        icon: Icons.shopping_bag_outlined,
        color: Color(0xFF00D97E)),
    BusinessCategory(
        wire: 'HEALTH_WELLNESS',
        label: 'Health & Wellness',
        icon: Icons.local_hospital_outlined,
        color: Color(0xFF00B8D9)),
    BusinessCategory(
        wire: 'EDUCATION',
        label: 'Education',
        icon: Icons.school_outlined,
        color: Color(0xFFF43F5E)),
    BusinessCategory(
        wire: 'ENTERTAINMENT',
        label: 'Entertainment',
        icon: Icons.music_note_outlined,
        color: Color(0xFFEC4899)),
    BusinessCategory(
        wire: 'FREELANCE_SERVICES',
        label: 'Services',
        icon: Icons.work_outline,
        color: Color(0xFF8B5CF6)),
    BusinessCategory(
        wire: 'TECHNOLOGY',
        label: 'Technology',
        icon: Icons.memory_outlined,
        color: Color(0xFF06B6D4)),
    BusinessCategory(
        wire: 'FINANCIAL_SERVICES',
        label: 'Financial',
        icon: Icons.account_balance_outlined,
        color: Color(0xFFEAB308)),
    BusinessCategory(
        wire: 'HOSPITALITY',
        label: 'Hospitality',
        icon: Icons.holiday_village_outlined,
        color: Color(0xFFD946EF),
        subtitle: 'Hotels, guesthouses & lodging'),
    BusinessCategory(
        wire: 'OTHER',
        label: 'Other',
        icon: Icons.category_outlined,
        color: Color(0xFF7B7B9A)),
  ];

  /// Only the primary categories (for hero section on marketplace home).
  static List<BusinessCategory> get primary =>
      values.where((c) => c.isPrimary).toList();

  /// Only the secondary categories (for compact grid).
  static List<BusinessCategory> get secondary =>
      values.where((c) => !c.isPrimary).toList();

  /// "All" carousel order (filter chip bar / category carousel).
  static const List<BusinessCategory> withAll = [all, ...values];

  /// Resolve a wire value to its catalogue entry (falls back to "Other").
  static BusinessCategory fromWire(String? wire) {
    if (wire == null || wire.isEmpty) return all;
    return values.firstWhere(
      (c) => c.wire == wire,
      orElse: () => values.last, // OTHER
    );
  }

  /// Friendly label for any wire value (e.g. on a business card).
  static String labelFor(String? wire) => fromWire(wire).label;
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessSubcategory — pre-seeded lookup for the category drill-down UI.
// Mirrors the backend BusinessSubcategory table.
// ─────────────────────────────────────────────────────────────────────────────

class BusinessSubcategory {
  final String id;
  final String parentWire; // maps to BusinessCategory.wire
  final String wire; // e.g. "RESTAURANT_FINE_DINING"
  final String label; // "Fine Dining"
  final String? imageUrl; // Cloudinary lifestyle photo
  final int displayOrder;
  final bool isActive;

  const BusinessSubcategory({
    required this.id,
    required this.parentWire,
    required this.wire,
    required this.label,
    this.imageUrl,
    required this.displayOrder,
    required this.isActive,
  });

  factory BusinessSubcategory.fromJson(Map<String, dynamic> json) {
    return BusinessSubcategory(
      id: json['id'] as String? ?? '',
      parentWire: json['parentWire'] as String? ?? '',
      wire: json['wire'] as String? ?? '',
      label: json['label'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      displayOrder: _toInt(json['displayOrder']),
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CatalogSection — menu section (Starters / Mains / Drinks / Rooms etc.)
// Each section contains an ordered list of BusinessProducts.
// ─────────────────────────────────────────────────────────────────────────────

class CatalogSection {
  final String id;
  final String businessProfileId;
  final String? locationId;
  final String name;
  final String? description;
  final int displayOrder;
  final String? availableFrom; // "06:00"
  final String? availableTo; // "11:00"
  final String? imageUrl;
  final bool isActive;
  final List<BusinessProduct> products;

  const CatalogSection({
    required this.id,
    required this.businessProfileId,
    this.locationId,
    required this.name,
    this.description,
    required this.displayOrder,
    this.availableFrom,
    this.availableTo,
    this.imageUrl,
    required this.isActive,
    this.products = const [],
  });

  factory CatalogSection.fromJson(Map<String, dynamic> json) {
    return CatalogSection(
      id: json['id'] as String? ?? '',
      businessProfileId: json['businessProfileId'] as String? ?? '',
      locationId: json['locationId'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      displayOrder: _toInt(json['displayOrder']),
      availableFrom: json['availableFrom'] as String?,
      availableTo: json['availableTo'] as String?,
      imageUrl: json['imageUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      products: (json['products'] as List<dynamic>? ?? [])
          .map((e) => BusinessProduct.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reservation — customer-held time-based booking.
// ─────────────────────────────────────────────────────────────────────────────

enum ReservationStatus {
  pending,
  confirmed,
  checkedIn,
  checkedOut,
  completed,
  cancelledCustomer,
  cancelledBusiness,
  noShow,
}

class Reservation {
  final String id;
  final String reservationRef;
  final String businessProfileId;
  final String? locationId;
  final int customerId;
  final String? serviceItemId;
  final ReservationStatus status;
  final DateTime startDatetime;
  final DateTime endDatetime;
  final int partySize;
  final double amountUsdc;
  final double depositUsdc;
  final String? cancellationPolicy;
  final String? customerNotes;
  final String? businessNotes;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;
  final String? escrowId;
  final Map<String, dynamic>? metadata;
  // Nested (from API include)
  final String? businessName;
  final String? businessLogoUrl;
  final String? businessBizId;

  const Reservation({
    required this.id,
    required this.reservationRef,
    required this.businessProfileId,
    this.locationId,
    required this.customerId,
    this.serviceItemId,
    required this.status,
    required this.startDatetime,
    required this.endDatetime,
    required this.partySize,
    required this.amountUsdc,
    required this.depositUsdc,
    this.cancellationPolicy,
    this.customerNotes,
    this.businessNotes,
    this.confirmedAt,
    this.cancelledAt,
    this.checkedInAt,
    this.checkedOutAt,
    this.escrowId,
    this.metadata,
    this.businessName,
    this.businessLogoUrl,
    this.businessBizId,
  });

  static ReservationStatus _parseStatus(String? s) {
    switch (s) {
      case 'CONFIRMED':
        return ReservationStatus.confirmed;
      case 'CHECKED_IN':
        return ReservationStatus.checkedIn;
      case 'CHECKED_OUT':
        return ReservationStatus.checkedOut;
      case 'COMPLETED':
        return ReservationStatus.completed;
      case 'CANCELLED_CUSTOMER':
        return ReservationStatus.cancelledCustomer;
      case 'CANCELLED_BUSINESS':
        return ReservationStatus.cancelledBusiness;
      case 'NO_SHOW':
        return ReservationStatus.noShow;
      default:
        return ReservationStatus.pending;
    }
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final biz = json['businessProfile'] as Map<String, dynamic>?;
    return Reservation(
      id: json['id'] as String? ?? '',
      reservationRef: json['reservationRef'] as String? ?? '',
      businessProfileId: json['businessProfileId'] as String? ?? '',
      locationId: json['locationId'] as String?,
      customerId: _toInt(json['customerId']),
      serviceItemId: json['serviceItemId'] as String?,
      status: _parseStatus(json['status'] as String?),
      startDatetime: _toDateOr0(json['startDatetime']),
      endDatetime: _toDateOr0(json['endDatetime']),
      partySize: _toInt(json['partySize']).let((v) => v == 0 ? 1 : v),
      amountUsdc: _toDouble(json['amountUsdc']),
      depositUsdc: _toDouble(json['depositUsdc']),
      cancellationPolicy: json['cancellationPolicy'] as String?,
      customerNotes: json['customerNotes'] as String?,
      businessNotes: json['businessNotes'] as String?,
      confirmedAt: _toDate(json['confirmedAt']),
      cancelledAt: _toDate(json['cancelledAt']),
      checkedInAt: _toDate(json['checkedInAt']),
      checkedOutAt: _toDate(json['checkedOutAt']),
      escrowId: json['escrowId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      businessName: biz?['businessName'] as String?,
      businessLogoUrl: biz?['logoUrl'] as String?,
      businessBizId: biz?['bizId'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PriceRange — renders 1=₵  2=₵₵  3=₵₵₵  4=₵₵₵₵
// ─────────────────────────────────────────────────────────────────────────────
class PriceRange {
  PriceRange._();
  static String label(int? range) {
    switch (range) {
      case 1:
        return '₵';
      case 2:
        return '₵₵';
      case 3:
        return '₵₵₵';
      case 4:
        return '₵₵₵₵';
      default:
        return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessProfile
// ─────────────────────────────────────────────────────────────────────────────

class BusinessProfile {
  final String id;
  final String bizId; // "BIZ-XXXXXXXXX"
  final String businessName;
  final String category;
  final String? description;
  final String? website;
  final String? logoUrl;
  final String? contactEmail;
  final String? phoneNumber;
  final String? address;
  final String? country;
  final bool isVerified;
  final bool isSuspended;
  final String kybStatus; // UNVERIFIED | PENDING | VERIFIED | REJECTED
  final int totalEscrows;
  final int completedEscrows;
  final int userId;
  final double totalVolume;
  final double averageRating;
  // Marketplace hierarchy additions (2026-06-24)
  final String? subcategory;
  final int? priceRange;
  final List<String> amenities;
  final List<String> cuisineTypes;
  final Map<String, dynamic>? businessMeta;
  // Ad appearance customization (2026-07-06): set from the business portal.
  // Hex string like "#FFAA00"; null falls back to the category-default tint
  // used in collapsible_business_bar.dart.
  final String? adAccentColor;

  List<String> get showcaseUrls {
    if (businessMeta == null || !businessMeta!.containsKey('showcaseUrls')) return [];
    return List<String>.from(businessMeta!['showcaseUrls']);
  }

  PenaltyPolicyModel? get penaltyPolicy {
    if (businessMeta == null || !businessMeta!.containsKey('penaltyPolicy')) return null;
    return PenaltyPolicyModel.fromJson(businessMeta!['penaltyPolicy']);
  }

  /// Parsed adAccentColor, or null if unset/malformed (caller falls back to
  /// the category-default tint in that case).
  Color? get adAccentColorValue {
    final hex = adAccentColor;
    if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
  final String username;
  final String? userProfilePictureUrl;
  // Marketplace Premium Upgrade (2026-06-21): the public getBusinessByBizId /
  // search payloads may embed the business's products + locations. Used by the
  // premium BusinessCard for the cover photo, "from X USDC" anchor and the
  // "Open Now" badge. Default to empty when the payload omits them.
  final List<BusinessProduct> products;
  final List<BusinessLocation> locations;

  const BusinessProfile({
    required this.id,
    required this.bizId,
    required this.businessName,
    required this.category,
    required this.isVerified,
    required this.isSuspended,
    required this.kybStatus,
    required this.totalEscrows,
    required this.completedEscrows,
    required this.userId,
    required this.totalVolume,
    required this.averageRating,
    this.subcategory,
    this.priceRange,
    this.amenities = const [],
    this.cuisineTypes = const [],
    this.businessMeta,
    this.adAccentColor,
    required this.username,
    this.description,
    this.website,
    this.logoUrl,
    this.contactEmail,
    this.phoneNumber,
    this.address,
    this.country,
    this.userProfilePictureUrl,
    this.products = const [],
    this.locations = const [],
  });

  String get categoryLabel => BusinessCategories.labelFor(category);
  bool get isKybVerified => kybStatus.toUpperCase() == 'VERIFIED';

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final products = (json['products'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BusinessProduct.fromJson)
        .toList();
    final locations = (json['locations'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BusinessLocation.fromJson)
        .toList();
    return BusinessProfile(
      id: json['id'].toString(),
      bizId: (json['bizId'] ?? '').toString(),
      businessName: (json['businessName'] ?? '').toString(),
      category: (json['category'] ?? 'OTHER').toString(),
      description: json['description']?.toString(),
      website: json['website']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      contactEmail: json['contactEmail']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      address: json['address']?.toString(),
      country: json['country']?.toString(),
      isVerified: json['isVerified'] == true,
      isSuspended: json['isSuspended'] == true,
      kybStatus: (json['kybStatus'] ?? 'UNVERIFIED').toString(),
      totalEscrows: _toInt(json['totalEscrows']),
      completedEscrows: _toInt(json['completedEscrows']),
      userId: _toInt(user['id']),
      totalVolume: _toDouble(json['totalVolume']),
      averageRating: _toDouble(json['averageRating']),
      subcategory: json['subcategory'] as String?,
      priceRange: _toInt(json['priceRange']).let((v) => v == 0 ? null : v),
      amenities: _toStringList(json['amenities']),
      cuisineTypes: _toStringList(json['cuisineTypes']),
      businessMeta: json['businessMeta'] as Map<String, dynamic>?,
      adAccentColor: json['adAccentColor'] as String?,
      username: (user['username'] ?? '').toString(),
      userProfilePictureUrl: user['profilePictureUrl']?.toString(),
      products: products,
      locations: locations,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessProduct
// ─────────────────────────────────────────────────────────────────────────────

class BusinessProduct {
  final String id;
  final String businessProfileId;
  final String name;
  final String slug;
  final String? description;
  final String? category;
  final String? locationId;
  final String? deliveryTerms;
  final String? estimatedDelivery;
  final double priceUsdc;
  final double totalRevenue;
  final List<String> imageUrls;
  final bool isActive;
  final int totalOrders;
  final List<String> tags;

  const BusinessProduct({
    required this.id,
    required this.businessProfileId,
    required this.name,
    required this.slug,
    required this.priceUsdc,
    required this.totalRevenue,
    required this.imageUrls,
    required this.isActive,
    required this.totalOrders,
    this.tags = const [],
    this.description,
    this.category,
    this.locationId,
    this.deliveryTerms,
    this.estimatedDelivery,
  });

  String? get primaryImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  factory BusinessProduct.fromJson(Map<String, dynamic> json) {
    return BusinessProduct(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      locationId: json['locationId']?.toString(),
      deliveryTerms: json['deliveryTerms']?.toString(),
      estimatedDelivery: json['estimatedDelivery']?.toString(),
      priceUsdc: _toDouble(json['priceUsdc']),
      totalRevenue: _toDouble(json['totalRevenue']),
      imageUrls: _toStringList(json['imageUrls']),
      isActive: json['isActive'] != false,
      totalOrders: _toInt(json['totalOrders']),
      tags: _toStringList(json['tags']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessLocation
// ─────────────────────────────────────────────────────────────────────────────

class BusinessLocation {
  final String id;
  final String businessProfileId;
  final String label;
  final String address;
  final String? city;
  final String? region;
  final String? country;
  final String? phoneNumber;
  final double latitude;
  final double longitude;
  final Map<String, dynamic>? operatingHours; // {mon: "8:00-22:00", ...}
  final List<String> galleryUrls;
  final bool isPrimary;
  final bool isActive;
  final double? distanceKm; // only present in searchNearby results

  const BusinessLocation({
    required this.id,
    required this.businessProfileId,
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.galleryUrls,
    required this.isPrimary,
    required this.isActive,
    this.city,
    this.region,
    this.country,
    this.phoneNumber,
    this.operatingHours,
    this.distanceKm,
  });

  factory BusinessLocation.fromJson(Map<String, dynamic> json) {
    return BusinessLocation(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      city: json['city']?.toString(),
      region: json['region']?.toString(),
      country: json['country']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      operatingHours: json['operatingHours'] is Map<String, dynamic>
          ? json['operatingHours'] as Map<String, dynamic>
          : null,
      galleryUrls: _toStringList(json['galleryUrls']),
      isPrimary: json['isPrimary'] == true,
      isActive: json['isActive'] != false,
      distanceKm: _toDoubleOrNull(json['distanceKm']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessTable
// ─────────────────────────────────────────────────────────────────────────────

class BusinessTable {
  final String id;
  final String locationId;
  final String label;
  final bool isActive;

  const BusinessTable({
    required this.id,
    required this.locationId,
    required this.label,
    required this.isActive,
  });

  factory BusinessTable.fromJson(Map<String, dynamic> json) {
    return BusinessTable(
      id: json['id'].toString(),
      locationId: (json['locationId'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      isActive: json['isActive'] != false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoices
// ─────────────────────────────────────────────────────────────────────────────

class InvoiceLineItem {
  final String id;
  final String description;
  final int quantity;
  final double unitPriceUsdc;
  final double lineTotalUsdc;

  const InvoiceLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPriceUsdc,
    required this.lineTotalUsdc,
  });

  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) {
    return InvoiceLineItem(
      id: json['id'].toString(),
      description: (json['description'] ?? '').toString(),
      quantity: _toInt(json['quantity']),
      // Backend column is `unitPrice` / `lineTotal` (Decimal, no Usdc suffix).
      unitPriceUsdc: _toDouble(json['unitPrice'] ?? json['unitPriceUsdc']),
      lineTotalUsdc: _toDouble(json['lineTotal'] ?? json['lineTotalUsdc']),
    );
  }
}

class InvoiceTaxLine {
  final String id;
  final String label;
  final String type; // PERCENTAGE | FLAT
  final double value;
  final double amountUsdc;

  const InvoiceTaxLine({
    required this.id,
    required this.label,
    required this.type,
    required this.value,
    required this.amountUsdc,
  });

  bool get isPercentage => type.toUpperCase() == 'PERCENTAGE';

  factory InvoiceTaxLine.fromJson(Map<String, dynamic> json) {
    return InvoiceTaxLine(
      id: json['id'].toString(),
      // Backend column is `name`; `computedAmount` for the resolved value.
      label: (json['name'] ?? json['label'] ?? '').toString(),
      type: (json['type'] ?? 'PERCENTAGE').toString(),
      value: _toDouble(json['value']),
      amountUsdc: _toDouble(json['computedAmount'] ?? json['amountUsdc']),
    );
  }
}

enum InvoiceStatus {
  draft,
  sent,
  paid,
  voided;

  static InvoiceStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'SENT':
        return InvoiceStatus.sent;
      case 'PAID':
        return InvoiceStatus.paid;
      case 'VOIDED':
        return InvoiceStatus.voided;
      case 'DRAFT':
      default:
        return InvoiceStatus.draft;
    }
  }

  String get label {
    switch (this) {
      case InvoiceStatus.draft:
        return 'Draft';
      case InvoiceStatus.sent:
        return 'Unpaid';
      case InvoiceStatus.paid:
        return 'Paid';
      case InvoiceStatus.voided:
        return 'Voided';
    }
  }
}

class BusinessInvoice {
  final String id;
  final String businessProfileId;
  final String invoiceRef;
  final String? locationId;
  final String? tableId;
  final int customerId;
  final InvoiceStatus status;
  final double subtotalUsdc;
  final double taxTotalUsdc;
  final double tipUsdc;
  final double billTotalUsdc;
  final double feeUsdc;
  final bool customerCoveredFee;
  final double? customerPaidUsdc;
  final String? customerNote;
  final String? businessNote;
  final DateTime? sentAt;
  final DateTime? paidAt;
  final DateTime? voidedAt;
  final DateTime createdAt;
  final List<InvoiceLineItem> lineItems;
  final List<InvoiceTaxLine> taxLines;
  // Nested includes
  final String? businessName;
  final String? businessBizId;
  final String? businessLogoUrl;
  final String? locationLabel;
  final String? locationAddress;
  final String? tableLabel;

  const BusinessInvoice({
    required this.id,
    required this.businessProfileId,
    required this.invoiceRef,
    required this.customerId,
    required this.status,
    required this.subtotalUsdc,
    required this.taxTotalUsdc,
    required this.tipUsdc,
    required this.billTotalUsdc,
    required this.feeUsdc,
    required this.customerCoveredFee,
    required this.createdAt,
    required this.lineItems,
    required this.taxLines,
    this.locationId,
    this.tableId,
    this.customerPaidUsdc,
    this.customerNote,
    this.businessNote,
    this.sentAt,
    this.paidAt,
    this.voidedAt,
    this.businessName,
    this.businessBizId,
    this.businessLogoUrl,
    this.locationLabel,
    this.locationAddress,
    this.tableLabel,
  });

  factory BusinessInvoice.fromJson(Map<String, dynamic> json) {
    final biz = json['businessProfile'] is Map<String, dynamic>
        ? json['businessProfile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final loc = json['location'] is Map<String, dynamic>
        ? json['location'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final table = json['table'] is Map<String, dynamic>
        ? json['table'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final lines = (json['lineItems'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceLineItem.fromJson)
        .toList();
    final taxes = (json['taxLines'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceTaxLine.fromJson)
        .toList();
    return BusinessInvoice(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      invoiceRef: (json['invoiceRef'] ?? '').toString(),
      locationId: json['locationId']?.toString(),
      tableId: json['tableId']?.toString(),
      customerId: _toInt(json['customerId']),
      status: InvoiceStatus.fromString(json['status']),
      subtotalUsdc: _toDouble(json['subtotalUsdc']),
      taxTotalUsdc: _toDouble(json['taxTotalUsdc']),
      tipUsdc: _toDouble(json['tipUsdc']),
      billTotalUsdc: _toDouble(json['billTotalUsdc']),
      feeUsdc: _toDouble(json['feeUsdc']),
      customerCoveredFee: json['customerCoveredFee'] == true,
      customerPaidUsdc: _toDoubleOrNull(json['customerPaidUsdc']),
      customerNote: json['customerNote']?.toString(),
      businessNote: json['businessNote']?.toString(),
      sentAt: _toDate(json['sentAt']),
      paidAt: _toDate(json['paidAt']),
      voidedAt: _toDate(json['voidedAt']),
      createdAt: _toDateOr0(json['createdAt']),
      lineItems: lines,
      taxLines: taxes,
      businessName: biz['businessName']?.toString(),
      businessBizId: biz['bizId']?.toString(),
      businessLogoUrl: biz['logoUrl']?.toString(),
      locationLabel: loc['label']?.toString(),
      locationAddress: loc['address']?.toString(),
      tableLabel: table['label']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BusinessReview
// ─────────────────────────────────────────────────────────────────────────────

class BusinessReview {
  final String id;
  final String businessProfileId;
  final String? locationId;
  final int reviewerId;
  final int rating; // 1-5
  final String? comment;
  final String sourceType; // ORDER | INVOICE
  final String? orderId;
  final String? invoiceId;
  final DateTime createdAt;
  final String reviewerUsername;
  final String? reviewerProfilePictureUrl;
  final String? locationLabel;

  const BusinessReview({
    required this.id,
    required this.businessProfileId,
    required this.reviewerId,
    required this.rating,
    required this.sourceType,
    required this.createdAt,
    required this.reviewerUsername,
    this.locationId,
    this.comment,
    this.orderId,
    this.invoiceId,
    this.reviewerProfilePictureUrl,
    this.locationLabel,
  });

  factory BusinessReview.fromJson(Map<String, dynamic> json) {
    final reviewer = json['reviewer'] is Map<String, dynamic>
        ? json['reviewer'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final loc = json['location'] is Map<String, dynamic>
        ? json['location'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return BusinessReview(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      locationId: json['locationId']?.toString(),
      reviewerId: _toInt(json['reviewerId']),
      rating: _toInt(json['rating']),
      comment: json['comment']?.toString(),
      sourceType: (json['sourceType'] ?? 'ORDER').toString(),
      orderId: json['orderId']?.toString(),
      invoiceId: json['invoiceId']?.toString(),
      createdAt: _toDateOr0(json['createdAt']),
      reviewerUsername: (reviewer['username'] ?? 'User').toString(),
      reviewerProfilePictureUrl: reviewer['profilePictureUrl']?.toString(),
      locationLabel: loc['label']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications
// ─────────────────────────────────────────────────────────────────────────────

class BizNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? metadata;
  final bool isRead;
  final DateTime createdAt;

  const BizNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory BizNotification.fromJson(Map<String, dynamic> json) {
    return BizNotification(
      id: json['id'].toString(),
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null,
      isRead: json['isRead'] == true,
      createdAt: _toDateOr0(json['createdAt']),
    );
  }
}

class BizNotificationFeed {
  final List<BizNotification> notifications;
  final bool hasMore;
  final String? nextCursor;
  final int unreadCount;

  const BizNotificationFeed({
    required this.notifications,
    required this.hasMore,
    required this.unreadCount,
    this.nextCursor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Orders + Stats
// ─────────────────────────────────────────────────────────────────────────────

enum BusinessOrderStatus {
  awaitingPayment,
  paid,
  delivered,
  completed,
  disputed,
  refunded,
  cancelled;

  static BusinessOrderStatus fromString(dynamic raw) {
    final s = raw?.toString().toUpperCase().trim() ?? '';
    switch (s) {
      case 'PAID':
        return BusinessOrderStatus.paid;
      case 'DELIVERED':
        return BusinessOrderStatus.delivered;
      case 'COMPLETED':
        return BusinessOrderStatus.completed;
      case 'DISPUTED':
        return BusinessOrderStatus.disputed;
      case 'REFUNDED':
        return BusinessOrderStatus.refunded;
      case 'CANCELLED':
        return BusinessOrderStatus.cancelled;
      case 'AWAITING_PAYMENT':
      default:
        return BusinessOrderStatus.awaitingPayment;
    }
  }

  String get label {
    switch (this) {
      case BusinessOrderStatus.awaitingPayment:
        return 'Awaiting Payment';
      case BusinessOrderStatus.paid:
        return 'Paid';
      case BusinessOrderStatus.delivered:
        return 'Delivered';
      case BusinessOrderStatus.completed:
        return 'Completed';
      case BusinessOrderStatus.disputed:
        return 'Disputed';
      case BusinessOrderStatus.refunded:
        return 'Refunded';
      case BusinessOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// Active = customer has an open obligation / live order.
  bool get isActive =>
      this == BusinessOrderStatus.awaitingPayment ||
      this == BusinessOrderStatus.paid ||
      this == BusinessOrderStatus.delivered ||
      this == BusinessOrderStatus.disputed;

  bool get isDone =>
      this == BusinessOrderStatus.completed ||
      this == BusinessOrderStatus.refunded ||
      this == BusinessOrderStatus.cancelled;
}

class BusinessOrder {
  final String id;
  final String businessProfileId;
  final String orderRef;
  final String title;
  final int customerId;
  final String? productId;
  final String? escrowId;
  final String? ticketId;
  final BusinessOrderStatus status;
  final double amountUsdc;
  final String? description;
  final String? customerNotes;
  final String? deliveryNotes;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  const BusinessOrder({
    required this.id,
    required this.businessProfileId,
    required this.orderRef,
    required this.title,
    required this.customerId,
    required this.status,
    required this.amountUsdc,
    required this.createdAt,
    this.productId,
    this.escrowId,
    this.ticketId,
    this.description,
    this.customerNotes,
    this.deliveryNotes,
    this.deliveredAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory BusinessOrder.fromJson(Map<String, dynamic> json) {
    return BusinessOrder(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      orderRef: (json['orderRef'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      customerId: _toInt(json['customerId']),
      productId: json['productId']?.toString(),
      escrowId: json['escrowId']?.toString(),
      ticketId: json['ticketId']?.toString(),
      status: BusinessOrderStatus.fromString(json['status']),
      amountUsdc: _toDouble(json['amountUsdc']),
      description: json['description']?.toString(),
      customerNotes: json['customerNotes']?.toString(),
      deliveryNotes: json['deliveryNotes']?.toString(),
      deliveredAt: _toDate(json['deliveredAt']),
      completedAt: _toDate(json['completedAt']),
      cancelledAt: _toDate(json['cancelledAt']),
      createdAt: _toDateOr0(json['createdAt']),
    );
  }
}

class BusinessStats {
  final int totalOrders;
  final int completedOrders;
  final int pendingOrders;
  final int disputedOrders;
  final int cancelledOrders;
  final double totalRevenue;
  final double avgOrderValue;
  final List<BusinessOrder> recentOrders;

  const BusinessStats({
    required this.totalOrders,
    required this.completedOrders,
    required this.pendingOrders,
    required this.disputedOrders,
    required this.cancelledOrders,
    required this.totalRevenue,
    required this.avgOrderValue,
    required this.recentOrders,
  });

  factory BusinessStats.fromJson(Map<String, dynamic> json) {
    final recent = (json['recentOrders'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BusinessOrder.fromJson)
        .toList();
    return BusinessStats(
      totalOrders: _toInt(json['totalOrders']),
      completedOrders: _toInt(json['completedOrders']),
      pendingOrders: _toInt(json['pendingOrders']),
      disputedOrders: _toInt(json['disputedOrders']),
      cancelledOrders: _toInt(json['cancelledOrders']),
      totalRevenue: _toDouble(json['totalRevenue']),
      avgOrderValue: _toDouble(json['avgOrderValue']),
      recentOrders: recent,
    );
  }
}


class DineInTabModel {
  final String id;
  final String businessName;
  final String status; // OPEN, CONFIRMED, CLOSED
  final List<DineInTabItemModel> items;
  final double totalUsdc;

  DineInTabModel({required this.id, required this.businessName, required this.status,
    required this.items, required this.totalUsdc});

  factory DineInTabModel.fromJson(Map<String, dynamic> j) => DineInTabModel(
    id: j['id'], businessName: j['businessName'] ?? '',
    status: j['status'] ?? 'OPEN',
    items: (j['items'] as List?)?.map((i) => DineInTabItemModel.fromJson(i)).toList() ?? [],
    totalUsdc: (j['totalUsdc'] as num?)?.toDouble() ?? 0.0,
  );
}

class DineInTabItemModel {
  final String name;
  final int quantity;
  final double unitPriceUsdc;
  final double totalUsdc;

  DineInTabItemModel({required this.name, required this.quantity,
    required this.unitPriceUsdc, required this.totalUsdc});

  factory DineInTabItemModel.fromJson(Map<String, dynamic> j) => DineInTabItemModel(
    name: j['name'] ?? '', quantity: j['quantity'] ?? 1,
    unitPriceUsdc: (j['unitPriceUsdc'] as num?)?.toDouble() ?? 0.0,
    totalUsdc: (j['totalUsdc'] as num?)?.toDouble() ?? 0.0,
  );
}

class PenaltyPolicyModel {
  final double penaltyPct;
  final int gracePeriodMins;
  final bool businessSideNoShowEnabled;

  PenaltyPolicyModel({required this.penaltyPct, required this.gracePeriodMins,
    required this.businessSideNoShowEnabled});

  factory PenaltyPolicyModel.fromJson(Map<String, dynamic> j) => PenaltyPolicyModel(
    penaltyPct: (j['penaltyPct'] as num?)?.toDouble() ?? 0.0,
    gracePeriodMins: j['gracePeriodMins'] ?? 30,
    businessSideNoShowEnabled: j['businessSideNoShowEnabled'] ?? false,
  );
}

class BusinessAdPostModel {
  final String id;
  final String template;
  final String? caption;
  final String? imageUrl;
  final DateTime createdAt;

  BusinessAdPostModel({required this.id, required this.template,
    required this.caption, required this.imageUrl, required this.createdAt});

  factory BusinessAdPostModel.fromJson(Map<String, dynamic> j) => BusinessAdPostModel(
    id: j['id'], template: j['template'] ?? 'PROMO',
    caption: j['caption'], imageUrl: j['imageUrl'],
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}
