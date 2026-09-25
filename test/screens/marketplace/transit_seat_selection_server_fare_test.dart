import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success sheet displays server-authoritative booking fare', () {
    final source = File('lib/screens/marketplace/transit_seat_selection_screen.dart').readAsStringSync();
    expect(source, contains('final total = result.totalFare;'));
    expect(source, isNot(contains('final total = _totalFare(availability, selected);')));
  });
}
