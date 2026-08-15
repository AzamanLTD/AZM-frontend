// =============================================================================
// AZAMAN — DEMO SEED DATA: MARKETPLACE
// Comprehensive mock data for marketplace verticals in demo mode.
// =============================================================================

String _img(String seed, {int w = 600, int h = 400}) =>
    'https://picsum.photos/seed/$seed/$w/$h';

class DemoMarketplaceSeed {
  DemoMarketplaceSeed._();

  static const restaurantBizId = 'BIZ-REST-001';
  static const hotelBizId = 'BIZ-HOTEL-001';
  static const transitBizId = 'BIZ-TRANS-001';

  static Map<String, dynamic> searchBusinesses() => {
    'businesses': [
      _restaurantBusiness(), _hotelBusiness(), _transitBusiness(),
      _retailBusiness(),
    ],
    'hasMore': false, 'nextCursor': null,
  };

  static Map<String, dynamic> searchNearby() => {
    'locations': [_restaurantLocation(), _hotelLocation(), _transitLocation()],
    'hasMore': false, 'nextPage': null,
  };

  static Map<String, dynamic> getBusinessByBizId(String bizId) {
    switch (bizId) {
      case restaurantBizId: return {'business': _restaurantBusiness()};
      case hotelBizId: return {'business': _hotelBusiness()};
      case transitBizId: return {'business': _transitBusiness()};
      default: return {'business': _restaurantBusiness()};
    }
  }

  static Map<String, dynamic> getMenu(String bizId) {
    if (bizId == restaurantBizId) {
      return {
        'sections': [
          {'id': 'sec-starters', 'name': 'Starters', 'description': 'Small plates to share', 'products': [
            _dish('dish-kelewele', 'Kelewele', 'Spicy fried plantain cubes with ginger and pepper', 4.50, ['spicy','veg'], 'kelewele'),
            _dish('dish-jollof', 'Jollof Rice', 'Smoky one-pot rice in tomato-pepper sauce', 12.00, ['veg'], 'jollof'),
            _dish('dish-suya', 'Beef Suya', 'Grilled spiced beef skewers with yaji rub', 8.50, ['spicy'], 'suya'),
            _dish('dish-salad', 'Avocado Salad', 'Fresh avocado, tomato, red onion, lime dressing', 6.00, ['veg'], 'avocado-salad'),
          ]},
          {'id': 'sec-mains', 'name': 'Main Courses', 'description': 'Hearty Ghanaian classics', 'products': [
            _dish('dish-waakye', 'Waakye & Stew', 'Rice & beans with spaghetti, egg, shito, and fried plantain', 14.50, [], 'waakye'),
            _dish('dish-banku', 'Banku & Tilapia', 'Grilled tilapia with fermented corn dough', 18.00, [], 'banku-tilapia'),
            _dish('dish-fufu', 'Fufu & Light Soup', 'Pounded cassava with goat light soup', 16.00, ['spicy'], 'fufu-soup'),
            _dish('dish-redred', 'Red Red', 'Bean stew with fried plantain', 10.00, ['veg'], 'red-red'),
            _dish('dish-omotuo', 'Omo Tuo & Groundnut Soup', 'Rice balls in rich peanut soup with chicken', 15.00, [], 'omo-tuo'),
          ]},
          {'id': 'sec-drinks', 'name': 'Beverages', 'description': 'Fresh & chilled', 'products': [
            _dish('drink-sobo', 'Sobolo', 'Hibiscus iced tea with ginger', 3.00, ['veg'], 'sobolo'),
            _dish('drink-palm', 'Palm Wine', 'Freshly tapped from the Eastern Region', 4.00, [], 'palm-wine'),
            _dish('drink-asana', 'Asana', 'Corn drink with fermented milk', 3.50, ['veg'], 'asana'),
          ]},
          {'id': 'sec-desserts', 'name': 'Desserts', 'description': 'Sweet endings', 'products': [
            _dish('dessert-kele', 'Kelewele Sundae', 'Vanilla ice cream with caramelised plantain', 7.00, ['veg'], 'kelewele-sundae'),
            _dish('dessert-bofrot', 'Bofrot Trio', 'Three puff puffs with chocolate dip', 5.00, ['veg'], 'bofrot'),
          ]},
        ],
        'uncategorisedProducts': [],
      };
    }
    return {'sections': [], 'uncategorisedProducts': []};
  }

