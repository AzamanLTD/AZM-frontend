import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/hotel/stay_decision.dart';

void main() {
  final d1 = DateTime(2026, 10, 10);
  final d3 = DateTime(2026, 10, 12);

  test('nights and completeness derive from dates + room', () {
    const none = StayDecision();
    expect(none.nights, isNull);
    expect(none.datesChosen, isFalse);
    expect(none.complete, isFalse);

    final dated = StayDecision(checkIn: d1, checkOut: d3);
    expect(dated.nights, 2);
    expect(dated.datesChosen, isTrue);
    expect(dated.complete, isFalse);
    expect(dated.copyWith(roomId: 'r1').complete, isTrue);
  });

  test('zero-night range does not count as chosen', () {
    expect(StayDecision(checkIn: d1, checkOut: d1).datesChosen, isFalse);
  });

  test('stepFor walks Dates → Room → Review → Confirmed', () {
    expect(const StayDecision().stepFor(confirmed: false), StayStep.dates);
    expect(StayDecision(checkIn: d1, checkOut: d3).stepFor(confirmed: false), StayStep.room);
    expect(StayDecision(checkIn: d1, checkOut: d3, roomId: 'r').stepFor(confirmed: false), StayStep.review);
    expect(const StayDecision().stepFor(confirmed: true), StayStep.confirmed);
    expect(StayStep.review.label, 'Review');
  });

  test('copyWith clears explicitly and is value-equal', () {
    final full = StayDecision(checkIn: d1, checkOut: d3, guests: 2, roomId: 'r');
    expect(full.copyWith(clearRoom: true).roomId, isNull);
    expect(full.copyWith(clearDates: true).nights, isNull);
    expect(full.copyWith(), equals(full));
    expect(full.copyWith(guests: 3), isNot(equals(full)));
  });
}