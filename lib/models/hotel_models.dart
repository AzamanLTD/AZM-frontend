import 'package:azaman/models/business_models.dart';

/// Customer-facing representation of a HotelRoom.
///
/// Unlike BusinessProduct, floor/room/capacity/status are first-class fields
/// here because they are authoritative inventory data, not presentation hints.
class HotelRoom {
  final String id;
  final String businessProfileId;
  final String? locationId;
  final String roomNumber;
  final String roomType;
  final int? floor;
  final int capacity;
  final String? bedConfig;
  final String status;
  final double basePriceUsdc;
  final double? weekendPriceUsdc;
  final List<String> amenities;
  final List<String> imageUrls;

  const HotelRoom({
    required this.id,
    required this.businessProfileId,
    required this.roomNumber,
    required this.roomType,
    required this.capacity,
    required this.status,
    required this.basePriceUsdc,
    required this.amenities,
    required this.imageUrls,
    this.locationId,
    this.floor,
    this.bedConfig,
    this.weekendPriceUsdc,
  });

  bool get isBookable => status.toUpperCase() == 'AVAILABLE';

  /// The same room, not bookable for the dates being looked at (taken,
  /// blocked or too small): the floor plan greys it out.
  HotelRoom unavailableForStay() => HotelRoom(
    id: id,
    businessProfileId: businessProfileId,
    roomNumber: roomNumber,
    roomType: roomType,
    capacity: capacity,
    status: 'UNAVAILABLE_FOR_STAY',
    basePriceUsdc: basePriceUsdc,
    amenities: amenities,
    imageUrls: imageUrls,
    locationId: locationId,
    floor: floor,
    bedConfig: bedConfig,
    weekendPriceUsdc: weekendPriceUsdc,
  );
  String get displayType => roomType
      .toLowerCase()
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
  String? get primaryImage => imageUrls.isEmpty ? null : imageUrls.first;

  factory HotelRoom.fromJson(Map<String, dynamic> json) {
    return HotelRoom(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      locationId: json['locationId']?.toString(),
      roomNumber: (json['roomNumber'] ?? '').toString(),
      roomType: (json['roomType'] ?? 'ROOM').toString(),
      floor: json['floor'] == null
          ? null
          : int.tryParse(json['floor'].toString()),
      capacity: int.tryParse(json['capacity']?.toString() ?? '') ?? 1,
      bedConfig: json['bedConfig']?.toString(),
      status: (json['status'] ?? 'UNKNOWN').toString(),
      basePriceUsdc: _hotelToDouble(json['basePriceUsdc'] ?? json['priceUsdc']),
      weekendPriceUsdc: json['weekendPriceUsdc'] == null
          ? null
          : _hotelToDouble(json['weekendPriceUsdc']),
      amenities: _hotelStrings(json['amenities']),
      imageUrls: _hotelStrings(json['imageUrls']),
    );
  }

  /// Preserve the existing generic-business APIs while the hotel flow moves
  /// fully onto HotelRoom. Useful only for legacy widgets that still render a
  /// BusinessProduct-shaped preview; booking continues to use [id].
  BusinessProduct toLegacyProduct() => BusinessProduct(
    id: id,
    businessProfileId: businessProfileId,
    name: 'Room $roomNumber',
    slug: 'hotel-room-$id',
    description: bedConfig,
    category: 'HOSPITALITY',
    locationId: locationId,
    priceUsdc: basePriceUsdc,
    totalRevenue: 0,
    imageUrls: imageUrls,
    isActive: isBookable,
    totalOrders: 0,
    tags: [roomType, ...amenities],
  );
}

double _hotelToDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _hotelStrings(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : const [];

/// One room in a stay quote: its exact total for the dates (the server's own
/// per-night pricing) and whether it can be booked, with the reason if not.
class RoomQuote {
  final String roomId;
  final bool bookable;
  final String? reason;
  final double totalUsdc;
  final int capacity;

  const RoomQuote({
    required this.roomId,
    required this.bookable,
    required this.totalUsdc,
    this.reason,
    this.capacity = 1,
  });

  /// Why the room is greyed out, in a few words.
  String? get reasonLabel => switch (reason) {
    'TOO_SMALL' => 'Too small for your group',
    'BOOKED' => 'Taken for these dates',
    'BLOCKED' => 'Closed for these dates',
    'ROOM_UNAVAILABLE' => 'Not available',
    'NO_PRICE' => 'No price set',
    _ => null,
  };

  factory RoomQuote.fromJson(Map<String, dynamic> json) => RoomQuote(
    roomId: json['roomId']?.toString() ?? '',
    bookable: json['bookable'] == true,
    reason: json['reason']?.toString(),
    totalUsdc: double.tryParse('${json['totalUsdc'] ?? 0}') ?? 0,
    capacity: int.tryParse('${json['capacity'] ?? 1}') ?? 1,
  );
}

/// GET /marketplace/business/:bizId/stay-quote: what each room costs for the
/// chosen dates and guests, and where the stay is paid.
class StayQuote {
  final int nights;
  final int guests;

  /// 'HOTEL': requested in the app, paid at the hotel.
  final String payAt;
  final Map<String, RoomQuote> rooms;

  const StayQuote({
    required this.nights,
    required this.guests,
    required this.rooms,
    this.payAt = 'HOTEL',
  });

  bool get payAtHotel => payAt.toUpperCase() == 'HOTEL';

  factory StayQuote.fromJson(Map<String, dynamic> json) {
    final list = (json['rooms'] as List? ?? const []).whereType<Map>().map(
      (r) => RoomQuote.fromJson(Map<String, dynamic>.from(r)),
    );
    return StayQuote(
      nights: int.tryParse('${json['nights'] ?? 0}') ?? 0,
      guests: int.tryParse('${json['guests'] ?? 1}') ?? 1,
      payAt: json['payAt']?.toString() ?? 'HOTEL',
      rooms: {for (final r in list) r.roomId: r},
    );
  }
}
