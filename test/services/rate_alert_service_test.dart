import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/rate_alert_service.dart';

void main() {
  test('RateAlert defaults missing pair metadata to USDC_GHS', () {
    final alert = RateAlert.fromJson({
      'id': 'a1',
      'targetRate': 13.5,
      'direction': 'ABOVE',
      'status': 'ACTIVE',
      'createdAt': '2026-09-04T10:00:00.000Z',
    });

    expect(alert.ratePair, canonicalRatePair);
  });

  test('RateAlert preserves explicit legacy pair metadata', () {
    final alert = RateAlert.fromJson({
      'id': 'legacy',
      'targetRate': 13.5,
      'direction': 'BELOW',
      'ratePair': 'USD_GHS',
      'status': 'ACTIVE',
      'createdAt': '2026-09-04T10:00:00.000Z',
    });

    expect(alert.ratePair, 'USD_GHS');
    expect(jsonEncode({'ratePair': alert.ratePair}), contains('USD_GHS'));
  });
}
