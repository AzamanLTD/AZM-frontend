import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/utils/business_hours.dart';

BusinessLocation _loc(Map<String, dynamic>? hours, {String id = 'l1'}) =>
    BusinessLocation(
      id: id,
      businessProfileId: 'b1',
      label: 'Main',
      address: '1 Street',
      latitude: 0,
      longitude: 0,
      galleryUrls: const [],
      isPrimary: true,
      isActive: true,
      operatingHours: hours,
    );

void main() {
  // Wednesday 2026-10-07.
  final wedNoon = DateTime(2026, 10, 7, 12, 0);
  final wedLate = DateTime(2026, 10, 7, 23, 30);
  final wedEarly = DateTime(2026, 10, 7, 1, 0);

  group('stateOfRange', () {
    test('normal window', () {
      expect(BusinessHours.stateOfRange('08:00-22:00', wedNoon), OpenState.open);
      expect(BusinessHours.stateOfRange('08:00-22:00', wedLate), OpenState.closed);
    });

    test('single-digit hour as in the data', () {
      expect(BusinessHours.stateOfRange('8:00-22:00', wedNoon), OpenState.open);
    });

    test('overnight window crosses midnight', () {
      expect(BusinessHours.stateOfRange('20:00-02:00', wedLate), OpenState.open);
      expect(BusinessHours.stateOfRange('20:00-02:00', wedEarly), OpenState.open);
      expect(BusinessHours.stateOfRange('20:00-02:00', wedNoon), OpenState.closed);
    });

    test('closing boundary is exclusive, opening inclusive', () {
      expect(BusinessHours.stateOfRange('12:00-13:00', wedNoon), OpenState.open);
      expect(BusinessHours.stateOfRange('11:00-12:00', wedNoon), OpenState.closed);
    });

    test('malformed → unknown', () {
      for (final bad in [null, '', 'closed', '8-22', '8:00-', '25:00-26:00', '08:60-09:00', '8:00-22:00-23:00']) {
        expect(BusinessHours.stateOfRange(bad, wedNoon), OpenState.unknown, reason: '$bad');
      }
    });
  });

  group('stateAt', () {
    test('missing day key → unknown', () {
      expect(BusinessHours.stateAt([_loc({'mon': '8:00-22:00'})], wedNoon), OpenState.unknown);
    });

    test('null hours on one location but open on another → open', () {
      final locs = [_loc(null), _loc({'wed': '8:00-22:00'}, id: 'l2')];
      expect(BusinessHours.stateAt(locs, wedNoon), OpenState.open);
    });

    test('all-null / empty hours → unknown', () {
      expect(BusinessHours.stateAt([_loc(null), _loc({})], wedNoon), OpenState.unknown);
      expect(BusinessHours.stateAt(const [], wedNoon), OpenState.unknown);
    });

    test('parseable but all closed → closed', () {
      final locs = [_loc({'wed': '8:00-11:00'}), _loc({'wed': '14:00-18:00'}, id: 'l2')];
      expect(BusinessHours.stateAt(locs, wedNoon), OpenState.closed);
    });

    test('one malformed and one closed → closed (malformed is ignored)', () {
      final locs = [_loc({'wed': 'nope'}), _loc({'wed': '14:00-18:00'}, id: 'l2')];
      expect(BusinessHours.stateAt(locs, wedNoon), OpenState.closed);
    });

    test('Sunday maps to index 0', () {
      final sun = DateTime(2026, 10, 4, 12, 0);
      expect(sun.weekday, DateTime.sunday);
      expect(BusinessHours.stateAt([_loc({'sun': '9:00-13:00'})], sun), OpenState.open);
    });
  });
}