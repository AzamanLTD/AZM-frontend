/// Stay decision state (Overhaul 03 §4.1) — UI-only.
///
/// Records what the guest picked (dates, guests, room). Authoritative price
/// and availability still come from `hotelMarketplaceProvider`; this object
/// only drives what is shown and when the summary dock appears.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class StayDecision {
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int guests;
  final String? roomId;

  const StayDecision({this.checkIn, this.checkOut, this.guests = 1, this.roomId});

  int? get nights => (checkIn != null && checkOut != null)
      ? checkOut!.difference(checkIn!).inDays
      : null;

  bool get datesChosen => (nights ?? 0) > 0;
  bool get complete => datesChosen && roomId != null;

  /// §4.6 — the step the dossier indicator should highlight.
  StayStep stepFor({required bool confirmed}) {
    if (confirmed) return StayStep.confirmed;
    if (!datesChosen) return StayStep.dates;
    if (roomId == null) return StayStep.room;
    return StayStep.review;
  }

  StayDecision copyWith({
    DateTime? checkIn,
    DateTime? checkOut,
    int? guests,
    String? roomId,
    bool clearRoom = false,
    bool clearDates = false,
  }) =>
      StayDecision(
        checkIn: clearDates ? null : (checkIn ?? this.checkIn),
        checkOut: clearDates ? null : (checkOut ?? this.checkOut),
        guests: guests ?? this.guests,
        roomId: clearRoom ? null : (roomId ?? this.roomId),
      );

  @override
  bool operator ==(Object other) =>
      other is StayDecision &&
      other.checkIn == checkIn &&
      other.checkOut == checkOut &&
      other.guests == guests &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(checkIn, checkOut, guests, roomId);
}

/// Dates → Room → Review → Confirmed (§4.6).
enum StayStep { dates, room, review, confirmed }

extension StayStepLabel on StayStep {
  String get label => switch (this) {
        StayStep.dates => 'Dates',
        StayStep.room => 'Room',
        StayStep.review => 'Review',
        StayStep.confirmed => 'Confirmed',
      };
}

final stayDecisionProvider =
    StateProvider.autoDispose.family<StayDecision, String>(
  (ref, bizId) => const StayDecision(),
);