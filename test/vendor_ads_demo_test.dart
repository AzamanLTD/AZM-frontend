// Unit test: verifies /ads/mine demo seed data has the fields that
// trade_provider.dart's fetchMyAds() expects, so vendor dashboard ad cards
// will render in demo mode (was returning emptyData() before the fix).
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:azaman/data/demo_seed_data.dart';

void main() {
  test('/ads/mine demo seed returns 3 ads with required fields', () {
    final result = DemoSeedData.myAds();
    final ads = result['ads'] as List;
    expect(ads.length, 3, reason: 'Expected 3 demo vendor ads');

    for (final ad in ads) {
      expect(ad['id'], isNotNull, reason: 'Ad missing id');
      expect(ad['type'], isNotNull, reason: 'Ad missing type');
      expect(ad['pricePerUSD'], isNotNull, reason: 'Ad missing pricePerUSD');
      expect(ad['minLimit'], isNotNull, reason: 'Ad missing minLimit');
      expect(ad['maxLimit'], isNotNull, reason: 'Ad missing maxLimit');
      expect(ad['paymentMethod'], isNotNull, reason: 'Ad missing paymentMethod');
      expect(ad['status'], isNotNull, reason: 'Ad missing status');
    }

    // Verify at least one SELL and one BUY
    final types = ads.map((a) => a['type']).toSet();
    expect(types.contains('SELL'), isTrue);
    expect(types.contains('BUY'), isTrue);

    // Verify at least one ACTIVE ad
    final statuses = ads.map((a) => a['status']).toSet();
    expect(statuses.contains('ACTIVE'), isTrue);

    // Verify the JSON round-trips (what apiClient.get would return after jsonDecode)
    final jsonStr = json.encode(result);
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    final decodedAds = decoded['ads'] as List;
    expect(decodedAds.length, 3);
  });
}
