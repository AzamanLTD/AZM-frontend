// =============================================================================
// AZAMAN — DEMO SEED DATA: MARKETPLACE
// Comprehensive mock data for marketplace verticals in demo mode.
//
// Milestone (2026-09-30): the seed now carries EIGHT businesses (two per
// canonical primary category) so the Marketplace portal feels populated,
// supports deterministic search/filter/pagination, and no longer leans on
// random placeholder generators (picsum.photos). Every media URL is a
// verified, checked-in Base44 media asset; category-native fallbacks are
// deterministic.
//
// Truthfulness contract: a seeded endpoint returns data that is coherent
// for the journey it feeds. An endpoint the marketplace journey expects
// but this file does NOT cover throws DemoEndpointNotSeededException from
// the interceptor — it can never masquerade as a successful empty dataset.
// =============================================================================

// The canonical Mix taxonomy vocabulary — the wire-exact chip contract
// shared with the real backend overlay. The discovery seed validates chips
// against it instead of inventing taxonomy IDs.
import 'package:azaman/marketplace/mix/mix_models.dart' show MixTaxonomy;
import 'dart:math' as math;

// Verified media assets (Base44 public CDN). Reused deterministically —
// one asset pool per category, no random generators.
const String _mp =
    'https://media.base44.com/images/public/6a4b8369bec68a34ddf0f3cf/';

class DemoMedia {
  DemoMedia._();

  // ── Restaurant pool ────────────────────────────────────────────────
  static const String rCover = '${_mp}c6cfdf741_generated_image.png';
  static const String rAlt = '${_mp}ff6392fb0_generated_image.png';
  static const String rThird = '${_mp}2c637584e_generated_image.png';
  static const String rLogo = '${_mp}eded2b264_generated_image.png';

  // ── Hotel pool ──────────────────────────────────────────────────────
  static const String hCover = '${_mp}5877f9e06_generated_image.png';
  static const String hAlt = '${_mp}75e3637bb_generated_image.png';
  static const String hThird = '${_mp}4c331502c_generated_image.png';
  static const String hLogo = '${_mp}456c5962a_generated_image.png';

  // ── Transit pool ────────────────────────────────────────────────────
  static const String tCover = '${_mp}38317d8aa_generated_image.png';
  static const String tAlt = '${_mp}e617a414b_generated_image.png';
  static const String tThird = '${_mp}05c20579a_generated_image.png';
  static const String tLogo = '${_mp}9eab4badd_generated_image.png';

  // ── Retail pool ─────────────────────────────────────────────────────
  static const String rtCover = '${_mp}595f7c251_generated_image.png';
  static const String rtAlt = '${_mp}16049fef1_generated_image.png';
  static const String rtThird = '${_mp}2dc7b658f_generated_image.png';
  static const String rtLogo = '${_mp}348cc5c1f_generated_image.png';

  /// Deterministic cover asset for a category wire. Used as the
  /// category-native fallback when a business has no media of its own.
  static String coverForCategory(String category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
        return rCover;
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return hCover;
      case 'LOGISTICS':
        return tCover;
      case 'RETAIL':
        return rtCover;
      default:
        return rCover;
    }
  }
}

/// Thrown when a Marketplace-family demo endpoint has no seeded coverage.
/// Surfaced through the provider error path so the UI shows the real
/// problem ("demo data is not seeded") instead of a fake "nothing exists".
class DemoEndpointNotSeededException implements Exception {
  final String method;
  final String endpoint;
  const DemoEndpointNotSeededException(this.method, this.endpoint);

  @override
  String toString() => 'Demo data is not seeded for $method $endpoint.';
}

class DemoMarketplaceSeed {
  DemoMarketplaceSeed._();

  static const restaurantBizId = 'BIZ-REST-001';
  static const restaurant2BizId = 'BIZ-REST-002';
  static const hotelBizId = 'BIZ-HOTEL-001';
  static const hotel2BizId = 'BIZ-HOTEL-002';
  static const transitBizId = 'BIZ-TRANS-001';
  static const transit2BizId = 'BIZ-TRANS-002';
  static const retailBizId = 'BIZ-RETAIL-001';
  static const retail2BizId = 'BIZ-RETAIL-002';

  static const String _demoAzamanId = 'AZM-000123456';

  /// Seeded Marketplace-family entity IDs. Every parameterized matcher must
  /// resolve a known ID to a valid synthetic response and throw
  /// [DemoEndpointNotSeededException] for anything else — no fake data for
  /// IDs the demo world never seeded.
  static const List<String> seededBusinessIds = <String>[
    restaurantBizId,
    restaurant2BizId,
    hotelBizId,
    hotel2BizId,
    transitBizId,
    transit2BizId,
    retailBizId,
    retail2BizId,
  ];
  static const List<String> seededTripIds = <String>[
    'trip-001',
    'trip-002',
    'trip-003',
    'trip-004',
  ];
  static const List<String> seededInvoiceIds = <String>[
    'inv-restaurant-001',
    'inv-restaurant-002',
  ];
  static const List<String> seededReservationRefs = <String>['AZM-RES-001'];
  static const List<String> seededDineInTabIds = <String>['tab-demo-001'];
  static const String seededTrustScoreAzamanId = _demoAzamanId;

  static bool isSeededId(String id, List<String> seeded) =>
      seeded.contains(id.trim().toUpperCase()) || seeded.contains(id);

  /// The canonical Marketplace GET endpoints the app's customer journey
  /// actually calls. Every entry must be explicitly covered by
  /// [DemoInterceptor] — a permanent test walks this list and fails if
  /// any of them is missing or throws.
  static const List<String> requiredGetEndpoints = <String>[
    '/business/search?q=jollof&category=FOOD_BEVERAGE&verified=true&limit=20',
    '/discovery/items?limit=24',
    '/business/search/nearby?lat=5.55&lng=-0.18&category=RETAIL',
    '/business/me',
    '/business/kyb/status',
    '/business/my-orders?limit=20',
    '/business/notifications?limit=20',
    '/business/notifications/unread-count',
    '/business/orders/stats',
    '/business/products?limit=20',
    '/business/products/prod-transit-001-eco',
    '/business/$restaurantBizId',
    '/business/$restaurantBizId/menu',
    '/business/$restaurantBizId/products',
    '/business/$restaurantBizId/locations',
    '/business/$restaurantBizId/reviews',
    '/business/invoices/inv-restaurant-001',
    '/follows/following?limit=50',
    '/follows/check/$restaurantBizId',
    '/marketplace/business/$restaurantBizId',
    '/marketplace/business/$restaurantBizId/stories',
    '/marketplace/business/dine-in/tab-demo-001',
    '/marketplace/reservations/AZM-RES-001/checkin-qr',
    '/marketplace/transit/trips?limit=20',
    '/marketplace/transit/trips/trip-001/seats',
    '/marketplace/trust-score/$_demoAzamanId',
    '/showcases/$restaurantBizId',
  ];

  // ── Search (deterministic, filter-aware, cursor-paginated) ────────────

  /// All eight seeded businesses, canonical order (portal order).
  static List<Map<String, dynamic>> allBusinesses() => [
    _restaurantBusiness(),
    _restaurant2Business(),
    _hotelBusiness(),
    _hotel2Business(),
    _transitBusiness(),
    _transit2Business(),
    _retailBusiness(),
    _retail2Business(),
  ];

  /// Deterministic demo search. Supports query text, category (wire value,
  /// with the launcher's REAL_ESTATE→HOSPITALITY alias), verified filter and
  /// index-based cursor pagination. This is not a ranking engine — it is a
  /// logically correct local filter so category/query/verified selections
  /// genuinely change the result set.
  static Map<String, dynamic> searchBusinesses({
    String? q,
    String? category,
    bool? verified,
    int limit = 20,
    String? cursor,
  }) {
    final filtered = _filterBusinesses(
      allBusinesses(),
      q: q,
      category: category,
      verified: verified,
    );
    return _pageOf(filtered, limit, cursor, 'businesses');
  }

  /// Deterministic nearby search over the seeded locations — a faithful
  /// mirror of the REAL `/business/search/nearby` contract
  /// (services/businessLocationService.js in AZM-backend):
  ///
  /// • offset pagination (`page`, 0-based) + `hasMore`/`nextPage` (int) —
  ///   NOT cursors. The real client sends `page`; the previous demo
  ///   handler read a `cursor` the real client never sends, so page 2 in
  ///   demo mode silently replayed page 1 (duplicated rows). That drift
  ///   is gone.
  /// • every row embeds the slim `businessProfile` object with EXACTLY
  ///   the field set the real include ships (id, bizId, businessName,
  ///   category, logoUrl, isVerified, averageRating, totalEscrows) — the
  ///   embedded facts power the Near You rows and category-correct map
  ///   markers without a second fetch, identically to production.
  /// • distanceKm is the real haversine from the request lat/lng,
  ///   rounded to 0.1 km, and rows are sorted ascending by distance —
  ///   pagination operates on the globally-ordered list, like the real
  ///   endpoint.
  static Map<String, dynamic> searchNearby({
    double? lat,
    double? lng,
    String? q,
    String? category,
    bool? verified,
    int limit = 20,
    int page = 0,
  }) {
    final byProfile = {for (final b in allBusinesses()) b['id'].toString(): b};
    final canMeasure = lat != null && lng != null;
    final locations = allBusinesses()
        .expand((b) => (b['locations'] as List).cast<Map<String, dynamic>>())
        .where((loc) {
          final biz = byProfile[loc['businessProfileId']];
          if (biz == null) return false;
          if (!_categoryMatches(biz, category)) return false;
          if (verified == true && biz['isVerified'] != true) return false;
          return _queryMatches(biz, q);
        })
        .map<Map<String, dynamic>>((loc) {
          final biz = byProfile[loc['businessProfileId']];
          if (biz == null) {
            // Unreachable — the where() above filters unknown profiles —
            // but fail closed rather than fabricate a profile.
            return {...loc, 'businessProfile': <String, dynamic>{}};
          }
          final requestLat = lat;
          final requestLng = lng;
          final double? distanceKm =
              canMeasure && requestLat != null && requestLng != null
              ? _haversineKm(
                  requestLat,
                  requestLng,
                  _num(loc['latitude']),
                  _num(loc['longitude']),
                )
              : null;
          return {
            ...loc,
            if (distanceKm != null) 'distanceKm': distanceKm,
            'businessProfile': {
              'id': biz['id'],
              'bizId': biz['bizId'],
              'businessName': biz['businessName'],
              'category': biz['category'],
              'logoUrl': biz['logoUrl'],
              'isVerified': biz['isVerified'] == true,
              'averageRating': biz['averageRating'],
              'totalEscrows': biz['totalEscrows'],
            },
          };
        })
        .toList(growable: false);

    if (canMeasure) {
      locations.sort(
        (a, b) => _num(a['distanceKm']).compareTo(_num(b['distanceKm'])),
      );
    }

    final take = limit <= 0 ? 20 : limit;
    final pageNum = page < 0 ? 0 : page;
    final start = pageNum * take;
    final end = (start + take).clamp(0, locations.length);
    final slice = locations.sublist(start.clamp(0, locations.length), end);
    final hasMore = end < locations.length;
    return {
      'locations': slice,
      'hasMore': hasMore,
      'nextPage': hasMore ? pageNum + 1 : null,
    };
  }

