import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/marketplace/nearby_map_markers.dart';

/// G2/G3 — category-correct map markers. The old builder resolved EVERY
/// location to 'OTHER' (a literal `'OTHER' : 'OTHER'` ternary), so all pins
/// rendered the same hue. The specs derive hue from the REAL embedded
/// category color; unknown categories degrade to the neutral default, and
/// the order is preserved (the map never silently disagrees with the
/// distance-ordered list).

BusinessLocation _loc(String id, String? category, {double? distanceKm}) =>
    BusinessLocation.fromJson({
      'id': id,
      'businessProfileId': 'bp-$id',
      'label': 'Branch $id',
      'address': 'Accra',
      'latitude': 5.56,
      'longitude': -0.19,
      'galleryUrls': <String>[],
      'isPrimary': true,
      'isActive': true,
      if (distanceKm != null) 'distanceKm': distanceKm,
      if (category != null)
        'businessProfile': {'id': 'bp-$id', 'category': category},
    });

void main() {
  test('markers carry the hue of their REAL category color', () {
    final specs = buildNearbyMarkerSpecs([
      _loc('food', 'FOOD_BEVERAGE'),
      _loc('retail', 'RETAIL'),
      _loc('logistics', 'LOGISTICS'),
      _loc('hospitality', 'HOSPITALITY'),
    ]);

    expect(specs.length, 4);
    // FOOD_BEVERAGE is amber-hued in the app palette — the spec must
    // carry the SAME hue the category chip paints, so the pin color and
    // the row color can never disagree.
    final expectedFoodHue = HSVColor.fromColor(
      BusinessCategories.fromWire('FOOD_BEVERAGE').color,
    ).hue;
    final expectedRetailHue = HSVColor.fromColor(
      BusinessCategories.fromWire('RETAIL').color,
    ).hue;
    final expectedLogisticsHue = HSVColor.fromColor(
      BusinessCategories.fromWire('LOGISTICS').color,
    ).hue;
    final expectedHospitalityHue = HSVColor.fromColor(
      BusinessCategories.fromWire('HOSPITALITY').color,
    ).hue;

    expect(specs[0].hue, expectedFoodHue);
    expect(specs[1].hue, expectedRetailHue);
    expect(specs[2].hue, expectedLogisticsHue);
    expect(specs[3].hue, expectedHospitalityHue);

    // Audit wire preserved.
    expect(specs.map((s) => s.categoryWire), [
      'FOOD_BEVERAGE',
      'RETAIL',
      'LOGISTICS',
      'HOSPITALITY',
    ]);
  });

  test('unknown, null or empty categories never GUESS a real category '
      'color', () {
    final specs = buildNearbyMarkerSpecs([
      _loc('unknown', 'NOT_A_REAL_CATEGORY'),
      _loc('null-cat', null),
      _loc('empty-cat', ''),
    ]);

    // An UNRECOGNIZED wire resolves exactly the way the Near You row
    // resolves it (BusinessCategories.fromWire → OTHER), so the pin and
    // the row can never disagree about an odd payload.
    final otherHue = HSVColor.fromColor(
      BusinessCategories.fromWire('NOT_A_REAL_CATEGORY').color,
    ).hue;
    expect(
      specs[0].hue,
      otherHue,
      reason: 'unknown wire must match the row treatment (OTHER)',
    );
    expect(specs[0].categoryWire, 'NOT_A_REAL_CATEGORY');

    // NO wire at all (legacy row) → the neutral default, never a guess
    // dressed as a category color.
    expect(specs[1].hue, kNearbyMarkerFallbackHue);
    expect(specs[1].categoryWire, isNull);
    expect(specs[2].hue, kNearbyMarkerFallbackHue);
    expect(
      specs[2].categoryWire,
      isNull,
      reason: 'a whitespace category is not a category',
    );
  });

  test('order is preserved — the map never re-sorts the server feed', () {
    final specs = buildNearbyMarkerSpecs([
      _loc('near', 'RETAIL', distanceKm: 0.2),
      _loc('far', 'RETAIL', distanceKm: 9.9),
      _loc('mid', 'RETAIL', distanceKm: 4.5),
    ]);
    expect(specs.map((s) => s.id), [
      'near',
      'far',
      'mid',
    ], reason: 'distance ordering is the SERVER contract');
    expect(specs.first.distanceKm, 0.2);
  });

  test('markersFromSpecs keeps spec identity and routes taps', () {
    final specs = buildNearbyMarkerSpecs([_loc('a', 'RETAIL')]);
    NearbyMarkerSpec? tapped;
    final markers = markersFromSpecs(specs, onTap: (spec) => tapped = spec);

    expect(markers.length, 1);
    final marker = markers.single;
    expect(marker.markerId.value, 'a');
    expect(marker.position.latitude, 5.56);
    expect(marker.position.longitude, -0.19);

    marker.onTap!.call();
    expect(tapped?.id, 'a');
  });
}
