// =============================================================================
// AZAMAN — SEAT LAYOUT MODELS
//
// Structured data model for vehicle seat layouts of arbitrary complexity:
// 12-14 seat trotros, 30-seat single-deck coaches, 50+ seat double-deckers.
//
// Key design rules:
//   - SeatTier and SeatStatus are ORTHOGONAL — a Seat has both independently.
//   - Multi-deck vehicles use a List<Deck>, each with its own grid — never a
//     single flat grid with an unused deckCount field.
//   - All models are immutable and serializable (fromJson / toJson).
// =============================================================================

/// Seating tier — affects fare and visual VIP badge.
enum SeatTier {
  standard,
  vip,
  executive;

  String get label => switch (this) {
        standard => 'Standard',
        vip => 'VIP',
        executive => 'Executive',
      };

  static SeatTier fromJson(String? s) => switch (s?.toUpperCase()) {
        'VIP' => vip,
        'EXECUTIVE' => executive,
        _ => standard,
      };

  String toJson() => switch (this) {
        standard => 'STANDARD',
        vip => 'VIP',
        executive => 'EXECUTIVE',
      };
}

/// Booking status of a seat — comes from the backend.
/// Selection (user picking a seat) is local UI state layered on top of
/// `available`, not a separate backend status.
enum SeatBookStatus {
  available,
  booked,
  blocked,
  reserved;

  /// Whether this status prevents the user from tapping the seat.
  bool get isTappable => this == available;

  String get label => switch (this) {
        available => 'Available',
        booked => 'Occupied',
        blocked => 'Not for sale',
        reserved => 'Held for another passenger',
      };

  static SeatBookStatus fromJson(String? s) => switch (s?.toUpperCase()) {
        'BOOKED' => booked,
        'OCCUPIED' => booked,
        'BLOCKED' => blocked,
        'RESERVED' => reserved,
        _ => available,
      };

  String toJson() => switch (this) {
        available => 'AVAILABLE',
        booked => 'BOOKED',
        blocked => 'BLOCKED',
        reserved => 'RESERVED',
      };
}

/// Type of a grid slot — most are seats, but layouts include aisles,
/// driver position, doors, etc.
enum SlotType {
  seat,
  aisle,
  driver,
  door,
  restroom,
  stairs,
  luggageRack,
  empty;

  static SlotType fromJson(String? s) => switch (s?.toUpperCase()) {
        'SEAT' => seat,
        'AISLE' => aisle,
        'DRIVER' => driver,
        'DOOR' => door,
        'RESTROOM' => restroom,
        'STAIRS' => stairs,
        'LUGGAGE_RACK' => luggageRack,
        'LUGGAGE' => luggageRack,
        _ => empty,
      };

  String toJson() => switch (this) {
        seat => 'SEAT',
        aisle => 'AISLE',
        driver => 'DRIVER',
        door => 'DOOR',
        restroom => 'RESTROOM',
        stairs => 'STAIRS',
        luggageRack => 'LUGGAGE_RACK',
        empty => 'EMPTY',
      };
}

/// A single cell in the deck grid. If [type] is [SlotType.seat], the seat-
/// specific fields ([seatId], [tier], [status], [fare], [seatLabel]) are set.
/// For non-seat slots these are null/zero.
class GridSlot {
  final SlotType type;

  // Seat-only fields
  final String? seatId;
  final String? seatLabel;
  final SeatTier tier;
  final SeatBookStatus status;
  final double fare;

  // Row/col within the deck grid (0-indexed)
  final int row;
  final int col;

  const GridSlot({
    required this.type,
    required this.row,
    required this.col,
    this.seatId,
    this.seatLabel,
    this.tier = SeatTier.standard,
    this.status = SeatBookStatus.available,
    this.fare = 0,
  });

  /// Whether this slot is a seat the user can interact with.
  bool get isSeat => type == SlotType.seat;

  /// Whether the user can currently tap this seat (available status only).
  bool get isTappable => isSeat && status.isTappable;