  // ── G1 — Mix discovery feed (GET /discovery/items) ───────────────────
  // The canonical cross-store discovery surface the Mix tab reads. Every
  // row reuses a REAL seeded business/product identity, seeded media and
  // a seeded location label. Each offer carries an AUTHORITATIVE GHS
  // sample price declared as a literal — never computed or converted from
  // any USDC value (owner rule: discovery renders authoritative GHS only).
  static const int discoveryDefaultLimit = 24;

  static Map<String, dynamic> _offer({
    required String productId,
    required String businessId,
    required String bizId,
    required String businessName,
    required String businessCategory,
    required String businessLogoUrl,
    required String name,
    required String description,
    required List<String> images,
    required List<String> tags,
    required String ghsAmount,
    required String taxonomy,
    required String locationLabel,
    required String city,
    required String region,
    bool orderable = false,
    bool bookable = false,
    bool deliverable = false,
    bool dineIn = false,
    int? preparationMins,
    String? deliveryTerms,
    String? estimatedDelivery,
  }) => {
    'id': productId,
    'businessId': businessId,
    'bizId': bizId,
    'businessName': businessName,
    'businessCategory': businessCategory,
    'businessLogoUrl': businessLogoUrl,
    'item': {
      'name': name,
      'description': description,
      'images': images,
      'tags': tags,
    },
    'pricing': {
      'currency': 'GHS',
      'displayCurrency': 'GHS',
      'amount': ghsAmount,
    },
    'availability': {
      'isAvailable': true,
      'sectionWindowOpen': true,
      if (preparationMins != null) 'preparationMins': preparationMins,
      if (deliveryTerms != null) 'deliveryTerms': deliveryTerms,
      if (estimatedDelivery != null) 'estimatedDelivery': estimatedDelivery,
    },
    // Structured location: the label is the established display DTO;
    // city/region carry the seeded metadata that drives the city and
    // region filters (never a text search over the label).
    'location': {
      'label': locationLabel,
      'city': city,
      'region': region,
      'country': 'Ghana',
    },
    'section': {'taxonomy': taxonomy},
    'action': 'ENQUIRE',
    'capabilities': {
      'orderable': orderable,
      'bookable': bookable,
      'deliverable': deliverable,
      'dineIn': dineIn,
      // payability is USDC-only today — same honest limit as the
      // real gateway's supportedCapabilities contract.
      'payableIn': ['USDC'],
    },
  };

  /// The full deterministic discovery catalog: FIXED order, stable IDs,
  /// offers from all four seeded categories. EVERY row is DERIVED from the
  /// seed's own ground truth (menus, hotel rooms, transit tickets, retail
  /// products, business records, seeded locations) — an offer cannot drift
  /// from its source item, and its displayed identity is coherent with
  /// that source by construction.
  static List<Map<String, dynamic>> _discoveryCatalog() => [
    // ── FOOD_BEVERAGE — real seeded menu dishes ─────────────────────
    _menuDishOffer(
      bizId: restaurantBizId,
      dishId: 'dish-jollof',
      ghsAmount: '45.00',
      deliverable: true,
      dineIn: true,
      preparationMins: 15,
      deliveryTerms: 'within 5km',
      estimatedDelivery: '35 min',
    ),
    _menuDishOffer(
      bizId: restaurantBizId,
      dishId: 'drink-sobo',
      ghsAmount: '12.00',
      deliverable: true,
      dineIn: true,
      preparationMins: 5,
    ),
    _menuDishOffer(
      bizId: restaurantBizId,
      dishId: 'dessert-bofrot',
      ghsAmount: '18.00',
      deliverable: true,
      dineIn: true,
      preparationMins: 8,
    ),
    _menuDishOffer(
      bizId: restaurant2BizId,
      dishId: 'dish2-suya',
      ghsAmount: '38.00',
      deliverable: true,
      dineIn: true,
      preparationMins: 12,
      deliveryTerms: 'within 8km',
      estimatedDelivery: '40 min',
    ),
    // ── HOSPITALITY — real seeded hotel rooms ──────────────────────
    _roomOffer(bizId: hotelBizId, roomNumber: 101, ghsAmount: '350.00'),
    _roomOffer(bizId: hotel2BizId, roomNumber: 201, ghsAmount: '610.00'),
    // ── LOGISTICS — real seeded transit tickets ────────────────────
    _ticketOffer(
      bizId: transitBizId,
      ticketId: 'prod-transit-001-std',
      ghsAmount: '90.00',
    ),
    _ticketOffer(
      bizId: transit2BizId,
      ticketId: 'prod-transit-002-vip',
      ghsAmount: '120.00',
    ),
    // ── RETAIL — real seeded retail products ────────────────────────
    _retailOffer(
      bizId: retailBizId,
      productId: 'prod-tshirt',
      ghsAmount: '180.00',
      deliverable: true,
    ),
    _retailOffer(
      bizId: retailBizId,
      productId: 'prod-throw-pillow',
      ghsAmount: '65.00',
      deliverable: true,
    ),
    _retailOffer(
      bizId: retail2BizId,
      productId: 'prod-adinkra-cloth',
      ghsAmount: '95.00',
    ),
    _retailOffer(
      bizId: retail2BizId,
      productId: 'prod-ahesi-ceramic',
      ghsAmount: '110.00',
    ),
  ];

  /// The seeded menu section → canonical taxonomy mapping. Wire-exact
  /// with [MixTaxonomy.canonical]: a section without a mapping is a seed
  /// error (never an invented taxonomy ID).
  static const Map<String, String> _menuSectionTaxonomy = {
    'Starters': 'STARTERS',
    'Light Bites': 'STARTERS',
    'Main Courses': 'MEALS',
    'From the Grill': 'MEALS',
    'Beverages': 'DRINKS',
    'Desserts': 'DESSERTS',
  };

  /// The seeded business record for a bizId (its locations included).
  static Map<String, dynamic> _seededBusiness(String bizId) {
    final business =
        getBusinessByBizId(bizId)['business'] as Map<String, dynamic>;
    if (business['bizId'] != bizId) {
      throw StateError('discovery seed: $bizId is not a seeded business');
    }
    return business;
  }

  /// The business's primary seeded location (the structured source for
  /// label/city/region truth).
  static Map<String, dynamic> _seededLocation(Map<String, dynamic> business) {
    final locations = business['locations'] as List;
    if (locations.isEmpty) {
      throw StateError(
        'discovery seed: ${business['id']} has no seeded location',
      );
    }
    return locations.first as Map<String, dynamic>;
  }

  /// A discovery offer for a REAL seeded menu dish. Item identity (id,
  /// name, description, images, tags) and owning business come from the
  /// seeded menu itself; the taxonomy is derived from the dish's seeded
  /// section via [_menuSectionTaxonomy]. The GHS price is an authored
  /// authoritative literal (never converted from any USDC value).
  static Map<String, dynamic> _menuDishOffer({
    required String bizId,
    required String dishId,
    required String ghsAmount,
    bool orderable = true,
    bool deliverable = false,
    bool dineIn = false,
    int? preparationMins,
    String? deliveryTerms,
    String? estimatedDelivery,
  }) {
    Map<String, dynamic>? dish;
    String? sectionName;
    for (final section in getMenu(bizId)['sections'] as List) {
      for (final product in section['products'] as List) {
        if (product['id'] == dishId) {
          dish = product as Map<String, dynamic>;
          sectionName = section['name'] as String;
          break;
        }
      }
      if (dish != null) break;
    }
    if (dish == null) {
      throw StateError(
        'discovery seed: $dishId is not a seeded menu item '
        'of $bizId',
      );
    }
    final taxonomy = _menuSectionTaxonomy[sectionName!];
    if (taxonomy == null) {
      throw StateError(
        'discovery seed: menu section "$sectionName" has no '
        'canonical taxonomy — do not invent IDs',
      );
    }
    final business = _seededBusiness(bizId);
    final location = _seededLocation(business);
    return _offer(
      productId: dish['id'] as String,
      businessId: business['id'] as String,
      bizId: bizId,
      businessName: business['businessName'] as String,
      businessCategory: business['category'] as String,
      businessLogoUrl: business['logoUrl'] as String,
      name: dish['name'] as String,
      description: dish['description'] as String,
      images: (dish['imageUrls'] as List).cast<String>(),
      tags: (dish['tags'] as List).cast<String>(),
      ghsAmount: ghsAmount,
      taxonomy: taxonomy,
      locationLabel: location['label'] as String,
      city: location['city'] as String,
      region: location['region'] as String,
      orderable: orderable,
      deliverable: deliverable,
      dineIn: dineIn,
      preparationMins: preparationMins,
      deliveryTerms: deliveryTerms,
      estimatedDelivery: estimatedDelivery,
    );
  }

