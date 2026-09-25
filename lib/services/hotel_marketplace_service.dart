import 'dart:convert';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/api_client.dart';

class HotelMarketplaceException implements Exception {
  final String message;
  final int? statusCode;
  const HotelMarketplaceException(this.message, {this.statusCode});

  @override
  String toString() => 'HotelMarketplaceException: $message';
}

class HotelBusinessDetail {
  final BusinessProfile business;
  final List<HotelRoom> rooms;

  const HotelBusinessDetail({required this.business, required this.rooms});
}

class HotelMarketplaceService {
  final ApiClient _client = ApiClient();

  Future<HotelBusinessDetail> fetchHotel(String bizId) async {
    final response = await _client.get('/marketplace/business/$bizId');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw HotelMarketplaceException(
        (body['message'] ?? 'Unable to load hotel').toString(),
        statusCode: response.statusCode,
      );
    }

    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rooms = (data['hotelRooms'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(HotelRoom.fromJson)
        .toList();
    return HotelBusinessDetail(
      business: BusinessProfile.fromJson(
        (data['business'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      rooms: rooms,
    );
  }

  Future<Map<String, dynamic>> reserve({
    required String bizId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
    int partySize = 1,
  }) async {
    final response = await _client.post('/marketplace/business/$bizId/reservations', {
      'roomId': roomId,
      'checkInDate': checkIn.toIso8601String(),
      'checkOutDate': checkOut.toIso8601String(),
      'partySize': partySize,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw HotelMarketplaceException(
        (body['message'] ?? 'Booking failed').toString(),
        statusCode: response.statusCode,
      );
    }
    final reservation = (body['reservation'] as Map?)?.cast<String, dynamic>();
    if (reservation == null) {
      throw const HotelMarketplaceException('Booking completed without a reservation response.');
    }
    return reservation;
  }
}