  static Map<String, dynamic> getMyInvoices() => {
    'invoices': [_unpaidInvoice(), _paidInvoice()],
    'hasMore': false, 'nextCursor': null,
  };

  static Map<String, dynamic> getInvoice(String invoiceId) =>
    {'invoice': invoiceId == 'inv-restaurant-001' ? _unpaidInvoice() : _paidInvoice()};

  static Map<String, dynamic> getTransitTrips() => {
    'success': true,
    'trips': [
      {'id': 'trip-001', 'businessProfileId': 'transit-001', 'vehicleId': 'veh-001',
       'routeName': 'Accra to Kumasi Express', 'origin': 'Accra', 'destination': 'Kumasi',
       'departureAt': _hoursFromNow(3), 'arrivalAt': _hoursFromNow(6),
       'fareUsdc': 15.00, 'availableSeats': 22, 'status': 'SCHEDULED',
       'vehicle': {'type': 'COACH', 'make': 'Mercedes-Benz', 'model': 'Sprinter 450',
         'imageUrl': 'https://picsum.photos/seed/coach-bus-fleet/600/400',
         'driverName': 'Kwabena Owusu', 'driverPhotoUrl': _img('driver-kwabena', w: 200, h: 200)},
       '_count': {'bookings': 12}},
      {'id': 'trip-002', 'businessProfileId': 'transit-001', 'vehicleId': 'veh-002',
       'routeName': 'Accra to Cape Coast Run', 'origin': 'Accra', 'destination': 'Cape Coast',
       'departureAt': _hoursFromNow(5), 'arrivalAt': _hoursFromNow(7),
       'fareUsdc': 10.00, 'availableSeats': 28, 'status': 'SCHEDULED',
       'vehicle': {'type': 'MINIVAN', 'make': 'Toyota', 'model': 'HiAce',
         'imageUrl': _img('toyota-hiace-van'),
         'driverName': 'Yaw Mensah', 'driverPhotoUrl': _img('driver-yaw', w: 200, h: 200)},
       '_count': {'bookings': 6}},
    ],
  };

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

  static Map<String, dynamic> getProducts(String bizId) {
    if (bizId == hotelBizId || bizId == 'hotel-001') return {'products': _hotelRooms()};
    if (bizId == transitBizId || bizId == 'transit-001') return {'products': _transitProducts()};
    if (bizId == restaurantBizId) return {'products': [
      _dish('dish-waakye', 'Waakye & Stew', 'Rice & beans with spaghetti, egg, shito', 14.50, [], 'waakye'),
      _dish('dish-jollof', 'Jollof Rice', 'Smoky one-pot rice', 12.00, ['veg'], 'jollof'),
    ]};
    return {'products': []};
  }

  static Map<String, dynamic> getLocations(String bizId) {
    switch (bizId) {
      case restaurantBizId: return {'locations': [_restaurantLocation()]};
      case hotelBizId: return {'locations': [_hotelLocation()]};
      case transitBizId: return {'locations': [_transitLocation()]};
      default: return {'locations': []};
    }
  }