  /// A discovery offer for a REAL seeded hotel room, identified by the
  /// deterministic seeded room numbering (floor*100+room).
  static Map<String, dynamic> _roomOffer({
    required String bizId,
    required int roomNumber,
    required String ghsAmount,
    bool bookable = true,
  }) {
    final business = _seededBusiness(bizId);
    final profileId = business['id'] as String;
    final room = _hotelRooms(profileId)
        .where((r) => r['id'] == 'room-$profileId-$roomNumber')
        .toList(growable: false);
    if (room.isEmpty) {
      throw StateError(
        'discovery seed: room $roomNumber is not a seeded '
        'room of $profileId',
      );
    }
    final source = room.first;
    final location = _seededLocation(business);
    return _offer(
      productId: source['id'] as String,
      businessId: profileId,
      bizId: bizId,
      businessName: business['businessName'] as String,
      businessCategory: business['category'] as String,
      businessLogoUrl: business['logoUrl'] as String,
      name: source['name'] as String,
      description: source['description'] as String,
      images: (source['imageUrls'] as List).cast<String>().take(1).toList(),
      tags: (source['tags'] as List).cast<String>(),
      ghsAmount: ghsAmount,
      taxonomy: 'ROOMS',
      locationLabel: location['label'] as String,
      city: location['city'] as String,
      region: location['region'] as String,
      bookable: bookable,
    );
  }

  /// A discovery offer for a REAL seeded transit ticket or retail
  /// product, verified against the public seeded catalogue — including
  /// that the item belongs to the named business.
  static Map<String, dynamic> _catalogProductOffer({
    required String bizId,
    required String productId,
    required String ghsAmount,
    required String taxonomy,
    bool orderable = false,
    bool bookable = false,
    bool deliverable = false,
  }) {
    final business = _seededBusiness(bizId);
    final product =
        getProductById(productId)['product'] as Map<String, dynamic>;
    if (product['businessProfileId'] != business['id']) {
      throw StateError(
        'discovery seed: $productId is not owned by '
        '${business['id']}',
      );
    }
    final location = _seededLocation(business);
    return _offer(
      productId: product['id'] as String,
      businessId: business['id'] as String,
      bizId: bizId,
      businessName: business['businessName'] as String,
      businessCategory: business['category'] as String,
      businessLogoUrl: business['logoUrl'] as String,
      name: product['name'] as String,
      description: product['description'] as String,
      images: (product['imageUrls'] as List).cast<String>(),
      tags: (product['tags'] as List).cast<String>(),
      ghsAmount: ghsAmount,
      taxonomy: taxonomy,
      locationLabel: location['label'] as String,
      city: location['city'] as String,
      region: location['region'] as String,
      orderable: orderable,
      bookable: bookable,
      deliverable: deliverable,
    );
  }

  /// A discovery offer for a real seeded transit ticket (RIDES).
  static Map<String, dynamic> _ticketOffer({
    required String bizId,
    required String ticketId,
    required String ghsAmount,
  }) => _catalogProductOffer(
    bizId: bizId,
    productId: ticketId,
    ghsAmount: ghsAmount,
    taxonomy: 'RIDES',
    bookable: true,
  );

  /// A discovery offer for a real seeded retail product (RETAIL_ITEMS).
  static Map<String, dynamic> _retailOffer({
    required String bizId,
    required String productId,
    required String ghsAmount,
    bool deliverable = false,
  }) => _catalogProductOffer(
    bizId: bizId,
    productId: productId,
    ghsAmount: ghsAmount,
    taxonomy: 'RETAIL_ITEMS',
    orderable: true,
    deliverable: deliverable,
  );

  /// Deterministic GET /discovery/items over the seeded catalog.
  /// Supports category, q, repeatable taxonomy chips, city/region,
  /// limit (clamped to the server's 1..50) and opaque offset cursors
  /// (`off-<n>`). An unparseable cursor is REFUSED (the demo world never
  /// fabricates a continuation) — exactly like the real endpoint would
  /// reject a malformed cursor rather than invent a page.
  static Map<String, dynamic> discoveryItems({
    String? category,
    String? q,
    List<String>? taxonomies,
    String? city,
    String? region,
    int? limit,
    String? cursor,
  }) {
    var offset = 0;
    if (cursor != null) {
      final m = RegExp(r'^off-(\d+)$').firstMatch(cursor.trim());
      if (m == null) {
        throw DemoEndpointNotSeededException(
          'GET',
          '/discovery/items (bad cursor: "$cursor")',
        );
      }
      offset = int.parse(m.group(1)!);
    }

    // Taxonomy chips are wire-exact with the backend overlay: the server
    // answers an unknown chip with a 422, so the demo refuses one the same
    // way it refuses a malformed cursor — never a fabricated result set.
    // A CANONICAL chip with no seeded items is different: that is an
    // honest empty success (the documented unmapped behaviour).
    final wantedTaxonomies = (taxonomies ?? const <String>[]).toSet();
    final canonicalIds = MixTaxonomy.canonical.map((t) => t.id).toSet();
    for (final chip in wantedTaxonomies) {
      if (!canonicalIds.contains(chip)) {
        throw DemoEndpointNotSeededException(
          'GET',
          '/discovery/items (unknown taxonomy: "$chip")',
        );
      }
    }
    final needle = q?.trim().toLowerCase();

    final filtered = _discoveryCatalog()
        .where((row) {
          if (category != null && category.trim().isNotEmpty) {
            final cat = category.trim().toUpperCase();
            final rowCat = row['businessCategory'].toString();
            if (rowCat != cat &&
                !(cat == 'HOSPITALITY' && rowCat == 'REAL_ESTATE')) {
              return false;
            }
          }
          if (wantedTaxonomies.isNotEmpty &&
              !wantedTaxonomies.contains(
                row['section']['taxonomy'].toString(),
              )) {
            return false;
          }
          // City and region filter on the seeded STRUCTURED metadata, never a
          // text search over the display label: an offer whose real location
          // is Accra must match city=Accra even when its label reads
          // "Spintex Road".
          if (city != null && city.trim().isNotEmpty) {
            if (row['location']['city'].toString().trim().toLowerCase() !=
                city.trim().toLowerCase()) {
              return false;
            }
          }
          if (region != null && region.trim().isNotEmpty) {
            if (row['location']['region'].toString().trim().toLowerCase() !=
                region.trim().toLowerCase()) {
              return false;
            }
          }
          if (needle != null && needle.isNotEmpty) {
            final haystack = [
              row['businessName'].toString(),
              row['item']['name'].toString(),
              row['item']['description'].toString(),
              (row['item']['tags'] as List).join(' '),
            ].join(' ').toLowerCase();
            if (!haystack.contains(needle)) return false;
          }
          return true;
        })
        .toList(growable: false);

    final effectiveLimit = (limit ?? discoveryDefaultLimit).clamp(1, 50);
    final page = filtered.skip(offset).take(effectiveLimit).toList();
    final nextOffset = offset + page.length;
    return {
      'success': true,
      'items': page,
      'nextCursor': nextOffset < filtered.length ? 'off-$nextOffset' : null,
    };
  }

  /// Real haversine, rounded the way the production endpoint rounds it
  /// (0.1 km precision).
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        _sq(_sin(dLat / 2)) +
        _cos(_rad(lat1)) * _cos(_rad(lat2)) * _sq(_sin(dLng / 2));
    final km = r * 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return (km * 10).roundToDouble() / 10;
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : 0.0;
  static double _rad(double deg) => deg * 3.141592653589793 / 180.0;
  static double _sq(double v) => v * v;
  static double _sin(double v) => math.sin(v);
  static double _cos(double v) => math.cos(v);
  static double _sqrt(double v) => math.sqrt(v);
  static double _atan2(double y, double x) => math.atan2(y, x);

  static List<Map<String, dynamic>> _filterBusinesses(
    List<Map<String, dynamic>> businesses, {
    String? q,
    String? category,
    bool? verified,
  }) {
    return businesses
        .where((b) {
          if (!_categoryMatches(b, category)) return false;
          if (verified == true && b['isVerified'] != true) return false;
          return _queryMatches(b, q);
        })
        .toList(growable: false);
  }

  static bool _categoryMatches(Map<String, dynamic> b, String? category) {
    if (category == null || category.isEmpty) return true;
    final wire = b['category'].toString().toUpperCase();
    final wanted = category.toUpperCase();
    // The in-app dial historically sends REAL_ESTATE for hotels — the same
    // wire-compatibility the production backend honours.
    if (wanted == 'REAL_ESTATE') return wire == 'HOSPITALITY';
    return wire == wanted;
  }

