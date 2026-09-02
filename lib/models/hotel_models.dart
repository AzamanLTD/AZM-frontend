'use strict';

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
  String get displayType => roomType
      .toLowerCase()
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  String? get primaryImage => imageUrls.isEmpty ? null : imageUrls.first;

  factory HotelRoom.fromJson(Map<String, dynamic> json) {
    return HotelRoom(
      id: json['id'].toString(),
      businessProfileId: (json['businessProfileId'] ?? '').toString(),
      locationId: json['locationId']?.toString(),
      roomNumber: (json['roomNumber'] ?? '').toString(),
      roomType: (json['roomType'] ?? 'ROOM').toString(),
      floor: json['floor'] == null ? null : int.tryParse(json['floor'].toString()),
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

List<String> _hotelStrings(dynamic value) => value is List
    ? value.map((item) => item.toString()).toList()
    : const [];