  factory GridSlot.fromJson(Map<String, dynamic> json) {
    return GridSlot(
      type: SlotType.fromJson(json['type']?.toString()),
      row: (json['row'] as num?)?.toInt() ?? 0,
      col: (json['col'] as num?)?.toInt() ?? 0,
      seatId: json['seatId']?.toString(),
      seatLabel: json['seatLabel']?.toString(),
      tier: SeatTier.fromJson(json['tier']?.toString()),
      status: SeatBookStatus.fromJson(json['status']?.toString()),
      fare: (json['fare'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.toJson(),
        'row': row,
        'col': col,
        if (seatId != null) 'seatId': seatId,
        if (seatLabel != null) 'seatLabel': seatLabel,
        'tier': tier.toJson(),
        'status': status.toJson(),
        'fare': fare,
      };

  GridSlot copyWith({
    SlotType? type,
    int? row,
    int? col,
    String? seatId,
    String? seatLabel,
    SeatTier? tier,
    SeatBookStatus? status,
    double? fare,
  }) =>
      GridSlot(
        type: type ?? this.type,
        row: row ?? this.row,
        col: col ?? this.col,
        seatId: seatId ?? this.seatId,
        seatLabel: seatLabel ?? this.seatLabel,
        tier: tier ?? this.tier,
        status: status ?? this.status,
        fare: fare ?? this.fare,
      );

  @override
  String toString() =>
      'GridSlot($type at ($row,$col)${isSeat ? ' seat=$seatId tier=$tier status=$status' : ''})';
}

/// A single deck of a vehicle — has its own grid of slots.
class Deck {
  final int deckIndex;
  final String? label;
  final List<List<GridSlot>> grid;

  const Deck({
    required this.deckIndex,
    required this.grid,
    this.label,
  });

  /// Number of rows in this deck's grid.
  int get rowCount => grid.length;

  /// Max columns across all rows (rows may have different lengths).
  int get colCount =>
      grid.isEmpty ? 0 : grid.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  /// All seat slots in this deck, flattened.
  List<GridSlot> get seats =>
      grid.expand((row) => row).where((s) => s.isSeat).toList();

  factory Deck.fromJson(Map<String, dynamic> json) {
    final gridJson = json['grid'] as List? ?? [];
    return Deck(
      deckIndex: (json['deckIndex'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString(),
      grid: gridJson.map((rowJson) {
        final rowList = rowJson as List? ?? [];
        return rowList
            .map((slot) => GridSlot.fromJson(slot as Map<String, dynamic>))
            .toList();
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deckIndex': deckIndex,
        if (label != null) 'label': label,
        'grid':
            grid.map((row) => row.map((slot) => slot.toJson()).toList()).toList(),
      };

  @override
  String toString() =>
      'Deck($deckIndex, ${rowCount}r×${colCount}c, ${seats.length} seats)';
}

/// Full vehicle layout — one or more decks, plus metadata.
class VehicleLayout {
  final String id;
  final String? vehicleType;
  final String? vehicleMake;
  final String? vehicleModel;
  final List<Deck> decks;

  const VehicleLayout({
    required this.id,
    required this.decks,
    this.vehicleType,
    this.vehicleMake,
    this.vehicleModel,
  });

  /// Total seats across all decks.
  int get totalSeats => decks.expand((d) => d.seats).length;

  /// Whether this is a multi-deck vehicle.
  bool get isMultiDeck => decks.length > 1;

  /// All seats across all decks, flattened.
  List<GridSlot> get allSeats => decks.expand((d) => d.seats).toList();

  /// Find a seat by [seatId] across all decks.
  GridSlot? findSeat(String seatId) {
    for (final deck in decks) {
      for (final row in deck.grid) {
        for (final slot in row) {
          if (slot.seatId == seatId) return slot;
        }
      }
    }
    return null;
  }

  /// Which deck index contains the given seatId.
  int? deckIndexForSeat(String seatId) {
    for (final deck in decks) {
      if (deck.seats.any((s) => s.seatId == seatId)) return deck.deckIndex;
    }
    return null;
  }

  factory VehicleLayout.fromJson(Map<String, dynamic> json) {
    final decksJson = json['decks'] as List? ?? [];
    return VehicleLayout(
      id: json['id']?.toString() ?? '',
      vehicleType: json['vehicleType']?.toString(),
      vehicleMake: json['vehicleMake']?.toString(),
      vehicleModel: json['vehicleModel']?.toString(),
      decks: decksJson
          .map((d) => Deck.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (vehicleType != null) 'vehicleType': vehicleType,
        if (vehicleMake != null) 'vehicleMake': vehicleMake,
        if (vehicleModel != null) 'vehicleModel': vehicleModel,
        'decks': decks.map((d) => d.toJson()).toList(),
      };

  @override
  String toString() =>
      'VehicleLayout($id, ${decks.length} deck${decks.length == 1 ? '' : 's'}, $totalSeats seats)';
}