  static bool _queryMatches(Map<String, dynamic> b, String? q) {
    final query = (q ?? '').trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      b['businessName']?.toString() ?? '',
      b['description']?.toString() ?? '',
      b['subcategory']?.toString() ?? '',
      ...((b['cuisineTypes'] as List?) ?? const []).map((e) => e.toString()),
      ...((b['amenities'] as List?) ?? const []).map((e) => e.toString()),
    ].join(' ').toLowerCase();
    // Every whitespace-separated term must appear — "jollof accra" only
    // matches a business mentioning both.
    return query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(haystack.contains);
  }

  /// Cursor semantics: the cursor is the next start index (as a string).
  static Map<String, dynamic> _pageOf(
    List<Map<String, dynamic>> rows,
    int limit,
    String? cursor,
    String rowsKey, {
    String hasMoreKey = 'hasMore',
    String cursorKey = 'nextCursor',
  }) {
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final clampedStart = start.clamp(0, rows.length);
    final effectiveLimit = limit <= 0 ? 20 : limit;
    final end = (clampedStart + effectiveLimit).clamp(0, rows.length);
    final slice = rows.sublist(clampedStart, end);
    final hasMore = end < rows.length;
    return {
      rowsKey: slice,
      hasMoreKey: hasMore,
      cursorKey: hasMore ? '$end' : null,
    };
  }

  // ── Business lookups ────────────────────────────────────────────────

  static Map<String, dynamic> getBusinessByBizId(String bizId) {
    final match = allBusinesses()
        .where((b) => b['bizId'] == bizId)
        .toList(growable: false);
    if (match.isEmpty) {
      throw DemoEndpointNotSeededException('GET', '/business/$bizId');
    }
    return {'business': match.first};
  }

  static Map<String, dynamic> getMenu(String bizId) {
    if (bizId == restaurantBizId) {
      return {
        'sections': [
          {
            'id': 'sec-starters',
            'name': 'Starters',
            'description': 'Small plates to share',
            'products': [
              _dish(
                'dish-kelewele',
                'Kelewele',
                'Spicy fried plantain cubes with ginger and pepper',
                4.50,
                ['spicy', 'veg'],
                DemoMedia.rThird,
                restaurantBizId,
              ),
              _dish(
                'dish-jollof',
                'Jollof Rice',
                'Smoky one-pot rice in tomato-pepper sauce',
                12.00,
                ['veg'],
                DemoMedia.rCover,
                restaurantBizId,
              ),
              _dish(
                'dish-suya',
                'Beef Suya',
                'Grilled spiced beef skewers with yaji rub',
                8.50,
                ['spicy'],
                DemoMedia.rAlt,
                restaurantBizId,
              ),
              _dish(
                'dish-salad',
                'Avocado Salad',
                'Fresh avocado, tomato, red onion, lime dressing',
                6.00,
                ['veg'],
                DemoMedia.rThird,
                restaurantBizId,
              ),
            ],
          },
          {
            'id': 'sec-mains',
            'name': 'Main Courses',
            'description': 'Hearty Ghanaian classics',
            'products': [
              _dish(
                'dish-waakye',
                'Waakye & Stew',
                'Rice & beans with spaghetti, egg, shito, and fried plantain',
                14.50,
                [],
                DemoMedia.rCover,
                restaurantBizId,
              ),
              _dish(
                'dish-banku',
                'Banku & Tilapia',
                'Grilled tilapia with fermented corn dough',
                18.00,
                [],
                DemoMedia.rAlt,
                restaurantBizId,
              ),
              _dish(
                'dish-fufu',
                'Fufu & Light Soup',
                'Pounded cassava with goat light soup',
                16.00,
                ['spicy'],
                DemoMedia.rThird,
                restaurantBizId,
              ),
              _dish(
                'dish-redred',
                'Red Red',
                'Bean stew with fried plantain',
                10.00,
                ['veg'],
                DemoMedia.rCover,
                restaurantBizId,
              ),
              _dish(
                'dish-omotuo',
                'Omo Tuo & Groundnut Soup',
                'Rice balls in rich peanut soup with chicken',
                15.00,
                [],
                DemoMedia.rAlt,
                restaurantBizId,
              ),
            ],
          },
          {
            'id': 'sec-drinks',
            'name': 'Beverages',
            'description': 'Fresh & chilled',
            'products': [
              _dish(
                'drink-sobo',
                'Sobolo',
                'Hibiscus iced tea with ginger',
                3.00,
                ['veg'],
                DemoMedia.rThird,
                restaurantBizId,
              ),
              _dish(
                'drink-palm',
                'Palm Wine',
                'Freshly tapped from the Eastern Region',
                4.00,
                [],
                DemoMedia.rCover,
                restaurantBizId,
              ),
              _dish(
                'drink-asana',
                'Asana',
                'Corn drink with fermented milk',
                3.50,
                ['veg'],
                DemoMedia.rAlt,
                restaurantBizId,
              ),
            ],
          },
          {
            'id': 'sec-desserts',
            'name': 'Desserts',
            'description': 'Sweet endings',
            'products': [
              _dish(
                'dessert-kele',
                'Kelewele Sundae',
                'Vanilla ice cream with caramelised plantain',
                7.00,
                ['veg'],
                DemoMedia.rThird,
                restaurantBizId,
              ),
              _dish(
                'dessert-bofrot',
                'Bofrot Trio',
                'Three puff puffs with chocolate dip',
                5.00,
                ['veg'],
                DemoMedia.rCover,
                restaurantBizId,
              ),
            ],
          },
        ],
        'uncategorisedProducts': [],
      };
    }
    if (bizId == restaurant2BizId) {
      return {
        'sections': [
          {
            'id': 'sec-2-light',
            'name': 'Light Bites',
            'description': 'Street-food favourites',
            'products': [
              _dish(
                'dish2-kelewele',
                'Kelewele Bowl',
                'Double-spice plantain with groundnuts',
                5.00,
                ['spicy', 'veg'],
                DemoMedia.rCover,
                restaurant2BizId,
              ),
              _dish(
                'dish2-koshari',
                'Koshari',
                'Rice, lentils and pasta in tomato sauce',
                9.00,
                ['veg'],
                DemoMedia.rAlt,
                restaurant2BizId,
              ),
            ],
          },
          {
            'id': 'sec-2-grill',
            'name': 'From the Grill',
            'description': 'Charcoal-grilled to order',
            'products': [
              _dish(
                'dish2-suya',
                'Chicken Suya',
                'Yaji-rubbed grilled chicken thighs',
                11.00,
                ['spicy'],
                DemoMedia.rThird,
                restaurant2BizId,
              ),
              _dish(
                'dish2-tilapia',
                'Whole Tilapia',
                'Stuffed with shito and served with banku',
                22.00,
                [],
                DemoMedia.rCover,
                restaurant2BizId,
              ),
            ],
          },
          {
            'id': 'sec-2-drinks',
            'name': 'Beverages',
            'description': 'Cold and fresh',
            'products': [
              _dish(
                'drink2-lamugin',
                'Lamugin',
                'Spiced ginger juice over ice',
                3.50,
                ['veg'],
                DemoMedia.rAlt,
                restaurant2BizId,
              ),
            ],
          },
        ],
        'uncategorisedProducts': [],
      };
    }
    // Menus are a restaurant-only concept — an empty menu for any other
    // vertical is the truthful, explicitly-seeded response.
    return {'sections': [], 'uncategorisedProducts': []};
  }

  static Map<String, dynamic> getMyInvoices() => {
    'invoices': [_unpaidInvoice(), _paidInvoice()],
    'hasMore': false,
    'nextCursor': null,
  };

  static Map<String, dynamic> getInvoice(String invoiceId) {
    if (!isSeededId(invoiceId, seededInvoiceIds)) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/business/invoices/$invoiceId',
      );
    }
    return {
      'invoice': invoiceId == 'inv-restaurant-001'
          ? _unpaidInvoice()
          : _paidInvoice(),
    };
  }

  static Map<String, dynamic> getMyOrders() => {
    'orders': [
      {
        'id': 'ord-001',
        'businessProfileId': 'restaurant-001',
        'orderRef': 'AZM-ORD-101',
        'title': "Chef Abby's takeaway",
        'customerId': 1,
        'productId': 'dish-jollof',
        'status': 'COMPLETED',
        'amountUsdc': 12.00,
        'description': 'Jollof Rice × 1',
        'createdAt': _daysAgo(2),
      },
      {
        'id': 'ord-002',
        'businessProfileId': 'retail-001',
        'orderRef': 'AZM-ORD-102',
        'title': 'Mr. Price cotton tee',
        'customerId': 1,
        'productId': 'prod-tshirt',
        'status': 'IN_ESCROW',
        'amountUsdc': 8.00,
        'description': 'Cotton Crew Tee × 1',
        'createdAt': _hoursAgo(6),
      },
    ],
    'hasMore': false,
    'nextCursor': null,
  };

  /// Demo user owns no business — the truthful stats are zeros.
  static Map<String, dynamic> getOwnerStats() => {
    'stats': {
      'totalOrders': 0,
      'completedOrders': 0,
      'pendingOrders': 0,
      'disputedOrders': 0,
      'cancelledOrders': 0,
      'totalRevenue': 0.0,
      'avgOrderValue': 0.0,
      'recentOrders': [],
    },
  };

  /// Demo user owns no business — an empty notification feed is the
  /// truthful, explicit decision here (not a fake fallback).
  static Map<String, dynamic> getOwnerNotifications() => {
    'notifications': [],
    'hasMore': false,
    'nextCursor': null,
    'unreadCount': 0,
  };

  /// Demo user owns no business — KYB is unstarted.
  static Map<String, dynamic> getKybStatus() => {
    'kybStatus': 'UNVERIFIED',
    'documents': [],
  };

  /// Owner-scoped global product list — demo user owns none.
  static Map<String, dynamic> getMyProducts() => {
    'products': [],
    'hasMore': false,
    'nextCursor': null,
  };

  /// Public single-product lookup across the seeded catalogue.
  static Map<String, dynamic> getProductById(String productId) {
    // The FULL seeded catalogue: transit-002's tickets are seeded too —
    // an endpoint that answers "not seeded" for a genuinely seeded product
    // is a truthfulness bug, not a scoping decision.
    final catalogue = [
      ..._transitProducts('transit-001'),
      ..._transitProducts('transit-002'),
      ..._retailProducts('retail-001'),
      ..._retailProducts('retail-002'),
    ];
    final match = catalogue
        .where((p) => p['id'] == productId)
        .toList(growable: false);
    if (match.isEmpty) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/business/products/$productId',
      );
    }
    return {'product': match.first};
  }

  // ── Transit ──────────────────────────────────────────────────────────

  static Map<String, dynamic> getTransitTrips() {
    return {
      'success': true,
      'trips': [
        {
          'id': 'trip-001',
          'businessProfileId': 'transit-001',
          'vehicleId': 'veh-001',
          'routeName': 'Accra to Kumasi Express',
          'origin': 'Accra',
          'destination': 'Kumasi',
          'departureAt': _hoursFromNow(3),
          'arrivalAt': _hoursFromNow(6),
          'fareUsdc': 15.00,
          'availableSeats': 22,
          'status': 'SCHEDULED',
          'vehicle': {
            'type': 'COACH',
            'make': 'Mercedes-Benz',
            'model': 'Sprinter 450',
            'imageUrl': DemoMedia.tCover,
            'driverName': 'Kwabena Owusu',
            'driverPhotoUrl': DemoMedia.tLogo,
            'plateNumber': 'GT 4521-24',
            'coDriverName': 'Akosua Mensah',
            'coDriverPhotoUrl': DemoMedia.tAlt,
          },
          '_count': {'bookings': 12},
        },
        {
          'id': 'trip-002',
          'businessProfileId': 'transit-001',
          'vehicleId': 'veh-002',
          'routeName': 'Accra to Cape Coast Run',
          'origin': 'Accra',
          'destination': 'Cape Coast',
          'departureAt': _hoursFromNow(5),
          'arrivalAt': _hoursFromNow(7),
          'fareUsdc': 10.00,
          'availableSeats': 28,
          'status': 'SCHEDULED',
          'vehicle': {
            'type': 'MINIVAN',
            'make': 'Toyota',
            'model': 'HiAce',
            'imageUrl': DemoMedia.tAlt,
            'driverName': 'Yaw Mensah',
            'driverPhotoUrl': DemoMedia.tLogo,
            'plateNumber': 'GR 8892-25',
          },
          '_count': {'bookings': 6},
        },
        {
          'id': 'trip-003',
          'businessProfileId': 'transit-002',
          'vehicleId': 'veh-101',
          'routeName': 'Accra to Ho Scenic',
          'origin': 'Accra',
          'destination': 'Ho',
          'departureAt': _hoursFromNow(4),
          'arrivalAt': _hoursFromNow(7),
          'fareUsdc': 12.00,
          'availableSeats': 16,
          'status': 'SCHEDULED',
          'vehicle': {
            'type': 'MINIBUS',
            'make': 'Nissan',
            'model': 'Urvan',
            'imageUrl': DemoMedia.tThird,
            'driverName': 'Kofi Boateng',
            'driverPhotoUrl': DemoMedia.tLogo,
            'plateNumber': 'GR 3320-24',
          },
          '_count': {'bookings': 9},
        },
        {
          'id': 'trip-004',
          'businessProfileId': 'transit-002',
          'vehicleId': 'veh-102',
          'routeName': 'Kumasi to Tamale Overnight',
          'origin': 'Kumasi',
          'destination': 'Tamale',
          'departureAt': _hoursFromNow(9),
          'arrivalAt': _hoursFromNow(17),
          'fareUsdc': 20.00,
          'availableSeats': 24,
          'status': 'SCHEDULED',
          'vehicle': {
            'type': 'COACH',
            'make': 'Yutong',
            'model': 'ZK6122',
            'imageUrl': DemoMedia.tCover,
            'driverName': 'Fuseini Iddrisu',
            'driverPhotoUrl': DemoMedia.tAlt,
            'plateNumber': 'AS 1109-23',
          },
          '_count': {'bookings': 15},
        },
      ],
    };
  }

  static Map<String, dynamic> getTripSeats(String tripId) {
    if (!isSeededId(tripId, seededTripIds)) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/marketplace/transit/trips/$tripId/seats',
      );
    }
    final seats = <Map<String, dynamic>>[];
    final occupied = {'1A', '2B', '3D', '5A', '7C', '10B', '10D'};
    for (var row = 1; row <= 10; row++) {
      for (var col = 0; col < 4; col++) {
        final seatLetter = String.fromCharCode(65 + col);
        final seatId = '$row$seatLetter';
        final isWindow = col == 0 || col == 3;
        var tier = 'ECONOMY';
        var fare = 15.0;
        if (row <= 2) {
          tier = 'VIP';
          fare = 25.0;
        } else if (row <= 5) {
          tier = 'STANDARD';
          fare = 18.0;
        }
        seats.add({
          'seatId': seatId,
          'row': row,
          'col': col + 1,
          'type': isWindow ? 'WINDOW' : 'AISLE',
          'status': occupied.contains(seatId) ? 'OCCUPIED' : 'AVAILABLE',
          'tier': tier,
          'fare': fare,
        });
      }
    }
    return {
      'success': true,
      'tripId': tripId,
      'seats': seats,
      'availableCount': seats.where((s) => s['status'] == 'AVAILABLE').length,
      'totalSeats': seats.length,
      'tripStatus': 'SCHEDULED',
      'fareUsdc': 15.0,
      'tierFares': {'VIP': 25.0, 'STANDARD': 18.0, 'ECONOMY': 15.0},
    };
  }

  static Map<String, dynamic> getTrustScore(String azamanId) {
    if (azamanId.trim() != seededTrustScoreAzamanId) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/marketplace/trust-score/$azamanId',
      );
    }
    return {
      'trustLevel': 'GOOD',
      'noShowRate': 0.02,
      'totalBookings': 14,
      'noShowCount': 0,
      'completedBookings': 14,
    };
  }

  /// Legacy dine-in tab path (marketplace_booking_service). Coherent OPEN
  /// tab on the seeded restaurant so the endpoint is explicitly covered.
  static Map<String, dynamic> getDineInTab(String tabId) {
    if (!isSeededId(tabId, seededDineInTabIds)) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/marketplace/business/dine-in/$tabId',
      );
    }
    return {
      'data': {
        'id': tabId,
        'status': 'OPEN',
        'openedAt': _hoursAgo(1),
        'subtotalUsdc': 15.00,
        'taxTotalUsdc': 0.75,
        'tipUsdc': 0.0,
        'grandTotalUsdc': 15.75,
        'businessProfile': {
          'id': 'restaurant-001',
          'bizId': restaurantBizId,
          'businessName': "Chef Abby's",
          'logoUrl': DemoMedia.rLogo,
        },
        'table': {
          'id': 'tbl-005',
          'label': 'Table 12',
          'locationId': 'loc-rest-001',
        },
        'items': [
          {
            'id': 'di-1',
            'name': 'Jollof Rice',
            'unitPrice': 12.00,
            'quantity': 1,
            'lineTotal': 12.00,
            'addedAt': _hoursAgo(1),
          },
          {
            'id': 'di-2',
            'name': 'Sobolo',
            'unitPrice': 3.00,
            'quantity': 1,
            'lineTotal': 3.00,
            'addedAt': _minutesAgo(50),
          },
        ],
      },
    };
  }

  // ── Reviews ──────────────────────────────────────────────────────────

  /// Two coherent reviews per business — real content, not a fake empty
  /// list contradicting the business's reviewCount.
  static Map<String, dynamic> getReviews(String bizId) {
    final businesses = {
      restaurantBizId: ["Chef Abby's", 'restaurant-001'],
      restaurant2BizId: ["Mama Titi's Kitchen", 'restaurant-002'],
      hotelBizId: ['The Gallery', 'hotel-001'],
      hotel2BizId: ['Coastline Suites', 'hotel-002'],
      transitBizId: ['Advenr', 'transit-001'],
      transit2BizId: ['Volta Lines', 'transit-002'],
      retailBizId: ['Mr. Price', 'retail-001'],
      retail2BizId: ['Accra Home Goods', 'retail-002'],
    };
    final entry = businesses[bizId];
    if (entry == null) {
      throw DemoEndpointNotSeededException('GET', '/business/$bizId/reviews');
    }
    final profileId = entry[1];
    return {
      'reviews': [
        {
          'id': 'rev-$bizId-1',
          'businessProfileId': profileId,
          'reviewerId': 11,
          'rating': 5,
          'comment':
              'Great experience — fast service and exactly as described.',
          'sourceType': 'ORDER',
          'createdAt': _daysAgo(5),
          'reviewer': {'id': 11, 'username': 'ama_k'},
          'reviewerUsername': 'ama_k',
        },
        {
          'id': 'rev-$bizId-2',
          'businessProfileId': profileId,
          'reviewerId': 12,
          'rating': 4,
          'comment': 'Good value. Will come back.',
          'sourceType': 'ORDER',
          'createdAt': _daysAgo(12),
          'reviewer': {'id': 12, 'username': 'yaw_o'},
          'reviewerUsername': 'yaw_o',
        },
      ],
      'hasMore': false,
      'nextCursor': null,
    };
  }

  // ── Products / rooms ─────────────────────────────────────────────────

  static Map<String, dynamic> getProducts(String bizId) {
    if (bizId == hotelBizId || bizId == 'hotel-001')
      return {'products': _hotelRooms('hotel-001')};
    if (bizId == hotel2BizId || bizId == 'hotel-002')
      return {'products': _hotelRooms('hotel-002')};
    if (bizId == transitBizId || bizId == 'transit-001')
      return {'products': _transitProducts('transit-001')};
    if (bizId == transit2BizId || bizId == 'transit-002')
      return {'products': _transitProducts('transit-002')};
    if (bizId == retailBizId || bizId == 'retail-001')
      return {'products': _retailProducts('retail-001')};
    if (bizId == retail2BizId || bizId == 'retail-002')
      return {'products': _retailProducts('retail-002')};
    if (bizId == restaurantBizId) {
      return {
        'products': [
          _dish(
            'dish-waakye',
            'Waakye & Stew',
            'Rice & beans with spaghetti, egg, shito',
            14.50,
            [],
            DemoMedia.rCover,
            restaurantBizId,
          ),
          _dish(
            'dish-jollof',
            'Jollof Rice',
            'Smoky one-pot rice',
            12.00,
            ['veg'],
            DemoMedia.rAlt,
            restaurantBizId,
          ),
        ],
      };
    }
    if (bizId == restaurant2BizId) {
      return {
        'products': [
          _dish(
            'dish2-suya',
            'Chicken Suya',
            'Yaji-rubbed grilled chicken thighs',
            11.00,
            ['spicy'],
            DemoMedia.rThird,
            restaurant2BizId,
          ),
          _dish(
            'dish2-koshari',
            'Koshari',
            'Rice, lentils and pasta in tomato sauce',
            9.00,
            ['veg'],
            DemoMedia.rCover,
            restaurant2BizId,
          ),
        ],
      };
    }
    throw DemoEndpointNotSeededException('GET', '/business/$bizId/products');
  }

  static Map<String, dynamic> getLocations(String bizId) {
    final match = allBusinesses()
        .where((b) => b['bizId'] == bizId)
        .toList(growable: false);
    if (match.isEmpty) {
      throw DemoEndpointNotSeededException('GET', '/business/$bizId/locations');
    }
    return {
      'locations': List<Map<String, dynamic>>.from(
        (match.first['locations'] as List).whereType<Map<String, dynamic>>(),
      ),
    };
  }

  static Map<String, dynamic> getShowcase(String bizId) {
    final byBizId = {
      restaurantBizId: [DemoMedia.rCover, DemoMedia.rAlt, DemoMedia.rThird],
      restaurant2BizId: [DemoMedia.rAlt, DemoMedia.rCover],
      hotelBizId: [
        DemoMedia.hCover,
        DemoMedia.hAlt,
        DemoMedia.hThird,
        DemoMedia.hAlt,
        DemoMedia.hCover,
      ],
      hotel2BizId: [DemoMedia.hThird, DemoMedia.hCover, DemoMedia.hAlt],
      transitBizId: [DemoMedia.tCover, DemoMedia.tAlt],
      transit2BizId: [DemoMedia.tThird, DemoMedia.tCover],
      retailBizId: [DemoMedia.rtAlt, DemoMedia.rtCover, DemoMedia.rtThird],
      retail2BizId: [DemoMedia.rtCover, DemoMedia.rtAlt],
    };
    final urls = byBizId[bizId];
    if (urls == null) {
      throw DemoEndpointNotSeededException('GET', '/showcases/$bizId');
    }
    return {'data': urls};
  }

  // ── Business definitions ──────────────────────────────────────────────

  static Map<String, dynamic> _restaurantBusiness() => {
    'id': 'restaurant-001',
    'bizId': restaurantBizId,
    'businessName': "Chef Abby's",
    'category': 'FOOD_BEVERAGE',
    'description':
        'Authentic Ghanaian cuisine in the heart of Accra. From jollof to waakye, every plate tells a story.',
    'website': 'https://chefabbys.gh',
    'logoUrl': DemoMedia.rLogo,
    'coverImageUrl': DemoMedia.rCover,
    'phoneNumber': '+233 24 123 4567',
    'address': 'Oxford Street, Osu, Accra',
    'country': 'Ghana',
    'isVerified': true,
    'isSuspended': false,
    'kybStatus': 'VERIFIED',
    'totalEscrows': 340,
    'completedEscrows': 335,
    'userId': 201,
    'totalVolume': 125000.00,
    'averageRating': 4.7,
    'reviewCount': 234,
    'subcategory': 'Restaurant',
    'priceRange': 2,
    'amenities': ['WiFi', 'Dine-in', 'Takeaway', 'Delivery', 'Parking'],
    'cuisineTypes': ['Ghanaian', 'African', 'Continental'],
    'adAccentColor': '#FF6B35',
    'user': {'id': 201, 'username': 'chef_abbys', 'profilePictureUrl': null},
    'products': [],
    'locations': [_restaurantLocation()],
  };

  static Map<String, dynamic> _restaurant2Business() {
    return {
      'id': 'restaurant-002',
      'bizId': restaurant2BizId,
      'businessName': "Mama Titi's Kitchen",
      'category': 'FOOD_BEVERAGE',
      'description':
          'Spintex road grill house. Charcoal suya, fresh tilapia and cold lamugin until late.',
      'website': 'https://mamatitis.gh',
      'logoUrl': DemoMedia.rAlt,
      'coverImageUrl': DemoMedia.rThird,
      'phoneNumber': '+233 27 445 8890',
      'address': 'Spintex Road, Accra',
      'country': 'Ghana',
      'isVerified': false,
      'isSuspended': false,
      'kybStatus': 'PENDING',
      'totalEscrows': 46,
      'completedEscrows': 44,
      'userId': 211,
      'totalVolume': 9200.00,
      'averageRating': 4.3,
      'reviewCount': 61,
      'subcategory': 'Grill House',
      'priceRange': 1,
      'amenities': ['Takeaway', 'Outdoor Seating', 'Late Night'],
      'cuisineTypes': ['Ghanaian', 'Barbecue'],
      'adAccentColor': '#F59E0B',
      'user': {'id': 211, 'username': 'mama_titi', 'profilePictureUrl': null},
      'products': [],
      'locations': [_restaurant2Location()],
    };
  }

  static Map<String, dynamic> _hotelBusiness() {
    return {
      'id': 'hotel-001',
      'bizId': hotelBizId,
      'businessName': 'The Gallery',
      'category': 'HOSPITALITY',
      'description':
          'Boutique apartments in East Legon. Fully furnished studios and 1-bedroom suites with 24/7 concierge.',
      'website': 'https://thegallery.gh',
      'logoUrl': DemoMedia.hLogo,
      'coverImageUrl': DemoMedia.hCover,
      'phoneNumber': '+233 26 987 6543',
      'address': 'East Legon, Greater Accra',
      'country': 'Ghana',
      'isVerified': true,
      'isSuspended': false,
      'kybStatus': 'VERIFIED',
      'totalEscrows': 180,
      'completedEscrows': 175,
      'userId': 202,
      'totalVolume': 85000.00,
      'averageRating': 4.8,
      'reviewCount': 156,
      'subcategory': 'Apartments',
      'priceRange': 3,
      'amenities': [
        'Pool',
        'Gym',
        'Spa',
        'WiFi',
        'Restaurant',
        'Bar',
        'Parking',
        'Concierge',
      ],
      'cuisineTypes': [],
      'adAccentColor': '#1A8FE3',
      'user': {'id': 202, 'username': 'the_gallery', 'profilePictureUrl': null},
      'products': _hotelRooms('hotel-001'),
      'locations': [_hotelLocation()],
      'businessMeta': {
        'showcaseUrls': [
          DemoMedia.hCover,
          DemoMedia.hAlt,
          DemoMedia.hThird,
          DemoMedia.hAlt,
          DemoMedia.hCover,
        ],
      },
    };
  }

  static Map<String, dynamic> _hotel2Business() {
    return {
      'id': 'hotel-002',
      'bizId': hotel2BizId,
      'businessName': 'Coastline Suites',
      'category': 'HOSPITALITY',
      'description':
          'Sea-view suites on Cape Coast beach road. Sunrise balconies, breakfast included, weekly rates for remote workers.',
      'website': 'https://coastlinesuites.gh',
      'logoUrl': DemoMedia.hAlt,
      'coverImageUrl': DemoMedia.hThird,
      'phoneNumber': '+233 31 202 3311',
      'address': 'Beach Road, Cape Coast',
      'country': 'Ghana',
      'isVerified': false,
      'isSuspended': false,
      'kybStatus': 'PENDING',
      'totalEscrows': 58,
      'completedEscrows': 56,
      'userId': 212,
      'totalVolume': 21800.00,
      'averageRating': 4.6,
      'reviewCount': 72,
      'subcategory': 'Beach Hotel',
      'priceRange': 2,
      'amenities': ['Sea View', 'Breakfast', 'WiFi', 'Airport Shuttle'],
      'cuisineTypes': [],
      'adAccentColor': '#A78BFA',
      'user': {
        'id': 212,
        'username': 'coastline_suites',
        'profilePictureUrl': null,
      },
      'products': _hotelRooms('hotel-002'),
      'locations': [_hotel2Location()],
      'businessMeta': {
        'showcaseUrls': [DemoMedia.hThird, DemoMedia.hCover, DemoMedia.hAlt],
      },
    };
  }

  static Map<String, dynamic> _transitBusiness() {
    return {
      'id': 'transit-001',
      'bizId': transitBizId,
      'businessName': 'Advenr',
      'category': 'LOGISTICS',
      'description':
          'Premium intercity travel. Modern fleet, professional drivers, on-time departures, comfortable seats.',
      'website': 'https://advenr.gh',
      'logoUrl': DemoMedia.tLogo,
      'coverImageUrl': DemoMedia.tCover,
      'phoneNumber': '+233 20 555 0199',
      'address': 'Circle Station, Accra',
      'country': 'Ghana',
      'isVerified': true,
      'isSuspended': false,
      'kybStatus': 'VERIFIED',
      'totalEscrows': 520,
      'completedEscrows': 515,
      'userId': 203,
      'totalVolume': 78000.00,
      'averageRating': 4.5,
      'reviewCount': 410,
      'subcategory': 'Intercity Bus',
      'priceRange': 1,
      'amenities': ['AC', 'WiFi', 'USB Charging', 'Refreshments'],
      'cuisineTypes': [],
      'adAccentColor': '#10B981',
      'user': {'id': 203, 'username': 'advenr', 'profilePictureUrl': null},
      'products': _transitProducts('transit-001'),
      'locations': [_transitLocation()],
    };
  }

  static Map<String, dynamic> _transit2Business() {
    return {
      'id': 'transit-002',
      'bizId': transit2BizId,
      'businessName': 'Volta Lines',
      'category': 'LOGISTICS',
      'description':
          'Scenic and overnight routes through the Volta corridor. Comfortable reclining seats, live trip tracking.',
      'website': 'https://voltalines.gh',
      'logoUrl': DemoMedia.tAlt,
      'coverImageUrl': DemoMedia.tThird,
      'phoneNumber': '+233 36 210 4477',
      'address': 'Ho Main Station, Ho',
      'country': 'Ghana',
      'isVerified': false,
      'isSuspended': false,
      'kybStatus': 'PENDING',
      'totalEscrows': 210,
      'completedEscrows': 205,
      'userId': 213,
      'totalVolume': 34000.00,
      'averageRating': 4.2,
      'reviewCount': 188,
      'subcategory': 'Regional Coach',
      'priceRange': 1,
      'amenities': ['AC', 'USB Charging', 'Live Tracking', 'Blanket'],
      'cuisineTypes': [],
      'adAccentColor': '#4F8EF7',
      'user': {'id': 213, 'username': 'volta_lines', 'profilePictureUrl': null},
      'products': _transitProducts('transit-002'),
      'locations': [_transit2Location()],
    };
  }

  static Map<String, dynamic> _retailBusiness() {
    return {
      'id': 'retail-001',
      'bizId': retailBizId,
      'businessName': 'Mr. Price',
      'category': 'RETAIL',
      'description': 'Fashion, homeware & lifestyle at everyday prices',
      'logoUrl': DemoMedia.rtLogo,
      'coverImageUrl': DemoMedia.rtCover,
      'isVerified': true,
      'isSuspended': false,
      'kybStatus': 'VERIFIED',
      'totalEscrows': 320,
      'completedEscrows': 315,
      'userId': 205,
      'totalVolume': 45000.00,
      'averageRating': 4.4,
      'reviewCount': 210,
      'subcategory': 'Fashion Retail',
      'priceRange': 1,
      'amenities': ['Changing Rooms', 'Click & Collect', 'Returns'],
      'cuisineTypes': [],
      'adAccentColor': '#00D97E',
      'user': {'id': 205, 'username': 'mr_price', 'profilePictureUrl': null},
      'products': _retailProducts('retail-001'),
      'locations': [_retailLocation()],
    };
  }

  static Map<String, dynamic> _retail2Business() {
    return {
      'id': 'retail-002',
      'bizId': retail2BizId,
      'businessName': 'Accra Home Goods',
      'category': 'RETAIL',
      'description':
          'Locally made homeware — woven baskets, ceramics and ashanti cloth for your space.',
      'logoUrl': DemoMedia.rtAlt,
      'coverImageUrl': DemoMedia.rtThird,
      'isVerified': false,
      'isSuspended': false,
      'kybStatus': 'PENDING',
      'totalEscrows': 74,
      'completedEscrows': 71,
      'userId': 214,
      'totalVolume': 11200.00,
      'averageRating': 4.1,
      'reviewCount': 39,
      'subcategory': 'Homeware',
      'priceRange': 2,
      'amenities': ['Click & Collect', 'Delivery'],
      'cuisineTypes': [],
      'adAccentColor': '#00D97E',
      'user': {'id': 214, 'username': 'accra_home', 'profilePictureUrl': null},
      'products': _retailProducts('retail-002'),
      'locations': [_retail2Location()],
    };
  }

  // ── Locations ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _restaurantLocation() => {
    'id': 'loc-rest-001',
    'businessProfileId': 'restaurant-001',
    'label': "Chef Abby's - Osu",
    'address': 'Oxford Street, Osu, Accra',
    'city': 'Accra',
    'region': 'Greater Accra',
    'country': 'Ghana',
    'latitude': 5.5550,
    'longitude': -0.1800,
    'isPrimary': true,
    'isActive': true,
    'galleryUrls': [DemoMedia.rCover, DemoMedia.rAlt, DemoMedia.rCover],
  };

  static Map<String, dynamic> _restaurant2Location() {
    return {
      'id': 'loc-rest-002',
      'businessProfileId': 'restaurant-002',
      'label': "Mama Titi's - Spintex",
      'address': 'Spintex Road, Accra',
      'city': 'Accra',
      'region': 'Greater Accra',
      'country': 'Ghana',
      'latitude': 5.6220,
      'longitude': -0.1180,
      'isPrimary': true,
      'isActive': true,
      'galleryUrls': [DemoMedia.rThird, DemoMedia.rCover],
    };
  }

  static Map<String, dynamic> _hotelLocation() => {
    'id': 'loc-hotel-001',
    'businessProfileId': 'hotel-001',
    'label': 'The Gallery - East Legon',
    'address': 'East Legon, Greater Accra',
    'city': 'Accra',
    'region': 'Greater Accra',
    'country': 'Ghana',
    'latitude': 5.6400,
    'longitude': -0.1680,
    'isPrimary': true,
    'isActive': true,
    'galleryUrls': [
      DemoMedia.hCover,
      DemoMedia.hAlt,
      DemoMedia.hThird,
      DemoMedia.hAlt,
      DemoMedia.hCover,
    ],
  };

  static Map<String, dynamic> _hotel2Location() {
    return {
      'id': 'loc-hotel-002',
      'businessProfileId': 'hotel-002',
      'label': 'Coastline Suites - Cape Coast',
      'address': 'Beach Road, Cape Coast',
      'city': 'Cape Coast',
      'region': 'Central',
      'country': 'Ghana',
      'latitude': 5.1050,
      'longitude': -1.2460,
      'isPrimary': true,
      'isActive': true,
      'galleryUrls': [DemoMedia.hThird, DemoMedia.hCover, DemoMedia.hAlt],
    };
  }

  static Map<String, dynamic> _transitLocation() => {
    'id': 'loc-transit-001',
    'businessProfileId': 'transit-001',
    'label': 'Advenr - Circle Station',
    'address': 'Circle Station, Accra',
    'city': 'Accra',
    'region': 'Greater Accra',
    'country': 'Ghana',
    'latitude': 5.5700,
    'longitude': -0.2050,
    'isPrimary': true,
    'isActive': true,
    'galleryUrls': [DemoMedia.tCover, DemoMedia.tAlt],
  };

  static Map<String, dynamic> _transit2Location() {
    return {
      'id': 'loc-transit-002',
      'businessProfileId': 'transit-002',
      'label': 'Volta Lines - Ho Main Station',
      'address': 'Ho Main Station, Ho',
      'city': 'Ho',
      'region': 'Volta',
      'country': 'Ghana',
      'latitude': 6.6060,
      'longitude': 0.4710,
      'isPrimary': true,
      'isActive': true,
      'galleryUrls': [DemoMedia.tThird, DemoMedia.tCover],
    };
  }

  static Map<String, dynamic> _retailLocation() => {
    'id': 'loc-retail-001',
    'businessProfileId': 'retail-001',
    'label': 'Mr. Price - Accra Mall',
    'address': 'Accra Mall, Tetteh Quarshie, Accra',
    'city': 'Accra',
    'region': 'Greater Accra',
    'country': 'Ghana',
    'latitude': 5.6300,
    'longitude': -0.1730,
    'isPrimary': true,
    'isActive': true,
    'galleryUrls': [DemoMedia.rtAlt, DemoMedia.rtCover],
  };

  static Map<String, dynamic> _retail2Location() {
    return {
      'id': 'loc-retail-002',
      'businessProfileId': 'retail-002',
      'label': 'Accra Home Goods - Osu',
      'address': 'Cantonments Road, Osu, Accra',
      'city': 'Accra',
      'region': 'Greater Accra',
      'country': 'Ghana',
      'latitude': 5.5620,
      'longitude': -0.1810,
      'isPrimary': true,
      'isActive': true,
      'galleryUrls': [DemoMedia.rtCover, DemoMedia.rtAlt],
    };
  }

  // ── Hotel Rooms ───────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _hotelRooms(String profileId) {
    final rooms = <Map<String, dynamic>>[];
    for (var f = 1; f <= 4; f++) {
      for (var r = 1; r <= 6; r++) {
        final roomNumber = f * 100 + r;
        String roomType;
        double price;
        if (r <= 2) {
          roomType = 'Deluxe Suite';
          price = 180.00;
        } else if (r <= 4) {
          roomType = 'Standard Room';
          price = 95.00;
        } else {
          roomType = 'Economy Room';
          price = 55.00;
        }
        // Deterministic per-floor media from the verified hotel pool.
        final image = f % 3 == 1
            ? DemoMedia.hCover
            : (f % 3 == 2 ? DemoMedia.hAlt : DemoMedia.hThird);
        rooms.add({
          'id': 'room-$profileId-$roomNumber',
          'businessProfileId': profileId,
          'name': 'Room $roomNumber',
          'slug': 'room-$roomNumber',
          'description': '$roomType on Floor $f',
          'priceUsdc': price,
          'totalRevenue': 0,
          'imageUrls': [image, DemoMedia.hThird],
          'isActive': true,
          'totalOrders': 0,
          'tags': [roomType, 'Floor $f'],
          'category': roomType,
        });
      }
    }
    return rooms;
  }

  // ── Transit Products ──────────────────────────────────────────────────

  static List<Map<String, dynamic>> _transitProducts(String profileId) => [
    {
      'id': 'prod-$profileId-eco',
      'businessProfileId': profileId,
      'name': 'Economy Ticket',
      'slug': 'economy-ticket-$profileId',
      'description': 'Standard seat with AC and USB charging',
      'priceUsdc': 15.00,
      'totalRevenue': 12000,
      'imageUrls': [DemoMedia.tThird],
      'isActive': true,
      'totalOrders': 800,
      'tags': ['Economy'],
    },
    {
      'id': 'prod-$profileId-std',
      'businessProfileId': profileId,
      'name': 'Standard Ticket',
      'slug': 'standard-ticket-$profileId',
      'description': 'Wider seat, priority boarding, refreshments',
      'priceUsdc': 18.00,
      'totalRevenue': 8000,
      'imageUrls': [DemoMedia.tThird],
      'isActive': true,
      'totalOrders': 440,
      'tags': ['Standard'],
    },
    {
      'id': 'prod-$profileId-vip',
      'businessProfileId': profileId,
      'name': 'VIP Ticket',
      'slug': 'vip-ticket-$profileId',
      'description': 'Lie-flat seat, privacy curtain, meal included',
      'priceUsdc': 25.00,
      'totalRevenue': 5000,
      'imageUrls': [DemoMedia.tAlt],
      'isActive': true,
      'totalOrders': 200,
      'tags': ['VIP'],
    },
  ];

  // ── Retail Products ───────────────────────────────────────────────────

  static List<Map<String, dynamic>> _retailProducts(String profileId) => [
    {
      'id': 'prod-tshirt',
      'businessProfileId': 'retail-001',
      'name': 'Cotton Crew Tee',
      'slug': 'cotton-crew-tee',
      'description': 'Soft 100% cotton t-shirt in classic colours',
      'priceUsdc': 8.00,
      'totalRevenue': 2400,
      'imageUrls': [DemoMedia.rtCover],
      'isActive': true,
      'totalOrders': 300,
      'tags': ['Tops', 'Unisex'],
    },
    {
      'id': 'prod-throw-pillow',
      'businessProfileId': 'retail-001',
      'name': 'Bolgatti Woven Basket',
      'slug': 'bolgatti-basket',
      'description': 'Hand-woven market basket from Bolgatanga',
      'priceUsdc': 22.00,
      'totalRevenue': 1800,
      'imageUrls': [DemoMedia.rtThird],
      'isActive': true,
      'totalOrders': 140,
      'tags': ['Homeware'],
    },
    {
      'id': 'prod-ahesi-ceramic',
      'businessProfileId': 'retail-002',
      'name': 'Ahesi Ceramic Bowl Set',
      'slug': 'ahesi-bowl-set',
      'description': 'Four stoneware bowls, glazed in terracotta',
      'priceUsdc': 34.00,
      'totalRevenue': 2100,
      'imageUrls': [DemoMedia.rtAlt],
      'isActive': true,
      'totalOrders': 95,
      'tags': ['Homeware', 'Ceramics'],
    },
    {
      'id': 'prod-adinkra-cloth',
      'businessProfileId': 'retail-002',
      'name': 'Adinkra Table Cloth',
      'slug': 'adinkra-table-cloth',
      'description': 'Hand-stamped cotton table cloth, 180×120cm',
      'priceUsdc': 45.00,
      'totalRevenue': 3200,
      'imageUrls': [DemoMedia.rtCover],
      'isActive': true,
      'totalOrders': 61,
      'tags': ['Homeware', 'Textiles'],
    },
  ].where((p) => p['businessProfileId'] == profileId).toList();

  // ── Invoices ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _unpaidInvoice() => {
    'id': 'inv-restaurant-001',
    'businessProfileId': 'restaurant-001',
    'invoiceRef': 'AZM-INV-2025-104',
    'locationId': 'loc-rest-001',
    'tableId': 'tbl-005',
    'customerId': 1,
    'status': 'SENT',
    'subtotalUsdc': 26.00,
    'taxTotalUsdc': 1.30,
    'tipUsdc': 2.00,
    'billTotalUsdc': 29.30,
    'feeUsdc': 0,
    'customerCoveredFee': false,
    'customerPaidUsdc': 0,
    'sentAt': _hoursAgo(1),
    'paidAt': null,
    'voidedAt': null,
    'createdAt': _hoursAgo(2),
    'lineItems': [
      {
        'id': 'li-1',
        'description': 'Kelewele',
        'quantity': 1,
        'unitPrice': 4.50,
        'lineTotal': 4.50,
      },
      {
        'id': 'li-2',
        'description': 'Jollof Rice',
        'quantity': 1,
        'unitPrice': 12.00,
        'lineTotal': 12.00,
      },
      {
        'id': 'li-3',
        'description': 'Sobolo',
        'quantity': 1,
        'unitPrice': 3.00,
        'lineTotal': 3.00,
      },
      {
        'id': 'li-4',
        'description': 'Banku & Tilapia',
        'quantity': 1,
        'unitPrice': 6.50,
        'lineTotal': 6.50,
      },
    ],
    'taxLines': [
      {
        'id': 'tax-1',
        'name': 'VAT (5%)',
        'type': 'PERCENTAGE',
        'value': 5,
        'computedAmount': 1.30,
      },
    ],
    'businessProfile': {
      'id': 'restaurant-001',
      'businessName': "Chef Abby's",
      'logoUrl': DemoMedia.rLogo,
    },
    'location': {
      'label': "Chef Abby's - Osu",
      'address': 'Oxford Street, Osu, Accra',
    },
    'table': {'label': 'Table 12'},
  };

  static Map<String, dynamic> _paidInvoice() {
    return {
      'id': 'inv-restaurant-002',
      'businessProfileId': 'restaurant-001',
      'invoiceRef': 'AZM-INV-2025-099',
      'locationId': 'loc-rest-001',
      'tableId': 'tbl-005',
      'customerId': 1,
      'status': 'PAID',
      'subtotalUsdc': 31.00,
      'taxTotalUsdc': 1.55,
      'tipUsdc': 3.00,
      'billTotalUsdc': 35.55,
      'feeUsdc': 0,
      'customerCoveredFee': false,
      'customerPaidUsdc': 35.55,
      'sentAt': _daysAgo(3),
      'paidAt': _daysAgo(3),
      'voidedAt': null,
      'createdAt': _daysAgo(4),
      'lineItems': [
        {
          'id': 'li-1',
          'description': 'Banku & Tilapia',
          'quantity': 1,
          'unitPrice': 18.00,
          'lineTotal': 18.00,
        },
        {
          'id': 'li-2',
          'description': 'Red Red',
          'quantity': 1,
          'unitPrice': 10.00,
          'lineTotal': 10.00,
        },
        {
          'id': 'li-3',
          'description': 'Palm Wine',
          'quantity': 1,
          'unitPrice': 3.00,
          'lineTotal': 3.00,
        },
      ],
      'taxLines': [
        {
          'id': 'tax-1',
          'name': 'VAT (5%)',
          'type': 'PERCENTAGE',
          'value': 5,
          'computedAmount': 1.55,
        },
      ],
      'businessProfile': {
        'id': 'restaurant-001',
        'businessName': "Chef Abby's",
        'logoUrl': DemoMedia.rLogo,
      },
      'location': {
        'label': "Chef Abby's - Osu",
        'address': 'Oxford Street, Osu, Accra',
      },
      'table': {'label': 'Table 12'},
    };
  }

  // ── Following list (marketplace story rail) ────────────────────────────

  static List<Map<String, dynamic>> getFollowing() => [
    {
      'id': restaurantBizId,
      'businessName': "Chef Abby's",
      'logoUrl': DemoMedia.rLogo,
      'isVerified': true,
      'lastStoryAt': _hoursAgo(2),
      'lastViewedAt': _hoursAgo(3),
    },
    {
      'id': hotelBizId,
      'businessName': 'The Gallery',
      'logoUrl': DemoMedia.hLogo,
      'isVerified': true,
      'lastStoryAt': _hoursAgo(8),
      'lastViewedAt': _hoursAgo(1),
    },
    {
      'id': 'BIZ-RETAIL-001',
      'businessName': 'Mr. Price',
      'logoUrl': DemoMedia.rtLogo,
      'isVerified': true,
      'lastStoryAt': _hoursAgo(3),
      'lastViewedAt': null,
    },
  ];

  // ── Business Stories ──────────────────────────────────────────────────
  /// Returns the production shape of GET /api/marketplace/business/:id/stories
  /// for a specific business: {success, stories} where each row is a Story
  /// plus its poster user. Each business has 2-3 showcase stories; extra
  /// showcase keys (mediaType, durationSeconds, boosted, seen) are retained
  /// for downstream demo consumers and ignored by BusinessStory.fromJson,
  /// which maps only fields the real rail sends.
  static Map<String, dynamic> getBusinessStories(String bizId) {
    final businesses = {
      restaurantBizId: {
        'name': "Chef Abby's",
        'logo': DemoMedia.rLogo,
        'stories': [
          {
            'id': 'bs-r1',
            'mediaUrl': DemoMedia.rAlt,
            'mediaType': 'IMAGE',
            'caption': 'Fresh jollof straight from the kitchen 🔥',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
          {
            'id': 'bs-r2',
            'mediaUrl': DemoMedia.rThird,
            'mediaType': 'IMAGE',
            'caption': 'Tonight\'s special: grilled tilapia',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
          {
            'id': 'bs-r3',
            'mediaUrl': DemoMedia.rCover,
            'mediaType': 'IMAGE',
            'caption': 'Weekend buffet is back!',
            'durationSeconds': 5,
            'boosted': true,
            'seen': false,
            'createdAt': _hoursAgo(1),
          },
        ],
      },
      restaurant2BizId: {
        'name': "Mama Titi's Kitchen",
        'logo': DemoMedia.rAlt,
        'stories': [
          {
            'id': 'bs-r2-1',
            'mediaUrl': DemoMedia.rThird,
            'mediaType': 'IMAGE',
            'caption': 'Suya night every Friday',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(5),
          },
          {
            'id': 'bs-r2-2',
            'mediaUrl': DemoMedia.rCover,
            'mediaType': 'IMAGE',
            'caption': 'Cold lamugin, hot grill',
            'durationSeconds': 5,
            'boosted': false,
            'seen': true,
            'createdAt': _hoursAgo(4),
          },
        ],
      },
      hotelBizId: {
        'name': 'The Gallery',
        'logo': DemoMedia.hLogo,
        'stories': [
          {
            'id': 'bs-h1',
            'mediaUrl': DemoMedia.hAlt,
            'mediaType': 'IMAGE',
            'caption': 'Rooftop pool now open',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(8),
          },
          {
            'id': 'bs-h2',
            'mediaUrl': DemoMedia.hThird,
            'mediaType': 'IMAGE',
            'caption': 'New deluxe suites available',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(7),
          },
        ],
      },
      hotel2BizId: {
        'name': 'Coastline Suites',
        'logo': DemoMedia.hAlt,
        'stories': [
          {
            'id': 'bs-h2-1',
            'mediaUrl': DemoMedia.hThird,
            'mediaType': 'IMAGE',
            'caption': 'Sunrise from suite 304',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(11),
          },
        ],
      },
      transitBizId: {
        'name': 'Advenr',
        'logo': DemoMedia.tLogo,
        'stories': [
          {
            'id': 'bs-t1',
            'mediaUrl': DemoMedia.tAlt,
            'mediaType': 'IMAGE',
            'caption': 'New fleet just arrived!',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(20),
          },
          {
            'id': 'bs-t2',
            'mediaUrl': DemoMedia.tThird,
            'mediaType': 'IMAGE',
            'caption': 'AC + WiFi + USB on every seat',
            'durationSeconds': 5,
            'boosted': true,
            'seen': true,
            'createdAt': _hoursAgo(19),
          },
        ],
      },
      transit2BizId: {
        'name': 'Volta Lines',
        'logo': DemoMedia.tAlt,
        'stories': [
          {
            'id': 'bs-t2-1',
            'mediaUrl': DemoMedia.tThird,
            'mediaType': 'IMAGE',
            'caption': 'Ho route now runs daily',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(14),
          },
        ],
      },
      'BIZ-RETAIL-001': {
        'name': 'Mr. Price',
        'logo': DemoMedia.rtLogo,
        'stories': [
          {
            'id': 'bs-rt1',
            'mediaUrl': DemoMedia.rtAlt,
            'mediaType': 'IMAGE',
            'caption': 'New season drop is here!',
            'durationSeconds': 5,
            'boosted': true,
            'seen': false,
            'createdAt': _hoursAgo(3),
          },
          {
            'id': 'bs-rt2',
            'mediaUrl': DemoMedia.rtThird,
            'mediaType': 'IMAGE',
            'caption': 'Up to 40% off all items',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
        ],
      },
      'BIZ-RETAIL-002': {
        'name': 'Accra Home Goods',
        'logo': DemoMedia.rtAlt,
        'stories': [
          {
            'id': 'bs-rt2-1',
            'mediaUrl': DemoMedia.rtCover,
            'mediaType': 'IMAGE',
            'caption': 'New ceramic glaze batch',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(6),
          },
        ],
      },
    };

    final biz = businesses[bizId];
    if (biz == null) {
      throw DemoEndpointNotSeededException(
        'GET',
        '/marketplace/business/$bizId/stories',
      );
    }

    return {
      'success': true,
      'stories': (biz['stories'] as List)
          .map<Map<String, dynamic>>(
            (raw) => {
              ...raw as Map<String, dynamic>,
              'userId': 1,
              'businessProfileId': bizId,
              'expiresAt': _hoursFromNow(24),
              'user': {
                'username': biz['name'],
                'profilePictureUrl': biz['logo'],
              },
            },
          )
          .toList(),
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _dish(
    String id,
    String name,
    String description,
    double price,
    List<String> tags,
    String image, [
    String? bizId,
  ]) => {
    'id': id,
    'businessProfileId': bizId ?? 'restaurant-001',
    'name': name,
    'slug': id,
    'description': description,
    'priceUsdc': price,
    'totalRevenue': 0,
    'imageUrls': [image],
    'isActive': true,
    'totalOrders': 0,
    'tags': tags,
  };

  static String _hoursAgo(int h) =>
      DateTime.now().subtract(Duration(hours: h)).toUtc().toIso8601String();
  static String _daysAgo(int d) =>
      DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();
  static String _hoursFromNow(int h) =>
      DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String();
  static String _minutesAgo(int m) =>
      DateTime.now().subtract(Duration(minutes: m)).toUtc().toIso8601String();
}
