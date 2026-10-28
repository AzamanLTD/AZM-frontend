import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';

/// G2/G3 — BusinessLocation must carry the embedded-profile facts that the
/// real `/business/search/nearby` payload ships on every row (category,
/// bizId, name, logo, verified) so the Near You rows and the category-
/// correct map markers render authoritative values — while legacy rows
/// without the embedding degrade to nulls, never guesses.

Map<String, dynamic> _rowWithProfile(Map<String, dynamic> profile) => {
  'id': 'loc-1',
  'businessProfileId': 'bp-1',
  'label': 'Main branch',
  'address': 'Osu, Accra',
  'latitude': 5.56,
  'longitude': -0.19,
  'galleryUrls': <String>[],
  'isPrimary': true,
  'isActive': true,
  'distanceKm': 1.23,
  'businessProfile': profile,
};

Map<String, dynamic> _legacyRow() => {
  'id': 'loc-1',
  'businessProfileId': 'bp-1',
  'label': 'Main branch',
  'address': 'Osu, Accra',
  'latitude': 5.56,
  'longitude': -0.19,
  'galleryUrls': <String>[],
  'isPrimary': true,
  'isActive': true,
};

void main() {
  test('parses the full embedded profile from a nearby row', () {
    final loc = BusinessLocation.fromJson(
      _rowWithProfile({
        'id': 'bp-1',
        'bizId': 'BIZ-RESTAURANT-1',
        'businessName': "Chef Abby's",
        'category': 'FOOD_BEVERAGE',
        'logoUrl': 'https://example.com/logo.png',
        'isVerified': true,
        'averageRating': 4.7,
        'totalEscrows': 340,
      }),
    );

    expect(loc.businessCategory, 'FOOD_BEVERAGE');
    expect(loc.bizId, 'BIZ-RESTAURANT-1');
    expect(loc.businessName, "Chef Abby's");
    expect(loc.businessLogoUrl, 'https://example.com/logo.png');
    expect(loc.businessVerified, isTrue);
    expect(loc.distanceKm, 1.23);
  });

  test('verified=false is preserved (not collapsed to null)', () {
    final loc = BusinessLocation.fromJson(
      _rowWithProfile({
        'id': 'bp-1',
        'bizId': 'BIZ-X',
        'businessName': 'Kiosk',
        'category': 'RETAIL',
        'isVerified': false,
      }),
    );
    expect(loc.businessVerified, isFalse);
  });

  test('legacy row without an embedding degrades to nulls — never guesses', () {
    final loc = BusinessLocation.fromJson(_legacyRow());
    expect(loc.businessCategory, isNull);
    expect(loc.bizId, isNull);
    expect(loc.businessName, isNull);
    expect(loc.businessLogoUrl, isNull);
    expect(loc.businessVerified, isNull);
  });

  test('empty-string embedded values degrade to nulls', () {
    final loc = BusinessLocation.fromJson(
      _rowWithProfile({'id': 'bp-1', 'category': '', 'businessName': ''}),
    );
    expect(
      loc.businessCategory,
      isNull,
      reason: 'an empty category must not render as a category',
    );
    expect(loc.businessName, isNull);
  });

  test('non-map embedding is ignored, not cast-crashed', () {
    final raw = _legacyRow()..['businessProfile'] = 'garbage-string';
    final loc = BusinessLocation.fromJson(raw);
    expect(loc.businessCategory, isNull);
    expect(loc.bizId, isNull);
  });

  test('bizId from the row root is honoured when the embedding omits it', () {
    final raw = _rowWithProfile({'id': 'bp-1', 'category': 'RETAIL'})
      ..['bizId'] = 'BIZ-TOP-LEVEL';
    final loc = BusinessLocation.fromJson(raw);
    expect(loc.bizId, 'BIZ-TOP-LEVEL');
  });
}