  static Map<String, dynamic> getShowcase(String bizId) {
    if (bizId == hotelBizId) return {'data': ['https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/2012-01-21_Hotelhalle_in_Saigon.jpg/600px-2012-01-21_Hotelhalle_in_Saigon.jpg', 'https://upload.wikimedia.org/wikipedia/commons/7/78/Fm_stirling_pool.jpg', 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Leonardo_Royal_Hotel_Frankfurt_room.jpg/600px-Leonardo_Royal_Hotel_Frankfurt_room.jpg', 'https://picsum.photos/seed/hotel-fine-dining/600/400', 'https://picsum.photos/seed/hotel-building-night/600/400']};
    if (bizId == restaurantBizId) return {'data': ['https://picsum.photos/seed/restaurant-warm-interior/600/400', 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/94/Waakye101.jpg/600px-Waakye101.jpg', 'https://picsum.photos/seed/restaurant-bar-counter/600/400']};
    if (bizId == transitBizId) return {'data': ['https://picsum.photos/seed/coach-bus-fleet/600/400', 'https://picsum.photos/seed/bus-interior-seats/600/400']};
    return {'data': []};
  }

  // ── Business definitions ──────────────────────────────────────────────

  static Map<String, dynamic> _restaurantBusiness() => {
    'id': 'restaurant-001', 'bizId': restaurantBizId, 'businessName': "Chef Abby's",
    'category': 'FOOD_BEVERAGE', 'description': 'Authentic Ghanaian cuisine in the heart of Accra. From jollof to waakye, every plate tells a story.',
    'website': 'https://chefabbys.gh', 'logoUrl': 'https://picsum.photos/seed/chef-abbys-logo/200/200',
    'coverImageUrl': 'https://picsum.photos/seed/restaurant-warm-interior/800/400',
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

  static Map<String, dynamic> _hotelBusiness() {
    return {'id': 'hotel-001', 'bizId': hotelBizId, 'businessName': 'The Gallery',
      'category': 'HOSPITALITY', 'description': 'Boutique apartments in East Legon. Fully furnished studios and 1-bedroom suites with 24/7 concierge.',
      'website': 'https://thegallery.gh', 'logoUrl': 'https://picsum.photos/seed/the-gallery-logo/200/200',
      'coverImageUrl': 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/2012-01-21_Hotelhalle_in_Saigon.jpg/800px-2012-01-21_Hotelhalle_in_Saigon.jpg',
      'phoneNumber': '+233 26 987 6543', 'address': 'East Legon, Greater Accra', 'country': 'Ghana',
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 180, 'completedEscrows': 175, 'userId': 202,
      'totalVolume': 85000.00, 'averageRating': 4.8, 'reviewCount': 156,
      'subcategory': 'Apartments', 'priceRange': 3,
      'amenities': ['Pool','Gym','Spa','WiFi','Restaurant','Bar','Parking','Concierge'],
      'cuisineTypes': [], 'adAccentColor': '#1A8FE3',
      'user': {'id': 202, 'username': 'the_gallery', 'profilePictureUrl': null},
      'products': _hotelRooms(), 'locations': [_hotelLocation()],
      'businessMeta': {'showcaseUrls': ['https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/2012-01-21_Hotelhalle_in_Saigon.jpg/600px-2012-01-21_Hotelhalle_in_Saigon.jpg', 'https://upload.wikimedia.org/wikipedia/commons/7/78/Fm_stirling_pool.jpg', 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Leonardo_Royal_Hotel_Frankfurt_room.jpg/600px-Leonardo_Royal_Hotel_Frankfurt_room.jpg', 'https://picsum.photos/seed/hotel-fine-dining/600/400', 'https://picsum.photos/seed/hotel-building-night/600/400']},
    };
  }

  static Map<String, dynamic> _transitBusiness() {
    return {'id': 'transit-001', 'bizId': transitBizId, 'businessName': 'Advenr',
      'category': 'LOGISTICS', 'description': 'Premium intercity travel. Modern fleet, professional drivers, on-time departures, comfortable seats.',
      'website': 'https://advenr.gh', 'logoUrl': 'https://picsum.photos/seed/advenr-logo/200/200',
      'coverImageUrl': 'https://picsum.photos/seed/coach-bus-fleet/800/400',
      'phoneNumber': '+233 20 555 0199', 'address': 'Circle Station, Accra', 'country': 'Ghana',
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 520, 'completedEscrows': 515, 'userId': 203,
      'totalVolume': 78000.00, 'averageRating': 4.5, 'reviewCount': 410,
      'subcategory': 'Intercity Bus', 'priceRange': 1,
      'amenities': ['AC','WiFi','USB Charging','Refreshments'],
      'cuisineTypes': [], 'adAccentColor': '#10B981',
      'user': {'id': 203, 'username': 'advenr', 'profilePictureUrl': null},
      'products': _transitProducts(), 'locations': [_transitLocation()],
    };
  }

  static Map<String, dynamic> _retailBusiness() {
    return {'id': 'retail-001', 'bizId': 'BIZ-RETAIL-001', 'businessName': 'Mr. Price',
      'category': 'RETAIL', 'description': 'Fashion, homeware & lifestyle at everyday prices',
      'logoUrl': _img('mr-price-logo', w: 200, h: 200), 'coverImageUrl': _img('clothing-store-racks', w: 800, h: 400),
      'isVerified': true, 'isSuspended': false, 'kybStatus': 'VERIFIED',
      'totalEscrows': 320, 'completedEscrows': 315, 'userId': 205,
      'totalVolume': 45000.00, 'averageRating': 4.4, 'reviewCount': 210,
      'subcategory': 'Fashion Retail', 'priceRange': 1,
      'amenities': ['Changing Rooms','Click & Collect','Returns'],
      'cuisineTypes': [], 'adAccentColor': '#00D97E',
      'user': {'id': 205, 'username': 'mr_price', 'profilePictureUrl': null},
      'products': _retailProducts(), 'locations': [],
    };
  }

  // ── Locations ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _restaurantLocation() => {
    'id': 'loc-rest-001', 'businessProfileId': 'restaurant-001',
    'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.5550, 'longitude': -0.1800,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': ['https://picsum.photos/seed/restaurant-warm-interior/600/400', 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/94/Waakye101.jpg/600px-Waakye101.jpg', 'https://picsum.photos/seed/restaurant-bar-counter/600/400'],
    'distanceKm': 1.2,
  };

  static Map<String, dynamic> _hotelLocation() => {
    'id': 'loc-hotel-001', 'businessProfileId': 'hotel-001',
    'label': 'The Gallery - East Legon', 'address': 'East Legon, Greater Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.6400, 'longitude': -0.1680,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': ['https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/2012-01-21_Hotelhalle_in_Saigon.jpg/600px-2012-01-21_Hotelhalle_in_Saigon.jpg', 'https://upload.wikimedia.org/wikipedia/commons/7/78/Fm_stirling_pool.jpg', 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Leonardo_Royal_Hotel_Frankfurt_room.jpg/600px-Leonardo_Royal_Hotel_Frankfurt_room.jpg', 'https://picsum.photos/seed/hotel-fine-dining/600/400', 'https://picsum.photos/seed/hotel-building-night/600/400'],
    'distanceKm': 3.8,
  };

  static Map<String, dynamic> _transitLocation() => {
    'id': 'loc-transit-001', 'businessProfileId': 'transit-001',
    'label': 'Advenr - Circle Station', 'address': 'Circle Station, Accra',
    'city': 'Accra', 'region': 'Greater Accra', 'country': 'Ghana',
    'latitude': 5.5700, 'longitude': -0.2050,
    'isPrimary': true, 'isActive': true,
    'galleryUrls': ['https://picsum.photos/seed/coach-bus-fleet/600/400', 'https://picsum.photos/seed/bus-interior-seats/600/400'],
    'distanceKm': 2.5,
  };

  // ── Hotel Rooms ───────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _hotelRooms() {
    final rooms = <Map<String, dynamic>>[];
    for (var f = 1; f <= 4; f++) {
      for (var r = 1; r <= 6; r++) {
        final roomNumber = f * 100 + r;
        String roomType; double price;
        if (r <= 2) { roomType = 'Deluxe Suite'; price = 180.00; }
        else if (r <= 4) { roomType = 'Standard Room'; price = 95.00; }
        else { roomType = 'Economy Room'; price = 55.00; }
        rooms.add({'id': 'room-$roomNumber', 'businessProfileId': 'hotel-001',
          'name': 'Room $roomNumber', 'slug': 'room-$roomNumber',
          'description': '$roomType on Floor $f', 'priceUsdc': price, 'totalRevenue': 0,
          'imageUrls': [_img('hotel-room-$roomNumber-a'), _img('hotel-room-$roomNumber-b')],
          'isActive': true, 'totalOrders': 0,
          'tags': [roomType, 'Floor $f'], 'category': roomType});
      }
    }
    return rooms;
  }

  // ── Transit Products ──────────────────────────────────────────────────

  static List<Map<String, dynamic>> _transitProducts() => [
    {'id': 'prod-ticket-eco', 'businessProfileId': 'transit-001', 'name': 'Economy Ticket', 'slug': 'economy-ticket', 'description': 'Standard seat with AC and USB charging', 'priceUsdc': 15.00, 'totalRevenue': 12000, 'imageUrls': ['https://picsum.photos/seed/bus-economy-seat/400/300'], 'isActive': true, 'totalOrders': 800, 'tags': ['Economy']},
    {'id': 'prod-ticket-std', 'businessProfileId': 'transit-001', 'name': 'Standard Ticket', 'slug': 'standard-ticket', 'description': 'Wider seat, priority boarding, refreshments', 'priceUsdc': 18.00, 'totalRevenue': 8000, 'imageUrls': ['https://picsum.photos/seed/bus-standard-seat/400/300'], 'isActive': true, 'totalOrders': 440, 'tags': ['Standard']},
    {'id': 'prod-ticket-vip', 'businessProfileId': 'transit-001', 'name': 'VIP Ticket', 'slug': 'vip-ticket', 'description': 'Lie-flat seat, privacy curtain, meal included', 'priceUsdc': 25.00, 'totalRevenue': 5000, 'imageUrls': ['https://picsum.photos/seed/bus-vip-seat/400/300'], 'isActive': true, 'totalOrders': 200, 'tags': ['VIP']},
  ];

  // ── Retail Products ───────────────────────────────────────────────────

  static List<Map<String, dynamic>> _retailProducts() => [
    {'id': 'prod-tshirt', 'businessProfileId': 'retail-001', 'name': 'Cotton Crew Tee', 'slug': 'cotton-crew-tee', 'description': 'Soft 100% cotton t-shirt in classic colours', 'priceUsdc': 8.00, 'totalRevenue': 2400, 'imageUrls': [_img('cotton-tee-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 300, 'tags': ['Tops', 'Unisex']},
    {'id': 'prod-jeans', 'businessProfileId': 'retail-001', 'name': 'Slim Fit Jeans', 'slug': 'slim-fit-jeans', 'description': 'Stretch denim with modern slim silhouette', 'priceUsdc': 22.00, 'totalRevenue': 4400, 'imageUrls': [_img('slim-jeans-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 200, 'tags': ['Bottoms', 'Denim']},
    {'id': 'prod-hoodie', 'businessProfileId': 'retail-001', 'name': 'Fleece Hoodie', 'slug': 'fleece-hoodie', 'description': 'Warm fleece-lined hoodie with kangaroo pocket', 'priceUsdc': 28.00, 'totalRevenue': 2800, 'imageUrls': [_img('fleece-hoodie-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 100, 'tags': ['Outerwear', 'Unisex']},
    {'id': 'prod-sneakers', 'businessProfileId': 'retail-001', 'name': 'Canvas Sneakers', 'slug': 'canvas-sneakers', 'description': 'Lightweight canvas sneakers, vulcanised rubber sole', 'priceUsdc': 35.00, 'totalRevenue': 3500, 'imageUrls': [_img('canvas-sneakers-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 100, 'tags': ['Footwear']},
    {'id': 'prod-watch', 'businessProfileId': 'retail-001', 'name': 'Minimalist Watch', 'slug': 'minimalist-watch', 'description': 'Slim analogue watch with leather strap', 'priceUsdc': 45.00, 'totalRevenue': 2250, 'imageUrls': [_img('minimalist-watch-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 50, 'tags': ['Accessories']},
    {'id': 'prod-tote', 'businessProfileId': 'retail-001', 'name': 'Canvas Tote Bag', 'slug': 'canvas-tote-bag', 'description': 'Durable canvas tote with reinforced straps', 'priceUsdc': 12.00, 'totalRevenue': 1200, 'imageUrls': [_img('tote-bag-product', w: 400, h: 400)], 'isActive': true, 'totalOrders': 100, 'tags': ['Accessories', 'Bags']},
  ];

  // ── Invoices ──────────────────────────────────────────────────────────

  static Map<String, dynamic> _unpaidInvoice() => {
    'id': 'inv-restaurant-001', 'businessProfileId': 'restaurant-001',
    'invoiceRef': 'AZM-INV-2026-001', 'locationId': 'loc-rest-001', 'tableId': 'tbl-003',
    'customerId': 1, 'status': 'SENT',
    'subtotalUsdc': 52.50, 'taxTotalUsdc': 2.63, 'tipUsdc': 0, 'billTotalUsdc': 55.13,
    'feeUsdc': 0, 'customerCoveredFee': false,
    'sentAt': _hoursAgo(1), 'paidAt': null, 'voidedAt': null, 'createdAt': _hoursAgo(2),
    'lineItems': [
      {'id': 'li-1', 'description': 'Jollof Rice', 'quantity': 2, 'unitPrice': 12.00, 'lineTotal': 24.00},
      {'id': 'li-2', 'description': 'Beef Suya', 'quantity': 1, 'unitPrice': 8.50, 'lineTotal': 8.50},
      {'id': 'li-3', 'description': 'Waakye & Stew', 'quantity': 1, 'unitPrice': 14.50, 'lineTotal': 14.50},
      {'id': 'li-4', 'description': 'Sobolo', 'quantity': 2, 'unitPrice': 3.00, 'lineTotal': 6.00},
    ],
    'taxLines': [{'id': 'tax-1', 'name': 'VAT (5%)', 'type': 'PERCENTAGE', 'value': 5, 'computedAmount': 2.63}],
    'businessProfile': {'id': 'restaurant-001', 'businessName': "Chef Abby's", 'logoUrl': 'https://picsum.photos/seed/chef-abbys-logo/200/200'},
    'location': {'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra'},
    'table': {'label': 'Table 7'},
  };

  static Map<String, dynamic> _paidInvoice() => {
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
    'businessProfile': {'id': 'restaurant-001', 'businessName': "Chef Abby's", 'logoUrl': 'https://picsum.photos/seed/chef-abbys-logo/200/200'},
    'location': {'label': "Chef Abby's - Osu", 'address': 'Oxford Street, Osu, Accra'},
    'table': {'label': 'Table 12'},
  };


  // ── Following list (marketplace story rail) ────────────────────────────

  static List<Map<String, dynamic>> getFollowing() => [
    {
      'id': restaurantBizId,
      'businessName': "Chef Abby's",
      'logoUrl': 'https://picsum.photos/seed/chef-abbys-logo/200/200',
      'isVerified': true,
      'lastStoryAt': _hoursAgo(2),
      'lastViewedAt': _hoursAgo(3),
    },
    {
      'id': hotelBizId,
      'businessName': 'The Gallery',
      'logoUrl': 'https://picsum.photos/seed/the-gallery-logo/200/200',
      'isVerified': true,
      'lastStoryAt': _hoursAgo(8),
      'lastViewedAt': _hoursAgo(1),
    },
    {
      'id': 'BIZ-RETAIL-001',
      'businessName': 'Mr. Price',
      'logoUrl': _img('mr-price-logo', w: 200, h: 200),
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
        'logo': 'https://picsum.photos/seed/chef-abbys-logo/200/200',
        'stories': [
          {
            'id': 'bs-r1',
            'mediaUrl': _img('ghanaian-jollof-rice', w: 600, h: 900),
            'mediaType': 'IMAGE',
            'caption': 'Fresh jollof straight from the kitchen 🔥',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
          {
            'id': 'bs-r2',
            'mediaUrl': _img('restaurant-grilled-fish', w: 600, h: 900),
            'mediaType': 'IMAGE',
            'caption': 'Tonight\'s special: grilled tilapia',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
          {
            'id': 'bs-r3',
            'mediaUrl': _img('ghanaian-food-spread', w: 600, h: 900),
            'mediaType': 'IMAGE',
            'caption': 'Weekend buffet is back!',
            'durationSeconds': 5,
            'boosted': true,
            'seen': false,
            'createdAt': _hoursAgo(1),
          },
        ],
      },
      hotelBizId: {
        'name': 'The Gallery',
        'logo': 'https://picsum.photos/seed/the-gallery-logo/200/200',
        'stories': [
          {
            'id': 'bs-h1',
            'mediaUrl': 'https://upload.wikimedia.org/wikipedia/commons/7/78/Fm_stirling_pool.jpg',
            'mediaType': 'IMAGE',
            'caption': 'Rooftop pool now open',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(8),
          },
          {
            'id': 'bs-h2',
            'mediaUrl': 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Leonardo_Royal_Hotel_Frankfurt_room.jpg/600px-Leonardo_Royal_Hotel_Frankfurt_room.jpg',
            'mediaType': 'IMAGE',
            'caption': 'New deluxe suites available',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(7),
          },
        ],
      },
      transitBizId: {
        'name': 'Advenr',
        'logo': 'https://picsum.photos/seed/advenr-logo/200/200',
        'stories': [
          {
            'id': 'bs-t1',
            'mediaUrl': 'https://picsum.photos/seed/coach-bus-exterior/600/900',
            'mediaType': 'IMAGE',
            'caption': 'New fleet just arrived!',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(20),
          },
          {
            'id': 'bs-t2',
            'mediaUrl': 'https://picsum.photos/seed/bus-interior-seats/600/900',
            'mediaType': 'IMAGE',
            'caption': 'AC + WiFi + USB on every seat',
            'durationSeconds': 5,
            'boosted': true,
            'seen': true,
            'createdAt': _hoursAgo(19),
          },
        ],
      },
      'BIZ-RETAIL-001': {
        'name': 'Mr. Price',
        'logo': _img('mr-price-logo', w: 200, h: 200),
        'stories': [
          {
            'id': 'bs-r1',
            'mediaUrl': _img('clothing-store-racks', w: 600, h: 900),
            'mediaType': 'IMAGE',
            'caption': 'New season drop is here!',
            'durationSeconds': 5,
            'boosted': true,
            'seen': false,
            'createdAt': _hoursAgo(3),
          },
          {
            'id': 'bs-r2',
            'mediaUrl': _img('fashion-sale-display', w: 600, h: 900),
            'mediaType': 'IMAGE',
            'caption': 'Up to 40% off all items',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
        ],
      },
    };

    final biz = businesses[bizId];
    if (biz == null) {
      return {'groups': []};
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

  static Map<String, dynamic> _dish(String id, String name, String description, double price, List<String> tags, String img) => {
    'id': id, 'businessProfileId': 'restaurant-001', 'name': name, 'slug': id,
    'description': description, 'priceUsdc': price, 'totalRevenue': 0,
    'imageUrls': [_img('food-$img', w: 400, h: 300)],
    'isActive': true, 'totalOrders': 0, 'tags': tags,
  };

  static String _hoursAgo(int h) => DateTime.now().subtract(Duration(hours: h)).toUtc().toIso8601String();
  static String _daysAgo(int d) => DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();
  static String _hoursFromNow(int h) => DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String();
}
