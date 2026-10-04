// =============================================================================
// AZAMAN — MARKETPLACE DISCOVERY SNAPSHOT
//
// One derived snapshot the portal renders from. It re-derives only when one
// of its inputs changes; the clock is sampled when the snapshot is built so
// no widget reads `DateTime.now()` inside `build`.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';

/// Injectable clock. Override in tests to pin "open now" derivations.
final discoveryClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final discoverySnapshotProvider = Provider<DiscoverySnapshot>((ref) {
  final search = ref.watch(businessSearchProvider);
  final featured = ref.watch(featuredBusinessesProvider);
  final nearby = ref.watch(nearbySearchProvider);
  final saved = ref.watch(savedBusinessesProvider);
  final now = ref.watch(discoveryClockProvider)();

  Map<String, double>? distances;
  if (nearby.locations.isNotEmpty) {
    distances = {};
    for (final loc in nearby.locations) {
      final d = loc.distanceKm;
      if (d == null) continue;
      final prev = distances[loc.businessProfileId];
      // A business with several locations is as near as its nearest one.
      if (prev == null || d < prev) distances[loc.businessProfileId] = d;
    }
    if (distances.isEmpty) distances = null;
  }

  return DiscoverySnapshot(
    catalog: search.results,
    featured: featured,
    distanceKmByBusinessId: distances,
    savedBizIds: saved,
    now: now,
  );
});