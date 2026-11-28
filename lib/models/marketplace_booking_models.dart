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
  return DateTime.tryParse(v.toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);
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
    final parts = [
      vehicleMake,
      vehicleModel,
    ].where((p) => p != null && p.isNotEmpty);
    return parts.isNotEmpty ? parts.join(' ') : (vehicleType ?? 'Vehicle');
  }

  String get routeLabel => '$origin \u2192 $destination';

  static TripStatus _parseStatus(String? s) {
    switch (s) {
      case 'DEPARTED':
        return TripStatus.departed;
      case 'COMPLETED':
        return TripStatus.completed;
      case 'CANCELLED':
        return TripStatus.cancelled;
      default:
        return TripStatus.scheduled;
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

/// [none] is a cell the operator marked as empty space or walkway in the
/// seat-map editor ("NONE"). It is not a seat and is never drawn as one.
enum SeatType { window, aisle, extra, none }

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

  /// An operator-marked empty cell, not a seat.
  bool get isSpace => type == SeatType.none;

  static SeatType _parseType(String? s) {
    switch (s?.toUpperCase()) {
      case 'WINDOW':
        return SeatType.window;
      case 'AISLE':
        return SeatType.aisle;
      case 'NONE':
      case 'EMPTY':
        return SeatType.none;
      default:
        return SeatType.extra;
    }
  }

  static SeatTier _parseTier(String? s) {
    switch (s?.toUpperCase()) {
      case 'VIP':
        return SeatTier.vip;
      case 'STANDARD':
        return SeatTier.standard;
      default:
        return SeatTier.economy;
    }
  }

  static SeatStatus _parseStatus(String? s) {
    switch (s?.toUpperCase()) {
      case 'OCCUPIED':
        return SeatStatus.occupied;
      case 'BLOCKED':
        return SeatStatus.blocked;
      default:
        return SeatStatus.available;
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
      seats: seatsList
          .map((s) => TransitSeat.fromJson(s as Map<String, dynamic>))
          .toList(),
      availableCount: _toInt(json['availableCount']),
      totalSeats: _toInt(json['totalSeats']),
      tripStatus: json['tripStatus'] as String? ?? 'SCHEDULED',
      fareUsdc: _toDouble(json['fareUsdc']),
      tierFares: tierFaresJson.map(
        (k, v) => MapEntry(k.toString(), _toDouble(v)),
      ),
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

  /// A transit passenger boarded (rather than a hotel guest checked in).
  final bool isTransit;
  final String? customerAzamanId;
  final String? customerUsername;
  final String? customerProfilePictureUrl;
  final String? businessName;
  final String reservationRef;
  final String status;
  final DateTime? checkedInAt;

  /// Boarded by staff after an ID check (not by the passenger's QR).
  final bool boardedByIdCheck;

  /// Hours after departure an unconfirmed ID-check fare is held before it
  /// is paid to the operator (the passenger's window to report it).
  final int? fareHeldHours;

  const CheckInResult({
    required this.success,
    this.isTransit = false,
    this.customerAzamanId,
    this.customerUsername,
    this.customerProfilePictureUrl,
    this.businessName,
    required this.reservationRef,
    required this.status,
    this.checkedInAt,
    this.boardedByIdCheck = false,
    this.fareHeldHours,
  });

  /// The same result, naming the passenger staff just checked.
  CheckInResult withPassenger(PassengerIdCard? p) => p == null
      ? this
      : CheckInResult(
          success: success,
          isTransit: isTransit,
          customerAzamanId: p.azamanId.isEmpty ? customerAzamanId : p.azamanId,
          customerUsername: p.shownName,
          customerProfilePictureUrl:
              p.profilePictureUrl ?? customerProfilePictureUrl,
          businessName: businessName,
          reservationRef: reservationRef,
          status: status,
          checkedInAt: checkedInAt,
          boardedByIdCheck: boardedByIdCheck,
          fareHeldHours: fareHeldHours,
        );

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    final reservation = json['reservation'] as Map<String, dynamic>?;
    final customer = reservation?['customer'] as Map<String, dynamic>?;
    final business = reservation?['businessProfile'] as Map<String, dynamic>?;
    return CheckInResult(
      success: json['success'] == true,
      customerAzamanId:
          json['customerAzamanId']?.toString() ??
          customer?['azamanId']?.toString(),
      customerUsername: customer?['username']?.toString(),
      customerProfilePictureUrl: customer?['profilePictureUrl']?.toString(),
      businessName: business?['businessName']?.toString(),
      reservationRef: reservation?['reservationRef'] as String? ?? '',
      status: reservation?['status'] as String? ?? '',
      checkedInAt: reservation?['checkedInAt'] != null
          ? _toDate(reservation!['checkedInAt'])
          : null,
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

  /// The passenger's name as they show it, and the name on their ID (sent
  /// only when they hold a booking with this business).
  final String? displayName;
  final String? legalName;
  final bool idVerified;

  /// Their upcoming trips with this business (boarding by ID check).
  final List<TransitPassengerBooking> transitBookings;

  /// False when the business boards by QR code only.
  final bool allowIdCheck;

  const AzamanIdSearchResult({
    required this.customerId,
    required this.username,
    required this.azamanId,
    this.profilePictureUrl,
    required this.reservations,
    this.displayName,
    this.legalName,
    this.idVerified = false,
    this.transitBookings = const [],
    this.allowIdCheck = true,
  });

  String get shownName =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : username;

  /// The passenger as staff check them, for a booking that carries none.
  PassengerIdCard get card => PassengerIdCard(
    azamanId: azamanId,
    username: username,
    displayName: displayName,
    legalName: legalName,
    profilePictureUrl: profilePictureUrl,
    idVerified: idVerified,
  );

  factory AzamanIdSearchResult.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? {};
    final reservationsList = json['reservations'] as List? ?? [];
    final trips = json['transitBookings'] as List? ?? const [];
    final policy = json['boardingPolicy'];
    return AzamanIdSearchResult(
      customerId: customer['id']?.toString() ?? '',
      username: customer['username']?.toString() ?? 'Unknown',
      azamanId: customer['azamanId']?.toString() ?? '',
      profilePictureUrl: customer['profilePictureUrl']?.toString(),
      reservations: reservationsList
          .map((r) => SearchReservation.fromJson(r as Map<String, dynamic>))
          .toList(),
      displayName: customer['displayName']?.toString(),
      legalName: customer['legalName']?.toString(),
      idVerified: customer['idVerified'] == true,
      transitBookings: trips
          .whereType<Map>()
          .map(
            (t) =>
                TransitPassengerBooking.fromJson(Map<String, dynamic>.from(t)),
          )
          .toList(growable: false),
      allowIdCheck: !(policy is Map && policy['allowIdCheck'] == false),
    );
  }
}

// ── ID-CHECK BOARDING (beside the passenger's QR) ────────────────────────────

/// What staff check a passenger against: the account photo, AZM-ID and
/// names. [legalName] is the name on their ID.
class PassengerIdCard {
  final String azamanId;
  final String? username;
  final String? displayName;
  final String? legalName;
  final String? profilePictureUrl;
  final bool idVerified;

  const PassengerIdCard({
    required this.azamanId,
    this.username,
    this.displayName,
    this.legalName,
    this.profilePictureUrl,
    this.idVerified = false,
  });

  String get shownName => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!
      : ((username?.trim().isNotEmpty ?? false) ? username! : azamanId);

  factory PassengerIdCard.fromJson(Map<String, dynamic> json) =>
      PassengerIdCard(
        azamanId: json['azamanId']?.toString() ?? '',
        username: json['username']?.toString(),
        displayName: json['displayName']?.toString(),
        legalName: json['legalName']?.toString(),
        profilePictureUrl: json['profilePictureUrl']?.toString(),
        idVerified: json['idVerified'] == true,
      );
}

/// One of a passenger's trips with this business, as staff see it when
/// they look the passenger up by AZM-ID.
class TransitPassengerBooking {
  final String id;
  final String bookingRef;
  final String status;
  final String origin;
  final String destination;
  final DateTime? departureAt;
  final List<String> seatIds;
  final double amountUsdc;

  /// HELD, PAID_OUT, REPORTED, REFUNDED or UNPAID.
  final String payment;
  final PassengerIdCard? passenger;
  final String? boardingMethod;
  final DateTime? boardedAt;

  /// Staff may board this passenger by ID check now (CONFIRMED, inside the
  /// boarding window, and the business allows it).
  final bool canBoardById;
  final DateTime? boardingOpensAt;
  final DateTime? boardingClosesAt;

  const TransitPassengerBooking({
    required this.id,
    required this.bookingRef,
    required this.status,
    required this.origin,
    required this.destination,
    required this.amountUsdc,
    this.departureAt,
    this.seatIds = const [],
    this.payment = 'UNPAID',
    this.passenger,
    this.boardingMethod,
    this.boardedAt,
    this.canBoardById = false,
    this.boardingOpensAt,
    this.boardingClosesAt,
  });

  bool get isPaid =>
      payment == 'HELD' || payment == 'PAID_OUT' || payment == 'REPORTED';
  bool get isWaiting => status.toUpperCase() == 'CONFIRMED';
  bool get isOnBoard => status.toUpperCase() == 'IN_PROGRESS';

  factory TransitPassengerBooking.fromJson(Map<String, dynamic> json) {
    DateTime? d(Object? v) => v == null ? null : DateTime.tryParse('$v');
    final seats = json['seats'] as List? ?? const [];
    final passenger = json['passenger'];
    final boarding = json['boarding'];
    final window = json['boardingWindow'];
    return TransitPassengerBooking(
      id: json['id']?.toString() ?? '',
      bookingRef: json['bookingRef']?.toString() ?? '',
      status: json['status']?.toString() ?? 'CONFIRMED',
      origin: json['origin']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      departureAt: d(json['departureAt']),
      seatIds: seats
          .map((s) => s is Map ? s['seatId']?.toString() : null)
          .whereType<String>()
          .toList(growable: false),
      amountUsdc: _toDouble(json['amountUsdc']),
      payment: json['payment']?.toString() ?? 'UNPAID',
      passenger: passenger is Map
          ? PassengerIdCard.fromJson(Map<String, dynamic>.from(passenger))
          : null,
      boardingMethod: boarding is Map ? boarding['method']?.toString() : null,
      boardedAt: boarding is Map ? d(boarding['at']) : null,
      canBoardById: json['canBoardById'] == true,
      boardingOpensAt: window is Map ? d(window['opensAt']) : null,
      boardingClosesAt: window is Map ? d(window['closesAt']) : null,
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

  /// Present when the seats were paid in the same request (wallet pay):
  /// what left the passenger's wallet, fare plus booking fee.
  final double? paidTotalUsdc;
  final double? paidFeeUsdc;

  const BookSeatResult({
    required this.success,
    required this.bookingId,
    required this.bookingRef,
    required this.seatIds,
    required this.totalFare,
    required this.status,
    this.paidTotalUsdc,
    this.paidFeeUsdc,
  });

  bool get paid => paidTotalUsdc != null;

  factory BookSeatResult.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>? ?? {};
    final payment = json['payment'] as Map<String, dynamic>?;
    return BookSeatResult(
      success: json['success'] == true,
      bookingId: booking['id'] as String? ?? '',
      bookingRef: booking['bookingRef'] as String? ?? '',
      seatIds:
          (json['seatIds'] as List?)?.map((s) => s.toString()).toList() ?? [],
      totalFare: _toDouble(json['totalFare']),
      status: booking['status'] as String? ?? 'PENDING',
      paidTotalUsdc: payment == null ? null : _toDouble(payment['totalUsdc']),
      paidFeeUsdc: payment == null ? null : _toDouble(payment['feeUsdc']),
    );
  }
}

// ── WALLET PAY QUOTE ─────────────────────────────────────────────────────────

/// What booking these seats with wallet pay charges, from
/// GET /marketplace/transit/trips/:id/quote — the same seat pricing and fee
/// function the booking uses, so the dock shows exactly what will leave the
/// wallet.
class TransitPaymentQuote {
  final List<String> seatIds;
  final double fareUsdc;
  final double feeUsdc;
  final double feePct;
  final double totalUsdc;
  final double availableUsdc;
  final bool canPay;

  const TransitPaymentQuote({
    required this.seatIds,
    required this.fareUsdc,
    required this.feeUsdc,
    required this.feePct,
    required this.totalUsdc,
    required this.availableUsdc,
    required this.canPay,
  });

  /// What the wallet is short by, or zero.
  double get shortfallUsdc =>
      totalUsdc > availableUsdc ? totalUsdc - availableUsdc : 0;

  factory TransitPaymentQuote.fromJson(Map<String, dynamic> json) =>
      TransitPaymentQuote(
        seatIds:
            (json['seatIds'] as List?)?.map((s) => s.toString()).toList() ??
            const [],
        fareUsdc: _toDouble(json['fareUsdc']),
        feeUsdc: _toDouble(json['feeUsdc']),
        feePct: _toDouble(json['feePct']),
        totalUsdc: _toDouble(json['totalUsdc']),
        availableUsdc: _toDouble(json['availableUsdc']),
        canPay: json['canPay'] == true,
      );
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

// ── PASSENGER TRIPS ──────────────────────────────────────────────────────────

/// One of the passenger's transit bookings, from GET /transit/bookings.
class TransitBookingSummary {
  final String id;
  final String bookingRef;
  final String status;
  final String origin;
  final String destination;
  final DateTime? departureAt;
  final double amountUsdc;
  final double feeUsdc;
  final String? operatorName;
  final String? boardingMethod;
  final DateTime? boardedAt;

  /// When the passenger confirmed an ID-check boarding ("That was me").
  final DateTime? boardingConfirmedAt;

  /// Where the fare is: HELD, PAID_OUT, REPORTED, REFUNDED or UNPAID.
  final String? payment;

  const TransitBookingSummary({
    required this.id,
    required this.bookingRef,
    required this.status,
    required this.origin,
    required this.destination,
    required this.amountUsdc,
    this.feeUsdc = 0,
    this.departureAt,
    this.operatorName,
    this.boardingMethod,
    this.boardedAt,
    this.boardingConfirmedAt,
    this.payment,
  });

  /// Paid and waiting to board: the boarding QR applies.
  bool get canShowBoardingQr => status.toUpperCase() == 'CONFIRMED';

  bool get boardedByIdCheck => boardingMethod == 'ID_CHECK';

  /// Staff boarded this passenger after an ID check, the fare is still held,
  /// and the passenger has not said whether it was them.
  bool get awaitsBoardingAnswer =>
      boardedByIdCheck &&
      boardingConfirmedAt == null &&
      payment == 'HELD' &&
      const {'IN_PROGRESS', 'COMPLETED'}.contains(status.toUpperCase());

  bool get isReported => payment == 'REPORTED';

  factory TransitBookingSummary.fromJson(Map<String, dynamic> json) {
    final business = json['businessProfile'] as Map<String, dynamic>?;
    final metadata = json['metadata'];
    final boarding = metadata is Map ? metadata['boarding'] : null;
    return TransitBookingSummary(
      id: json['id']?.toString() ?? '',
      bookingRef: json['bookingRef']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      origin: json['pickupAddress']?.toString() ?? '',
      destination: json['dropoffAddress']?.toString() ?? '',
      departureAt: json['scheduledAt'] != null
          ? DateTime.tryParse(json['scheduledAt'].toString())
          : null,
      amountUsdc: _toDouble(json['amountUsdc']),
      feeUsdc: _toDouble(json['feeUsdc']),
      operatorName: business?['businessName']?.toString(),
      boardingMethod: boarding is Map ? boarding['method']?.toString() : null,
      boardedAt: boarding is Map && boarding['at'] != null
          ? DateTime.tryParse('${boarding['at']}')
          : null,
      boardingConfirmedAt:
          boarding is Map && boarding['passengerConfirmedAt'] != null
          ? DateTime.tryParse('${boarding['passengerConfirmedAt']}')
          : null,
      payment: json['payment']?.toString(),
    );
  }
}

/// The passenger's signed boarding code for one booking, from
/// GET /marketplace/transit/bookings/:id/checkin-qr. Valid inside the
/// boarding window (an hour either side of departure), each code for at
/// most 30 minutes.
class TransitBoardingCode {
  final String qrPayload;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? expiresAt;

  const TransitBoardingCode({
    required this.qrPayload,
    this.validFrom,
    this.validUntil,
    this.expiresAt,
  });

  factory TransitBoardingCode.fromJson(Map<String, dynamic> json) {
    DateTime? d(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return TransitBoardingCode(
      qrPayload: json['qrPayload']?.toString() ?? '',
      validFrom: d(json['validFrom']),
      validUntil: d(json['validUntil']),
      expiresAt: d(json['expiresAt']),
    );
  }
}

// ── RESERVATIONS (stays and tables) ──────────────────────────────────────────

/// One of the customer's reservations, from GET /reservations/me: a hotel
/// stay or a table. The check-in QR (CheckInQrScreen) applies from a day
/// before it starts until it ends, while it is CONFIRMED.
class ReservationSummary {
  final String id;
  final String reservationRef;
  final String status;
  final DateTime? start;
  final DateTime? end;
  final int partySize;
  final double amountUsdc;
  final String businessName;
  final String? logoUrl;
  final String? category;
  final String? bizId;

  const ReservationSummary({
    required this.id,
    required this.reservationRef,
    required this.status,
    required this.businessName,
    this.start,
    this.end,
    this.partySize = 1,
    this.amountUsdc = 0,
    this.logoUrl,
    this.category,
    this.bizId,
  });

  /// Nights for a stay; 0 for a same-day booking (a table).
  int get nights {
    if (start == null || end == null) return 0;
    final a = DateTime(start!.year, start!.month, start!.day);
    final b = DateTime(end!.year, end!.month, end!.day);
    return b.difference(a).inDays.clamp(0, 365);
  }

  bool get isStay => nights > 0 || category == 'HOSPITALITY';

  bool get isActive => const {
    'PENDING',
    'CONFIRMED',
    'CHECKED_IN',
  }.contains(status.toUpperCase());

  bool canShowCheckInQr(DateTime now) =>
      status.toUpperCase() == 'CONFIRMED' &&
      start != null &&
      end != null &&
      !now.isBefore(start!.subtract(const Duration(hours: 24))) &&
      now.isBefore(end!);

  factory ReservationSummary.fromJson(Map<String, dynamic> json) {
    final business = json['businessProfile'];
    DateTime? d(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return ReservationSummary(
      id: json['id']?.toString() ?? '',
      reservationRef: json['reservationRef']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      start: d(json['startDatetime']),
      end: d(json['endDatetime']),
      partySize: (json['partySize'] as num?)?.toInt() ?? 1,
      amountUsdc: _toDouble(json['amountUsdc']),
      businessName: business is Map
          ? (business['businessName']?.toString() ?? 'Reservation')
          : 'Reservation',
      logoUrl: business is Map ? business['logoUrl']?.toString() : null,
      category: business is Map ? business['category']?.toString() : null,
      bizId: business is Map ? business['bizId']?.toString() : null,
    );
  }
}
