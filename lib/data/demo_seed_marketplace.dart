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

// Verified media assets (Base44 public CDN). Reused deterministically —
// one asset pool per category, no random generators.
const String _mp = 'https://media.base44.com/images/public/6a4b8369bec68a34ddf0f3cf/';

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

  /// The canonical Marketplace GET endpoints the app's customer journey
  /// actually calls. Every entry must be explicitly covered by
  /// [DemoInterceptor] — a permanent test walks this list and fails if
  /// any of them is missing or throws.
  static const List<String> requiredGetEndpoints = <String>[
    '/business/search?q=jollof&category=FOOD_BEVERAGE&verified=true&limit=20',
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
    '/stories/business/$restaurantBizId',
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
    final filtered = _filterBusinesses(allBusinesses(),
        q: q, category: category, verified: verified);
    return _pageOf(filtered, limit, cursor, 'businesses');
  }

  /// Deterministic nearby search over the seeded locations.
  static Map<String, dynamic> searchNearby({
    String? q,
    String? category,
    bool? verified,
    int limit = 20,
    String? cursor,
  }) {
    final byProfile = {
      for (final b in allBusinesses()) b['id'].toString(): b,
    };
    final locations = allBusinesses()
        .expand((b) => (b['locations'] as List).cast<Map<String, dynamic>>())
        .where((loc) {
          final biz = byProfile[loc['businessProfileId']];
          if (biz == null) return false;
          if (!_categoryMatches(biz, category)) return false;
          if (verified == true && biz['isVerified'] != true) return false;
          return _queryMatches(biz, q);
        })
        .toList(growable: false);
    return _pageOf(locations, limit, cursor, 'locations',
        hasMoreKey: 'hasMore', cursorKey: 'nextPage');
  }

  static List<Map<String, dynamic>> _filterBusinesses(
    List<Map<String, dynamic>> businesses, {
    String? q,
    String? category,
    bool? verified,
  }) {
    return businesses.where((b) {
      if (!_categoryMatches(b, category)) return false;
      if (verified == true && b['isVerified'] != true) return false;
      return _queryMatches(b, q);
    }).toList(growable: false);
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
          {'id': 'sec-starters', 'name': 'Starters', 'description': 'Small plates to share', 'products': [
            _dish('dish-kelewele', 'Kelewele', 'Spicy fried plantain cubes with ginger and pepper', 4.50, ['spicy','veg'], DemoMedia.rThird, restaurantBizId),
            _dish('dish-jollof', 'Jollof Rice', 'Smoky one-pot rice in tomato-pepper sauce', 12.00, ['veg'], DemoMedia.rCover, restaurantBizId),
            _dish('dish-suya', 'Beef Suya', 'Grilled spiced beef skewers with yaji rub', 8.50, ['spicy'], DemoMedia.rAlt, restaurantBizId),
            _dish('dish-salad', 'Avocado Salad', 'Fresh avocado, tomato, red onion, lime dressing', 6.00, ['veg'], DemoMedia.rThird, restaurantBizId),
          ]},
          {'id': 'sec-mains', 'name': 'Main Courses', 'description': 'Hearty Ghanaian classics', 'products': [
            _dish('dish-waakye', 'Waakye & Stew', 'Rice & beans with spaghetti, egg, shito, and fried plantain', 14.50, [], DemoMedia.rCover, restaurantBizId),
            _dish('dish-banku', 'Banku & Tilapia', 'Grilled tilapia with fermented corn dough', 18.00, [], DemoMedia.rAlt, restaurantBizId),
            _dish('dish-fufu', 'Fufu & Light Soup', 'Pounded cassava with goat light soup', 16.00, ['spicy'], DemoMedia.rThird, restaurantBizId),
            _dish('dish-redred', 'Red Red', 'Bean stew with fried plantain', 10.00, ['veg'], DemoMedia.rCover, restaurantBizId),
            _dish('dish-omotuo', 'Omo Tuo & Groundnut Soup', 'Rice balls in rich peanut soup with chicken', 15.00, [], DemoMedia.rAlt, restaurantBizId),
          ]},
          {'id': 'sec-drinks', 'name': 'Beverages', 'description': 'Fresh & chilled', 'products': [
            _dish('drink-sobo', 'Sobolo', 'Hibiscus iced tea with ginger', 3.00, ['veg'], DemoMedia.rThird, restaurantBizId),
            _dish('drink-palm', 'Palm Wine', 'Freshly tapped from the Eastern Region', 4.00, [], DemoMedia.rCover, restaurantBizId),
            _dish('drink-asana', 'Asana', 'Corn drink with fermented milk', 3.50, ['veg'], DemoMedia.rAlt, restaurantBizId),
          ]},
          {'id': 'sec-desserts', 'name': 'Desserts', 'description': 'Sweet endings', 'products': [
            _dish('dessert-kele', 'Kelewele Sundae', 'Vanilla ice cream with caramelised plantain', 7.00, ['veg'], DemoMedia.rThird, restaurantBizId),
            _dish('dessert-bofrot', 'Bofrot Trio', 'Three puff puffs with chocolate dip', 5.00, ['veg'], DemoMedia.rCover, restaurantBizId),
          ]},
        ],
        'uncategorisedProducts': [],
      };
    }
    if (bizId == restaurant2BizId) {
      return {
        'sections': [
          {'id': 'sec-2-light', 'name': 'Light Bites', 'description': 'Street-food favourites', 'products': [
            _dish('dish2-kelewele', 'Kelewele Bowl', 'Double-spice plantain with groundnuts', 5.00, ['spicy','veg'], DemoMedia.rCover, restaurant2BizId),
            _dish('dish2-koshari', 'Koshari', 'Rice, lentils and pasta in tomato sauce', 9.00, ['veg'], DemoMedia.rAlt, restaurant2BizId),
          ]},
          {'id': 'sec-2-grill', 'name': 'From the Grill', 'description': 'Charcoal-grilled to order', 'products': [
            _dish('dish2-suya', 'Chicken Suya', 'Yaji-rubbed grilled chicken thighs', 11.00, ['spicy'], DemoMedia.rThird, restaurant2BizId),
            _dish('dish2-tilapia', 'Whole Tilapia', 'Stuffed with shito and served with banku', 22.00, [], DemoMedia.rCover, restaurant2BizId),
          ]},
          {'id': 'sec-2-drinks', 'name': 'Beverages', 'description': 'Cold and fresh', 'products': [
            _dish('drink2-lamugin', 'Lamugin', 'Spiced ginger juice over ice', 3.50, ['veg'], DemoMedia.rAlt, restaurant2BizId),
          ]},
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
    'hasMore': false, 'nextCursor': null,
  };

  static Map<String, dynamic> getInvoice(String invoiceId) =>
    {'invoice': invoiceId == 'inv-restaurant-001' ? _unpaidInvoice() : _paidInvoice()};

  static Map<String, dynamic> getMyOrders() => {
    'orders': [
      {'id': 'ord-001', 'businessProfileId': 'restaurant-001', 'orderRef': 'AZM-ORD-101',
       'title': "Chef Abby's takeaway", 'customerId': 1, 'productId': 'dish-jollof',
       'status': 'COMPLETED', 'amountUsdc': 12.00, 'description': 'Jollof Rice × 1',
       'createdAt': _daysAgo(2)},
      {'id': 'ord-002', 'businessProfileId': 'retail-001', 'orderRef': 'AZM-ORD-102',
       'title': 'Mr. Price cotton tee', 'customerId': 1, 'productId': 'prod-tshirt',
       'status': 'IN_ESCROW', 'amountUsdc': 8.00, 'description': 'Cotton Crew Tee × 1',
       'createdAt': _hoursAgo(6)},
    ],
    'hasMore': false, 'nextCursor': null,
  };

  /// Demo user owns no business — the truthful stats are zeros.
  static Map<String, dynamic> getOwnerStats() => {
    'stats': {
      'totalOrders': 0, 'completedOrders': 0, 'pendingOrders': 0,
      'disputedOrders': 0, 'cancelledOrders': 0, 'totalRevenue': 0.0,
      'avgOrderValue': 0.0, 'recentOrders': [],
    },
  };

  /// Demo user owns no business — an empty notification feed is the
  /// truthful, explicit decision here (not a fake fallback).
  static Map<String, dynamic> getOwnerNotifications() => {
    'notifications': [], 'hasMore': false, 'nextCursor': null, 'unreadCount': 0,
  };

  /// Demo user owns no business — KYB is unstarted.
  static Map<String, dynamic> getKybStatus() =>
    {'kybStatus': 'UNVERIFIED', 'documents': []};

  /// Owner-scoped global product list — demo user owns none.
  static Map<String, dynamic> getMyProducts() =>
    {'products': [], 'hasMore': false, 'nextCursor': null};

  /// Public single-product lookup across the seeded catalogue.
  static Map<String, dynamic> getProductById(String productId) {
    final catalogue = [
      ..._transitProducts('transit-001'),
      ..._retailProducts('retail-001'),
      ..._retailProducts('retail-002'),
    ];
    final match = catalogue
        .where((p) => p['id'] == productId)
        .toList(growable: false);
    if (match.isEmpty) {
      throw DemoEndpointNotSeededException('GET', '/business/products/$productId');
    }
    return {'product': match.first};
  }

  // ── Transit ──────────────────────────────────────────────────────────

  static Map<String, dynamic> getTransitTrips() {
    return {
      'success': true,
      'trips': [
        {'id': 'trip-001', 'businessProfileId': 'transit-001', 'vehicleId': 'veh-001',
         'routeName': 'Accra to Kumasi Express', 'origin': 'Accra', 'destination': 'Kumasi',
         'departureAt': _hoursFromNow(3), 'arrivalAt': _hoursFromNow(6),
         'fareUsdc': 15.00, 'availableSeats': 22, 'status': 'SCHEDULED',
         'vehicle': {'type': 'COACH', 'make': 'Mercedes-Benz', 'model': 'Sprinter 450',
           'imageUrl': DemoMedia.tCover,
           'driverName': 'Kwabena Owusu', 'driverPhotoUrl': DemoMedia.tLogo,
           'plateNumber': 'GT 4521-24',
           'coDriverName': 'Akosua Mensah', 'coDriverPhotoUrl': DemoMedia.tAlt},
         '_count': {'bookings': 12}},
        {'id': 'trip-002', 'businessProfileId': 'transit-001', 'vehicleId': 'veh-002',
         'routeName': 'Accra to Cape Coast Run', 'origin': 'Accra', 'destination': 'Cape Coast',
         'departureAt': _hoursFromNow(5), 'arrivalAt': _hoursFromNow(7),
         'fareUsdc': 10.00, 'availableSeats': 28, 'status': 'SCHEDULED',
         'vehicle': {'type': 'MINIVAN', 'make': 'Toyota', 'model': 'HiAce',
           'imageUrl': DemoMedia.tAlt,
           'driverName': 'Yaw Mensah', 'driverPhotoUrl': DemoMedia.tLogo,
           'plateNumber': 'GR 8892-25'},
         '_count': {'bookings': 6}},
        {'id': 'trip-003', 'businessProfileId': 'transit-002', 'vehicleId': 'veh-101',
         'routeName': 'Accra to Ho Scenic', 'origin': 'Accra', 'destination': 'Ho',
         'departureAt': _hoursFromNow(4), 'arrivalAt': _hoursFromNow(7),
         'fareUsdc': 12.00, 'availableSeats': 16, 'status': 'SCHEDULED',
         'vehicle': {'type': 'MINIBUS', 'make': 'Nissan', 'model': 'Urvan',
           'imageUrl': DemoMedia.tThird,
           'driverName': 'Kofi Boateng', 'driverPhotoUrl': DemoMedia.tLogo,
           'plateNumber': 'GR 3320-24'},
         '_count': {'bookings': 9}},
        {'id': 'trip-004', 'businessProfileId': 'transit-002', 'vehicleId': 'veh-102',
         'routeName': 'Kumasi to Tamale Overnight', 'origin': 'Kumasi', 'destination': 'Tamale',
         'departureAt': _hoursFromNow(9), 'arrivalAt': _hoursFromNow(17),
         'fareUsdc': 20.00, 'availableSeats': 24, 'status': 'SCHEDULED',
         'vehicle': {'type': 'COACH', 'make': 'Yutong', 'model': 'ZK6122',
           'imageUrl': DemoMedia.tCover,
           'driverName': 'Fuseini Iddrisu', 'driverPhotoUrl': DemoMedia.tAlt,
           'plateNumber': 'AS 1109-23'},
         '_count': {'bookings': 15}},
      ],
    };
  }

  static Map<String, dynamic> getTripSeats(String tripId) {
    final seats = <Map<String, dynamic>>[];
    final occupied = {'1A','2B','3D','5A','7C','10B','10D'};
    for (var row = 1; row <= 10; row++) {
      for (var col = 0; col < 4; col++) {
        final seatLetter = String.fromCharCode(65 + col);
        final seatId = '$row$seatLetter';
        final isWindow = col == 0 || col == 3;
        var tier = 'ECONOMY'; var fare = 15.0;
        if (row <= 2) { tier = 'VIP'; fare = 25.0; }
        else if (row <= 5) { tier = 'STANDARD'; fare = 18.0; }
        seats.add({'seatId': seatId, 'row': row, 'col': col + 1,
          'type': isWindow ? 'WINDOW' : 'AISLE',
          'status': occupied.contains(seatId) ? 'OCCUPIED' : 'AVAILABLE',
          'tier': tier, 'fare': fare});
      }
    }
    return {'success': true, 'tripId': tripId, 'seats': seats,
      'availableCount': seats.where((s) => s['status'] == 'AVAILABLE').length,
      'totalSeats': seats.length, 'tripStatus': 'SCHEDULED', 'fareUsdc': 15.0,
      'tierFares': {'VIP': 25.0, 'STANDARD': 18.0, 'ECONOMY': 15.0}};
  }

  static Map<String, dynamic> getTrustScore(String azamanId) {
    return {
      'trustLevel': 'GOOD', 'noShowRate': 0.02,
      'totalBookings': 14, 'noShowCount': 0, 'completedBookings': 14,
    };
  }

  /// Legacy dine-in tab path (marketplace_booking_service). Coherent OPEN
  /// tab on the seeded restaurant so the endpoint is explicitly covered.
  static Map<String, dynamic> getDineInTab(String tabId) {
    return {'data': {
      'id': tabId,
      'status': 'OPEN',
      'openedAt': _hoursAgo(1),
      'subtotalUsdc': 15.00, 'taxTotalUsdc': 0.75, 'tipUsdc': 0.0,
      'grandTotalUsdc': 15.75,
      'businessProfile': {'id': 'restaurant-001', 'bizId': restaurantBizId,
        'businessName': "Chef Abby's", 'logoUrl': DemoMedia.rLogo},
      'table': {'id': 'tbl-005', 'label': 'Table 12', 'locationId': 'loc-rest-001'},
      'items': [
        {'id': 'di-1', 'name': 'Jollof Rice', 'unitPrice': 12.00, 'quantity': 1,
         'lineTotal': 12.00, 'addedAt': _hoursAgo(1)},
        {'id': 'di-2', 'name': 'Sobolo', 'unitPrice': 3.00, 'quantity': 1,
         'lineTotal': 3.00, 'addedAt': _minutesAgo(50)},
      ]},
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
        {'id': 'rev-$bizId-1', 'businessProfileId': profileId, 'reviewerId': 11,
         'rating': 5, 'comment': 'Great experience — fast service and exactly as described.',
         'sourceType': 'ORDER', 'createdAt': _daysAgo(5),
         'reviewer': {'id': 11, 'username': 'ama_k'},
         'reviewerUsername': 'ama_k'},
        {'id': 'rev-$bizId-2', 'businessProfileId': profileId, 'reviewerId': 12,
         'rating': 4, 'comment': 'Good value. Will come back.',
         'sourceType': 'ORDER', 'createdAt': _daysAgo(12),
         'reviewer': {'id': 12, 'username': 'yaw_o'},
         'reviewerUsername': 'yaw_o'},
      ],
      'hasMore': false, 'nextCursor': null,
    };
  }

  // ── Products / rooms ─────────────────────────────────────────────────

  static Map<String, dynamic> getProducts(String bizId) {
    if (bizId == hotelBizId || bizId == 'hotel-001') return {'products': _hotelRooms('hotel-001')};
    if (bizId == hotel2BizId || bizId == 'hotel-002') return {'products': _hotelRooms('hotel-002')};
    if (bizId == transitBizId || bizId == 'transit-001') return {'products': _transitProducts('transit-001')};
    if (bizId == transit2BizId || bizId == 'transit-002') return {'products': _transitProducts('transit-002')};
    if (bizId == retailBizId || bizId == 'retail-001') return {'products': _retailProducts('retail-001')};
    if (bizId == retail2BizId || bizId == 'retail-002') return {'products': _retailProducts('retail-002')};
    if (bizId == restaurantBizId) {
      return {'products': [
      _dish('dish-waakye', 'Waakye & Stew', 'Rice & beans with spaghetti, egg, shito', 14.50, [], DemoMedia.rCover, restaurantBizId),
      _dish('dish-jollof', 'Jollof Rice', 'Smoky one-pot rice', 12.00, ['veg'], DemoMedia.rAlt, restaurantBizId),
      ]};
    }
    if (bizId == restaurant2BizId) {
      return {'products': [
      _dish('dish2-suya', 'Chicken Suya', 'Yaji-rubbed grilled chicken thighs', 11.00, ['spicy'], DemoMedia.rThird, restaurant2BizId),
      _dish('dish2-koshari', 'Koshari', 'Rice, lentils and pasta in tomato sauce', 9.00, ['veg'], DemoMedia.rCover, restaurant2BizId),
      ]};
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
        (match.first['locations'] as List).whereType<Map<String, dynamic>>()),
    };
  }

  static Map<String, dynamic> getShowcase(String bizId) {
    final byBizId = {
      restaurantBizId: [DemoMedia.rCover, DemoMedia.rAlt, DemoMedia.rThird],
      restaurant2BizId: [DemoMedia.rAlt, DemoMedia.rCover],
      hotelBizId: [DemoMedia.hCover, DemoMedia.hAlt, DemoMedia.hThird, DemoMedia.hAlt, DemoMedia.hCover],
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
    'id': 'restaurant-001', 'bizId': restaurantBizId, 'businessName': "Chef Abby's",
    'category': 'FOOD_BEVERAGE', 'description': 'Authentic Ghanaian cuisine in the heart of Accra. From jollof to waakye, every plate tells a story.',
    'website': 'https://chefabbys.gh', 'logoUrl': DemoMedia.rLogo,
    'coverImageUrl': DemoMedia.rCover,
    'phoneNumber': '+233 24 123 4567', 'address': 'Oxford Street, Osu, Accra', 'country': 'Ghana',
    'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
    'totalEscrows': 340, 'completedEscrows': 335, 'userId': 201,
    'totalVolume': 125000.00, 'averageRating': 4.7, 'reviewCount': 234,
    'subcategory': 'Restaurant', 'priceRange': 2,
    'amenities': ['WiFi','Dine-in','Takeaway','Delivery','Parking'],
    'cuisineTypes': ['Ghanaian','African','Continental'],
    'adAccentColor': '#FF6B35',
    'user': {'id': 201, 'username': 'chef_abbys', 'profilePictureUrl': null},
    'products': [], 'locations': [_restaurantLocation()],
  };

  static Map<String, dynamic> _restaurant2Business() {
    return {'id': 'restaurant-002', 'bizId': restaurant2BizId, 'businessName': "Mama Titi's Kitchen",
      'category': 'FOOD_BEVERAGE', 'description': 'Spintex road grill house. Charcoal suya, fresh tilapia and cold lamugin until late.',
      'website': 'https://mamatitis.gh', 'logoUrl': DemoMedia.rAlt,
      'coverImageUrl': DemoMedia.rThird,
      'phoneNumber': '+233 27 445 8890', 'address': 'Spintex Road, Accra', 'country': 'Ghana',
      'isVerified': false, 'isSuspended': false, 'kybStatus': 'PENDING',
      'totalEscrows': 46, 'completedEscrows': 44, 'userId': 211,
      'totalVolume': 9200.00, 'averageRating': 4.3, 'reviewCount': 61,
      'subcategory': 'Grill House', 'priceRange': 1,
      'amenities': ['Takeaway','Outdoor Seating','Late Night'],
      'cuisineTypes': ['Ghanaian','Barbecue'],
      'adAccentColor': '#F59E0B',
      'user': {'id': 211, 'username': 'mama_titi', 'profilePictureUrl': null},
      'products': [], 'locations': [_restaurant2Location()],
    };
  }

  static Map<String, dynamic> _hotelBusiness() {
    return {'id': 'hotel-001', 'bizId': hotelBizId, 'businessName': 'The Gallery',
      'category': 'HOSPITALITY', 'description': 'Boutique apartments in East Legon. Fully furnished studios and 1-bedroom suites with 24/7 concierge.',
      'website': 'https://thegallery.gh', 'logoUrl': DemoMedia.hLogo,
      'coverImageUrl': DemoMedia.hCover,
      'phoneNumber': '+233 26 987 6543', 'address': 'East Legon, Greater Accra', 'country': 'Ghana',
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 180, 'completedEscrows': 175, 'userId': 202,
      'totalVolume': 85000.00, 'averageRating': 4.8, 'reviewCount': 156,
      'subcategory': 'Apartments', 'priceRange': 3,
      'amenities': ['Pool','Gym','Spa','WiFi','Restaurant','Bar','Parking','Concierge'],
      'cuisineTypes': [], 'adAccentColor': '#1A8FE3',
      'user': {'id': 202, 'username': 'the_gallery', 'profilePictureUrl': null},
      'products': _hotelRooms('hotel-001'), 'locations': [_hotelLocation()],
      'businessMeta': {'showcaseUrls': [DemoMedia.hCover, DemoMedia.hAlt, DemoMedia.hThird, DemoMedia.hAlt, DemoMedia.hCover]},
    };
  }

  static Map<String, dynamic> _hotel2Business() {
    return {'id': 'hotel-002', 'bizId': hotel2BizId, 'businessName': 'Coastline Suites',
      'category': 'HOSPITALITY', 'description': 'Sea-view suites on Cape Coast beach road. Sunrise balconies, breakfast included, weekly rates for remote workers.',
      'website': 'https://coastlinesuites.gh', 'logoUrl': DemoMedia.hAlt,
      'coverImageUrl': DemoMedia.hThird,
      'phoneNumber': '+233 31 202 3311', 'address': 'Beach Road, Cape Coast', 'country': 'Ghana',
      'isVerified': false, 'isSuspended': false, 'kybStatus': 'PENDING',
      'totalEscrows': 58, 'completedEscrows': 56, 'userId': 212,
      'totalVolume': 21800.00, 'averageRating': 4.6, 'reviewCount': 72,
      'subcategory': 'Beach Hotel', 'priceRange': 2,
      'amenities': ['Sea View','Breakfast','WiFi','Airport Shuttle'],
      'cuisineTypes': [], 'adAccentColor': '#A78BFA',
      'user': {'id': 212, 'username': 'coastline_suites', 'profilePictureUrl': null},
      'products': _hotelRooms('hotel-002'), 'locations': [_hotel2Location()],
      'businessMeta': {'showcaseUrls': [DemoMedia.hThird, DemoMedia.hCover, DemoMedia.hAlt]},
    };
  }

  static Map<String, dynamic> _transitBusiness() {
    return {'id': 'transit-001', 'bizId': transitBizId, 'businessName': 'Advenr',
      'category': 'LOGISTICS', 'description': 'Premium intercity travel. Modern fleet, professional drivers, on-time departures, comfortable seats.',
      'website': 'https://advenr.gh', 'logoUrl': DemoMedia.tLogo,
      'coverImageUrl': DemoMedia.tCover,
      'phoneNumber': '+233 20 555 0199', 'address': 'Circle Station, Accra', 'country': 'Ghana',
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 520, 'completedEscrows': 515, 'userId': 203,
      'totalVolume': 78000.00, 'averageRating': 4.5, 'reviewCount': 410,
      'subcategory': 'Intercity Bus', 'priceRange': 1,
      'amenities': ['AC','WiFi','USB Charging','Refreshments'],
      'cuisineTypes': [], 'adAccentColor': '#10B981',
      'user': {'id': 203, 'username': 'advenr', 'profilePictureUrl': null},
      'products': _transitProducts('transit-001'), 'locations': [_transitLocation()],
    };
  }

  static Map<String, dynamic> _transit2Business() {
    return {'id': 'transit-002', 'bizId': transit2BizId, 'businessName': 'Volta Lines',
      'category': 'LOGISTICS', 'description': 'Scenic and overnight routes through the Volta corridor. Comfortable reclining seats, live trip tracking.',
      'website': 'https://voltalines.gh', 'logoUrl': DemoMedia.tAlt,
      'coverImageUrl': DemoMedia.tThird,
      'phoneNumber': '+233 36 210 4477', 'address': 'Ho Main Station, Ho', 'country': 'Ghana',
      'isVerified': false, 'isSuspended': false, 'kybStatus': 'PENDING',
      'totalEscrows': 210, 'completedEscrows': 205, 'userId': 213,
      'totalVolume': 34000.00, 'averageRating': 4.2, 'reviewCount': 188,
      'subcategory': 'Regional Coach', 'priceRange': 1,
      'amenities': ['AC','USB Charging','Live Tracking','Blanket'],
      'cuisineTypes': [], 'adAccentColor': '#4F8EF7',
      'user': {'id': 213, 'username': 'volta_lines', 'profilePictureUrl': null},
      'products': _transitProducts('transit-002'), 'locations': [_transit2Location()],
    };
  }

  static Map<String, dynamic> _retailBusiness() {
    return {'id': 'retail-001', 'bizId': retailBizId, 'businessName': 'Mr. Price',
      'category': 'RETAIL', 'description': 'Fashion, homeware & lifestyle at everyday prices',
      'logoUrl': DemoMedia.rtLogo, 'coverImageUrl': DemoMedia.rtCover,
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 320, 'completedEscrows': 315, 'userId': 205,
      'totalVolume': 45000.00, 'averageRating': 4.4, 'reviewCount': 210,
      'subcategory': 'Fashion Retail', 'priceRange': 1,
      'amenities': ['Changing Rooms','Click & Collect','Returns'],
      'cuisineTypes': [], 'adAccentColor': '#00D97E',
      'user': {'id': 205, 'username': 'mr_price', 'profilePictureUrl': null},
      'products': _retailProducts('retail-001'), 'locations': [_retailLocation()],
    };
  }

  static Map<String, dynamic> _retail2Business() {
    return {'id': 'retail-002', 'bizId': retail2BizId, 'businessName': 'Accra Home Goods',
      'category': 'RETAIL', 'description': 'Locally made homeware — woven baskets, ceramics and ashanti cloth for your space.',
      'logoUrl': DemoMedia.rtAlt, 'coverImageUrl': DemoMedia.rtThird,
      'isVerified': false, 'isSuspended': false, 'kybStatus': 'PENDING',
      'totalEscrows': 74, 'completedEscrows': 71, 'userId': 214,
      'totalVolume': 11200.00, 'averageRating': 4.1, 'reviewCount': 39,
      'subcategory': 'Homeware', 'priceRange': 2,
      'amenities': ['Click & Collect','Delivery'],
      'cuisineTypes': [], 'adAccentColor': '#00D97E',
      'user': {'id': 214, 'username': 'accra_home', 'profilePictureUrl': null},
      'products': _retailProducts('retail-002'), 'locations': [_retail2Location()],
    };
  }

  // ── Locations ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _restaurantLocation() => {
    'id': 'loc-rest-001', 'businessProfileId': 'restaurant-001',
    'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.5550, 'longitude': -0.1800,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': [DemoMedia.rCover, DemoMedia.rAlt, DemoMedia.rCover],
    'distanceKm': 1.2,
  };

  static Map<String, dynamic> _restaurant2Location() {
    return {'id': 'loc-rest-002', 'businessProfileId': 'restaurant-002',
      'label': "Mama Titi's - Spintex", 'address': 'Spintex Road, Accra',
      'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
      'latitude': 5.6220, 'longitude': -0.1180,
      'isPrimary': true, 'isActive': true,
      'galleryUrls': [DemoMedia.rThird, DemoMedia.rCover],
      'distanceKm': 4.6,
    };
  }

  static Map<String, dynamic> _hotelLocation() => {
    'id': 'loc-hotel-001', 'businessProfileId': 'hotel-001',
    'label': 'The Gallery - East Legon', 'address': 'East Legon, Greater Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.6400, 'longitude': -0.1680,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': [DemoMedia.hCover, DemoMedia.hAlt, DemoMedia.hThird, DemoMedia.hAlt, DemoMedia.hCover],
    'distanceKm': 3.8,
  };

  static Map<String, dynamic> _hotel2Location() {
    return {'id': 'loc-hotel-002', 'businessProfileId': 'hotel-002',
      'label': 'Coastline Suites - Cape Coast', 'address': 'Beach Road, Cape Coast',
      'city': 'Cape Coast', 'region': 'Central', 'country': 'Ghana',
      'latitude': 5.1050, 'longitude': -1.2460,
      'isPrimary': true, 'isActive': true,
      'galleryUrls': [DemoMedia.hThird, DemoMedia.hCover, DemoMedia.hAlt],
      'distanceKm': 9.4,
    };
  }

  static Map<String, dynamic> _transitLocation() => {
    'id': 'loc-transit-001', 'businessProfileId': 'transit-001',
    'label': 'Advenr - Circle Station', 'address': 'Circle Station, Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.5700, 'longitude': -0.2050,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': [DemoMedia.tCover, DemoMedia.tAlt],
    'distanceKm': 2.5,
  };

  static Map<String, dynamic> _transit2Location() {
    return {'id': 'loc-transit-002', 'businessProfileId': 'transit-002',
      'label': 'Volta Lines - Ho Main Station', 'address': 'Ho Main Station, Ho',
      'city': 'Ho', 'region': 'Volta', 'country': 'Ghana',
      'latitude': 6.6060, 'longitude': 0.4710,
      'isPrimary': true, 'isActive': true,
      'galleryUrls': [DemoMedia.tThird, DemoMedia.tCover],
      'distanceKm': 6.1,
    };
  }

  static Map<String, dynamic> _retailLocation() => {
    'id': 'loc-retail-001', 'businessProfileId': 'retail-001',
    'label': 'Mr. Price - Accra Mall', 'address': 'Accra Mall, Tetteh Quarshie, Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.6300, 'longitude': -0.1730,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': [DemoMedia.rtAlt, DemoMedia.rtCover],
    'distanceKm': 3.1,
  };

  static Map<String, dynamic> _retail2Location() {
    return {'id': 'loc-retail-002', 'businessProfileId': 'retail-002',
      'label': 'Accra Home Goods - Osu', 'address': 'Cantonments Road, Osu, Accra',
      'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
      'latitude': 5.5620, 'longitude': -0.1810,
      'isPrimary': true, 'isActive': true,
      'galleryUrls': [DemoMedia.rtCover, DemoMedia.rtAlt],
      'distanceKm': 1.9,
    };
  }

  // ── Hotel Rooms ───────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _hotelRooms(String profileId) {
    final rooms = <Map<String, dynamic>>[];
    for (var f = 1; f <= 4; f++) {
      for (var r = 1; r <= 6; r++) {
        final roomNumber = f * 100 + r;
        String roomType; double price;
        if (r <= 2) { roomType = 'Deluxe Suite'; price = 180.00; }
        else if (r <= 4) { roomType = 'Standard Room'; price = 95.00; }
        else { roomType = 'Economy Room'; price = 55.00; }
        // Deterministic per-floor media from the verified hotel pool.
        final image = f % 3 == 1
            ? DemoMedia.hCover
            : (f % 3 == 2 ? DemoMedia.hAlt : DemoMedia.hThird);
        rooms.add({'id': 'room-$profileId-$roomNumber', 'businessProfileId': profileId,
          'name': 'Room $roomNumber', 'slug': 'room-$roomNumber',
          'description': '$roomType on Floor $f', 'priceUsdc': price, 'totalRevenue': 0,
          'imageUrls': [image, DemoMedia.hThird],
          'isActive': true, 'totalOrders': 0,
          'tags': [roomType, 'Floor $f'], 'category': roomType});
      }
    }
    return rooms;
  }

  // ── Transit Products ──────────────────────────────────────────────────

  static List<Map<String, dynamic>> _transitProducts(String profileId) => [
    {'id': 'prod-$profileId-eco', 'businessProfileId': profileId, 'name': 'Economy Ticket', 'slug': 'economy-ticket-$profileId', 'description': 'Standard seat with AC and USB charging', 'priceUsdc': 15.00, 'totalRevenue': 12000, 'imageUrls': [DemoMedia.tThird], 'isActive': true, 'totalOrders': 800, 'tags': ['Economy']},
    {'id': 'prod-$profileId-std', 'businessProfileId': profileId, 'name': 'Standard Ticket', 'slug': 'standard-ticket-$profileId', 'description': 'Wider seat, priority boarding, refreshments', 'priceUsdc': 18.00, 'totalRevenue': 8000, 'imageUrls': [DemoMedia.tThird], 'isActive': true, 'totalOrders': 440, 'tags': ['Standard']},
    {'id': 'prod-$profileId-vip', 'businessProfileId': profileId, 'name': 'VIP Ticket', 'slug': 'vip-ticket-$profileId', 'description': 'Lie-flat seat, privacy curtain, meal included', 'priceUsdc': 25.00, 'totalRevenue': 5000, 'imageUrls': [DemoMedia.tAlt], 'isActive': true, 'totalOrders': 200, 'tags': ['VIP']},
  ];

  // ── Retail Products ───────────────────────────────────────────────────

  static List<Map<String, dynamic>> _retailProducts(String profileId) => [
    {'id': 'prod-tshirt', 'businessProfileId': 'retail-001', 'name': 'Cotton Crew Tee', 'slug': 'cotton-crew-tee', 'description': 'Soft 100% cotton t-shirt in classic colours', 'priceUsdc': 8.00, 'totalRevenue': 2400, 'imageUrls': [DemoMedia.rtCover], 'isActive': true, 'totalOrders': 300, 'tags': ['Tops', 'Unisex']},
    {'id': 'prod-throw-pillow', 'businessProfileId': 'retail-001', 'name': 'Bolgatti Woven Basket', 'slug': 'bolgatti-basket', 'description': 'Hand-woven market basket from Bolgatanga', 'priceUsdc': 22.00, 'totalRevenue': 1800, 'imageUrls': [DemoMedia.rtThird], 'isActive': true, 'totalOrders': 140, 'tags': ['Homeware']},
    {'id': 'prod-ahesi-ceramic', 'businessProfileId': 'retail-002', 'name': 'Ahesi Ceramic Bowl Set', 'slug': 'ahesi-bowl-set', 'description': 'Four stoneware bowls, glazed in terracotta', 'priceUsdc': 34.00, 'totalRevenue': 2100, 'imageUrls': [DemoMedia.rtAlt], 'isActive': true, 'totalOrders': 95, 'tags': ['Homeware', 'Ceramics']},
    {'id': 'prod-adinkra-cloth', 'businessProfileId': 'retail-002', 'name': 'Adinkra Table Cloth', 'slug': 'adinkra-table-cloth', 'description': 'Hand-stamped cotton table cloth, 180×120cm', 'priceUsdc': 45.00, 'totalRevenue': 3200, 'imageUrls': [DemoMedia.rtCover], 'isActive': true, 'totalOrders': 61, 'tags': ['Homeware', 'Textiles']},
  ].where((p) => p['businessProfileId'] == profileId).toList();

  // ── Invoices ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _unpaidInvoice() => {
    'id': 'inv-restaurant-001', 'businessProfileId': 'restaurant-001',
    'invoiceRef': 'AZM-INV-2025-104', 'locationId': 'loc-rest-001', 'tableId': 'tbl-005',
    'customerId': 1, 'status': 'SENT',
    'subtotalUsdc': 26.00, 'taxTotalUsdc': 1.30, 'tipUsdc': 2.00, 'billTotalUsdc': 29.30,
    'feeUsdc': 0, 'customerCoveredFee': false, 'customerPaidUsdc': 0,
    'sentAt': _hoursAgo(1), 'paidAt': null, 'voidedAt': null, 'createdAt': _hoursAgo(2),
    'lineItems': [
      {'id': 'li-1', 'description': 'Kelewele', 'quantity': 1, 'unitPrice': 4.50, 'lineTotal': 4.50},
      {'id': 'li-2', 'description': 'Jollof Rice', 'quantity': 1, 'unitPrice': 12.00, 'lineTotal': 12.00},
      {'id': 'li-3', 'description': 'Sobolo', 'quantity': 1, 'unitPrice': 3.00, 'lineTotal': 3.00},
      {'id': 'li-4', 'description': 'Banku & Tilapia', 'quantity': 1, 'unitPrice': 6.50, 'lineTotal': 6.50},
    ],
    'taxLines': [{'id': 'tax-1', 'name': 'VAT (5%)', 'type': 'PERCENTAGE', 'value': 5, 'computedAmount': 1.30}],
    'businessProfile': {'id': 'restaurant-001', 'businessName': "Chef Abby's", 'logoUrl': DemoMedia.rLogo},
    'location': {'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra'},
    'table': {'label': 'Table 12'},
  };

  static Map<String, dynamic> _paidInvoice() {
    return {
    'id': 'inv-restaurant-002', 'businessProfileId': 'restaurant-001',
    'invoiceRef': 'AZM-INV-2025-099', 'locationId': 'loc-rest-001', 'tableId': 'tbl-005',
    'customerId': 1, 'status': 'PAID',
    'subtotalUsdc': 31.00, 'taxTotalUsdc': 1.55, 'tipUsdc': 3.00, 'billTotalUsdc': 35.55,
    'feeUsdc': 0, 'customerCoveredFee': false, 'customerPaidUsdc': 35.55,
    'sentAt': _daysAgo(3), 'paidAt': _daysAgo(3), 'voidedAt': null, 'createdAt': _daysAgo(4),
    'lineItems': [
      {'id': 'li-1', 'description': 'Banku & Tilapia', 'quantity': 1, 'unitPrice': 18.00, 'lineTotal': 18.00},
      {'id': 'li-2', 'description': 'Red Red', 'quantity': 1, 'unitPrice': 10.00, 'lineTotal': 10.00},
      {'id': 'li-3', 'description': 'Palm Wine', 'quantity': 1, 'unitPrice': 3.00, 'lineTotal': 3.00},
    ],
    'taxLines': [{'id': 'tax-1', 'name': 'VAT (5%)', 'type': 'PERCENTAGE', 'value': 5, 'computedAmount': 1.55}],
    'businessProfile': {'id': 'restaurant-001', 'businessName': "Chef Abby's", 'logoUrl': DemoMedia.rLogo},
    'location': {'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra'},
    'table': {'label': 'Table 12'},
  };}

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
  /// Returns story groups for a specific business. Each business has 2-3
  /// stories showcasing their products/services.
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
      throw DemoEndpointNotSeededException('GET', '/stories/business/$bizId');
    }

    return {
      'groups': [
        {
          'authorId': 0,
          'author': {
            'username': biz['name'],
            'profilePictureUrl': biz['logo'],
          },
          'hasUnseen': (biz['stories'] as List).any((s) => s['seen'] == false),
          'isBoosted': (biz['stories'] as List).any((s) => s['boosted'] == true),
          'stories': biz['stories'],
        },
      ],
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _dish(String id, String name, String description, double price, List<String> tags, String image, [String? bizId]) => {
    'id': id, 'businessProfileId': bizId ?? 'restaurant-001', 'name': name, 'slug': id,
    'description': description, 'priceUsdc': price, 'totalRevenue': 0,
    'imageUrls': [image],
    'isActive': true, 'totalOrders': 0, 'tags': tags,
  };

  static String _hoursAgo(int h) => DateTime.now().subtract(Duration(hours: h)).toUtc().toIso8601String();
  static String _daysAgo(int d) => DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();
  static String _hoursFromNow(int h) => DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String();
  static String _minutesAgo(int m) => DateTime.now().subtract(Duration(minutes: m)).toUtc().toIso8601String();
}
