// =============================================================================
// AZAMAN — MARKETPLACE BOOKING MODELS (2026-07-02)
//
// Models for the marketplace booking lifecycle overhaul:
//   - TransitTrip: scheduled departure for a vehicle
//   - TransitSeat: individual seat with availability status
//   - SeatAvailability: full seat map for a trip
//   - CheckInToken: HMAC-signed QR token for reservation check-in
//   - CheckInResult: result of a business check-in scan
//   - AzamanIdSearchResult: manual AZM-ID search result
//   - BookSeatResult: transit seat booking result
//   - BusinessStory: story linked to a business (viral loop)
// =============================================================================

// ── HELPERS ──────────────────────────────────────────────────────────────────

DateTime _toDate(dynamic v) {
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

// ── TRANSIT TRIP ─────────────────────────────────────────────────────────────

enum TripStatus { scheduled, departed, completed, cancelled }

class TransitTrip {
  final String id;
  final String businessProfileId;
  final String vehicleId;
  final String routeName;
  final String origin;
  final String destination;
  final DateTime departureAt;
  final DateTime? arrivalAt;
  final double fareUsdc;
  final int availableSeats;
  final TripStatus status;
  final String? vehicleType;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleImageUrl;
  final String? driverName;
  final String? driverPhotoUrl;
  // ── Added 2026-08-23: vehicle & crew info for header strip ──
  final String? plateNumber;
  final String? coDriverName;
  final String? coDriverPhotoUrl;
  final int bookingCount;

  const TransitTrip({
    required this.id,
    required this.businessProfileId,
    required this.vehicleId,
    required this.routeName,
    required this.origin,
    required this.destination,
    required this.departureAt,
    this.arrivalAt,
    required this.fareUsdc,
    required this.availableSeats,
    required this.status,
    this.vehicleType,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleImageUrl,
    this.driverName,
    this.driverPhotoUrl,
    this.plateNumber,
    this.coDriverName,
    this.coDriverPhotoUrl,
    this.bookingCount = 0,
  });

  String get vehicleLabel {
    final parts = [vehicleMake, vehicleModel].where((p) => p != null && p.isNotEmpty);
    return parts.isNotEmpty ? parts.join(' ') : (vehicleType ?? 'Vehicle');
  }

  String get routeLabel => '$origin \u2192 $destination';

  static TripStatus _parseStatus(String? s) {
    switch (s) {
      case 'DEPARTED': return TripStatus.departed;
      case 'COMPLETED': return TripStatus.completed;
      case 'CANCELLED': return TripStatus.cancelled;
      default: return TripStatus.scheduled;
    }
  }

  factory TransitTrip.fromJson(Map<String, dynamic> json) {
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    final count = json['_count'] as Map<String, dynamic>?;
    return TransitTrip(
      id: json['id'] as String? ?? '',
      businessProfileId: json['businessProfileId'] as String? ?? '',
      vehicleId: json['vehicleId'] as String? ?? '',
      routeName: json['routeName'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      departureAt: _toDate(json['departureAt']),
      arrivalAt: json['arrivalAt'] != null ? _toDate(json['arrivalAt']) : null,
      fareUsdc: _toDouble(json['fareUsdc']),
      availableSeats: _toInt(json['availableSeats']),
      status: _parseStatus(json['status'] as String?),
      vehicleType: vehicle?['type']?.toString(),
      vehicleMake: vehicle?['make']?.toString(),
      vehicleModel: vehicle?['model']?.toString(),
      vehicleImageUrl: vehicle?['imageUrl']?.toString(),
      driverName: vehicle?['driverName']?.toString(),
      driverPhotoUrl: vehicle?['driverPhotoUrl']?.toString(),
      plateNumber: vehicle?['plateNumber']?.toString(),
      coDriverName: vehicle?['coDriverName']?.toString(),
      coDriverPhotoUrl: vehicle?['coDriverPhotoUrl']?.toString(),
      bookingCount: count?['bookings'] != null ? _toInt(count!['bookings']) : 0,
    );
  }
}

// ── TRANSIT SEAT ─────────────────────────────────────────────────────────────

enum SeatStatus { available, occupied, blocked }
enum SeatType { window, aisle, extra }
enum SeatTier { economy, standard, vip }

class TransitSeat {
  final String seatId;
  final int row;
  final int col;
  final SeatType type;
  final SeatStatus status;
  final SeatTier tier;
  final double fare;

  const TransitSeat({
    required this.seatId,
    required this.row,
    required this.col,
    required this.type,
    required this.status,
    this.tier = SeatTier.economy,
    this.fare = 0,
  });

  static SeatType _parseType(String? s) {
    switch (s?.toUpperCase()) {
      case 'WINDOW': return SeatType.window;
      case 'AISLE': return SeatType.aisle;
      default: return SeatType.extra;
    }
  }

  static SeatTier _parseTier(String? s) {
    switch (s?.toUpperCase()) {
      case 'VIP': return SeatTier.vip;
      case 'STANDARD': return SeatTier.standard;
      default: return SeatTier.economy;
    }
  }

  static SeatStatus _parseStatus(String? s) {
    switch (s?.toUpperCase()) {
      case 'OCCUPIED': return SeatStatus.occupied;
      case 'BLOCKED': return SeatStatus.blocked;
      default: return SeatStatus.available;
    }
  }

  factory TransitSeat.fromJson(Map<String, dynamic> json) {
    return TransitSeat(
      seatId: json['seatId'] as String? ?? '',
      row: _toInt(json['row']),
      col: _toInt(json['col']),
      type: _parseType(json['type']?.toString()),
      status: _parseStatus(json['status']?.toString()),
      tier: _parseTier(json['tier']?.toString()),
      fare: _toDouble(json['fare']),
    );
  }
}

// ── SEAT AVAILABILITY RESPONSE ───────────────────────────────────────────────

class SeatAvailability {
  final String tripId;
  final List<TransitSeat> seats;
  final int availableCount;
  final int totalSeats;
  final String tripStatus;
  final double fareUsdc;
  final Map<String, double> tierFares;

  const SeatAvailability({
    required this.tripId,
    required this.seats,
    required this.availableCount,
    required this.totalSeats,
    required this.tripStatus,
    required this.fareUsdc,
    this.tierFares = const {},
  });

  factory SeatAvailability.fromJson(Map<String, dynamic> json) {
    final seatsList = json['seats'] as List? ?? [];
    final tierFaresJson = json['tierFares'] as Map? ?? {};
    return SeatAvailability(
      tripId: json['tripId'] as String? ?? '',
      seats: seatsList.map((s) => TransitSeat.fromJson(s as Map<String, dynamic>)).toList(),
      availableCount: _toInt(json['availableCount']),
      totalSeats: _toInt(json['totalSeats']),
      tripStatus: json['tripStatus'] as String? ?? 'SCHEDULED',
      fareUsdc: _toDouble(json['fareUsdc']),
      tierFares: tierFaresJson.map((k, v) => MapEntry(k.toString(), _toDouble(v))),
    );
  }
}

// ── CHECK-IN TOKEN ───────────────────────────────────────────────────────────

class CheckInToken {
  final String token;
  final String qrPayload;
  final String azamanId;
  final String reservationRef;
  final DateTime expiresAt;
  final String? businessName;
  final String? businessLogoUrl;

  const CheckInToken({
    required this.token,
    required this.qrPayload,
    required this.azamanId,
    required this.reservationRef,
    required this.expiresAt,
    this.businessName,
    this.businessLogoUrl,
  });

  factory CheckInToken.fromJson(Map<String, dynamic> json) {
    return CheckInToken(
      token: json['token'] as String? ?? '',
      qrPayload: json['qrPayload'] as String? ?? '',
      azamanId: json['azamanId'] as String? ?? '',
      reservationRef: json['reservationRef'] as String? ?? '',
      expiresAt: _toDate(json['expiresAt']),
      businessName: json['businessName']?.toString(),
      businessLogoUrl: json['businessLogoUrl']?.toString(),
    );
  }
}

// ── CHECK-IN RESULT ──────────────────────────────────────────────────────────

class CheckInResult {
  final bool success;
  final String? customerAzamanId;
  final String? customerUsername;
  final String? customerProfilePictureUrl;
  final String? businessName;
  final String reservationRef;
  final String status;
  final DateTime? checkedInAt;

  const CheckInResult({
    required this.success,
    this.customerAzamanId,
    this.customerUsername,
    this.customerProfilePictureUrl,
    this.businessName,
    required this.reservationRef,
    required this.status,
    this.checkedInAt,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    final reservation = json['reservation'] as Map<String, dynamic>?;
    final customer = reservation?['customer'] as Map<String, dynamic>?;
    final business = reservation?['businessProfile'] as Map<String, dynamic>?;
    return CheckInResult(
      success: json['success'] == true,
      customerAzamanId: json['customerAzamanId']?.toString() ?? customer?['azamanId']?.toString(),
      customerUsername: customer?['username']?.toString(),
      customerProfilePictureUrl: customer?['profilePictureUrl']?.toString(),
      businessName: business?['businessName']?.toString(),
      reservationRef: reservation?['reservationRef'] as String? ?? '',
      status: reservation?['status'] as String? ?? '',
      checkedInAt: reservation?['checkedInAt'] != null ? _toDate(reservation!['checkedInAt']) : null,
    );
  }
}

// ── AZM-ID SEARCH RESULT ─────────────────────────────────────────────────────

class AzamanIdSearchResult {
  final String customerId;
  final String username;
  final String azamanId;
  final String? profilePictureUrl;
  final List<SearchReservation> reservations;

  const AzamanIdSearchResult({
    required this.customerId,
    required this.username,
    required this.azamanId,
    this.profilePictureUrl,
    required this.reservations,
  });

  factory AzamanIdSearchResult.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? {};
    final reservationsList = json['reservations'] as List? ?? [];
    return AzamanIdSearchResult(
      customerId: customer['id']?.toString() ?? '',
      username: customer['username']?.toString() ?? 'Unknown',
      azamanId: customer['azamanId']?.toString() ?? '',
      profilePictureUrl: customer['profilePictureUrl']?.toString(),
      reservations: reservationsList.map((r) => SearchReservation.fromJson(r as Map<String, dynamic>)).toList(),
    );
  }
}

class SearchReservation {
  final String id;
  final String reservationRef;
  final String status;
  final DateTime startDatetime;
  final double amountUsdc;

  const SearchReservation({
    required this.id,
    required this.reservationRef,
    required this.status,
    required this.startDatetime,
    required this.amountUsdc,
  });

  factory SearchReservation.fromJson(Map<String, dynamic> json) {
    return SearchReservation(
      id: json['id'] as String? ?? '',
      reservationRef: json['reservationRef'] as String? ?? '',
      status: json['status'] as String? ?? '',
      startDatetime: _toDate(json['startDatetime']),
      amountUsdc: _toDouble(json['amountUsdc']),
    );
  }
}

// ── BOOK SEAT RESULT ─────────────────────────────────────────────────────────

class BookSeatResult {
  final bool success;
  final String bookingId;
  final String bookingRef;
  final List<String> seatIds;
  final double totalFare;
  final String status;

  const BookSeatResult({
    required this.success,
    required this.bookingId,
    required this.bookingRef,
    required this.seatIds,
    required this.totalFare,
    required this.status,
  });

  factory BookSeatResult.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>? ?? {};
    return BookSeatResult(
      success: json['success'] == true,
      bookingId: booking['id'] as String? ?? '',
      bookingRef: booking['bookingRef'] as String? ?? '',
      seatIds: (json['seatIds'] as List?)?.map((s) => s.toString()).toList() ?? [],
      totalFare: _toDouble(json['totalFare']),
      status: booking['status'] as String? ?? 'PENDING',
    );
  }
}

// ── BUSINESS STORY (for viral loop) ──────────────────────────────────────────

class BusinessStory {
  final String id;
  final String userId;
  final String? businessProfileId;
  final String mediaUrl;
  final String caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? username;
  final String? userProfilePictureUrl;

  const BusinessStory({
    required this.id,
    required this.userId,
    this.businessProfileId,
    required this.mediaUrl,
    required this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.username,
    this.userProfilePictureUrl,
  });

  factory BusinessStory.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return BusinessStory(
      id: json['id'] as String? ?? '',
      userId: json['userId']?.toString() ?? '',
      businessProfileId: json['businessProfileId']?.toString(),
      mediaUrl: json['mediaUrl'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      createdAt: _toDate(json['createdAt']),
      expiresAt: _toDate(json['expiresAt']),
      username: user?['username']?.toString(),
      userProfilePictureUrl: user?['profilePictureUrl']?.toString(),
    );
  }
}


