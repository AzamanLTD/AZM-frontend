// lib/widgets/marketplace/nearby_map_markers.dart
// =============================================================================
// AZAMAN — NEAR YOU MAP MARKERS (Programme G2/G3)
//
// Category-correct marker specs for the Marketplace map.
//
// The old marker builder resolved EVERY location to 'OTHER' (a literal
// `'OTHER' : 'OTHER'` ternary), so every pin rendered the same gray hue —
// the "correct category markers" defect. The nearby payload embeds the
// owning profile's real category on every row (BusinessLocation
// .businessCategory), and this builder derives each pin's hue from that
// REAL category color:
//
//   FOOD_BEVERAGE → amber · RETAIL → green · LOGISTICS → blue
//   HOSPITALITY   → violet · REAL_ESTATE → violet · unknown → neutral
//
// The spec list is a pure, synchronous function of the payload (no
// platform channels), so the category-color contract is unit-testable
// without the Google Maps plugin. The thin [markersFromSpecs] adapter then
// turns specs into platform [Marker]s.
// =============================================================================

import 'package:azaman/models/business_models.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single category-correct map pin, derived only from the payload.
class NearbyMarkerSpec {
  const NearbyMarkerSpec({
    required this.id,
    required this.position,
    required this.hue,
    this.categoryWire,
    this.distanceKm,
  });

  /// Stable marker identity (the location row id).
  final String id;

  final LatLng position;

  /// Hue of the owning business's REAL category color (HSV hue), or the
  /// neutral fallback hue when the row carries no category (legacy rows).
  final double hue;

  /// The raw category wire the hue was derived from (audit/testing).
  final String? categoryWire;

  final double? distanceKm;
}

/// Neutral hue for rows with no (or unrecognized) category — the
/// platform's DEFAULT marker hue. An uncategorized pin is visibly
/// "default", never a guess dressed as a category color.
const double kNearbyMarkerFallbackHue = 0.0;

/// Builds category-correct marker specs from nearby payload rows.
///
/// Pure and synchronous: same rows → same specs (order preserved, one spec
/// per row). Rows are NEVER re-ordered here — the nearby feed is
/// distance-sorted by the server and the map must not silently disagree
/// with the list.
List<NearbyMarkerSpec> buildNearbyMarkerSpecs(
  List<BusinessLocation> locations,
) {
  return locations
      .map((loc) {
        final wire = loc.businessCategory?.trim().isEmpty == true
            ? null
            : loc.businessCategory?.trim();
        final double hue;
        if (wire == null) {
          hue = kNearbyMarkerFallbackHue;
        } else {
          final category = BusinessCategories.fromWire(wire);
          hue = HSVColor.fromColor(category.color).hue;
        }
        return NearbyMarkerSpec(
          id: loc.id,
          position: LatLng(loc.latitude, loc.longitude),
          hue: hue,
          categoryWire: wire,
          distanceKm: loc.distanceKm,
        );
      })
      .toList(growable: false);
}

/// Thin adapter from specs to platform markers. Marker taps route through
/// [onTap] with the originating spec so callers keep the full row facts.
Set<Marker> markersFromSpecs(
  List<NearbyMarkerSpec> specs, {
  void Function(NearbyMarkerSpec spec)? onTap,
}) {
  return {
    for (final spec in specs)
      Marker(
        markerId: MarkerId(spec.id),
        position: spec.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(spec.hue),
        onTap: onTap == null ? null : () => onTap(spec),
      ),
  };
}
