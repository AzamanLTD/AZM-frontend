// =============================================================================
// AZAMAN — MARKETPLACE RELEVANCE  (PR #142 close-out §2)
//
// The third REAL marketplace reminder signal: a real business in the
// category/world the user actually visited most recently.
//
// Truthfulness is the whole contract:
//
//   * WHERE the user was   → worldMemoryProvider (the existing, tested
//                            freshness-windowed world memory — no new store).
//   * WHAT actually exists → discoverySnapshotProvider (the existing real
//                            search/featured results — no new fetch, no
//                            invented repositories).
//
// Nothing is manufactured in between: no fake stores, no fake recency, no
// "new" claims (the data model exposes no trustworthy newness), no random
// merchant pick — featured results are considered before catalog order,
// deterministically. No fresh memory, or no real match in that category,
// means NO reminder. The deck stays a derived presentation layer.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';

/// The derived relevance signal the Home reminder deck renders:
/// "Relevant in <Category>" for a real, openable business.
class MarketplaceRelevance {
  /// The world wire the user most recently visited (e.g. `'FOOD_BEVERAGE'`).
  final String worldWire;

  /// Canonical category label for that wire (BusinessCategories.labelFor).
  final String categoryLabel;

  /// The real business the reminder names — drawn from the existing
  /// discovery snapshot, never fabricated.
  final BusinessProfile business;

  const MarketplaceRelevance({
    required this.worldWire,
    required this.categoryLabel,
    required this.business,
  });
}

/// A business can honestly be offered as a reminder destination when it
/// has the identity the storefront route needs and is not suspended.
/// KYB/verified status is deliberately NOT a criterion — an unverified
/// but open store is still a real store in a real category.
bool _openable(BusinessProfile b) =>
    b.id.isNotEmpty && b.businessName.trim().isNotEmpty && !b.isSuspended;

/// Most-recently-touched FRESH world, or null when memory is empty or
/// stale. Freshness and recency both come from the existing world-memory
/// contract (30-minute window) — nothing new is invented here.
MapEntry<String, WorldMemory>? _mostRecentFreshContext(
    Map<String, WorldMemory> memories, DateTime now) {
  MapEntry<String, WorldMemory>? best;
  for (final e in memories.entries) {
    if (!e.value.isFresh(now)) continue;
    if (best == null || e.value.touchedAt.isAfter(best.value.touchedAt)) {
      best = e;
    }
  }
  return best;
}

final marketplaceRelevanceProvider = Provider<MarketplaceRelevance?>((ref) {
  final now = ref.watch(discoveryClockProvider)();
  final context = _mostRecentFreshContext(ref.watch(worldMemoryProvider), now);
  if (context == null) return null;

  // Canonical category resolution — the same BusinessCategories utility
  // every other surface uses (wire ↔ label in one place).
  final wire = context.key;
  final categoryLabel = BusinessCategories.labelFor(wire);

  // A real business in that category, from data the app already holds.
  // Featured results first (already-curated real data), then catalog
  // order — deterministic, never random, never invented.
  final snapshot = ref.watch(discoverySnapshotProvider);
  for (final b in snapshot.featured) {
    if (b.category == wire && _openable(b)) {
      return MarketplaceRelevance(
          worldWire: wire, categoryLabel: categoryLabel, business: b);
    }
  }
  for (final b in snapshot.catalog) {
    if (b.category == wire && _openable(b)) {
      return MarketplaceRelevance(
          worldWire: wire, categoryLabel: categoryLabel, business: b);
    }
  }
  // The user visited a category with nothing real to offer — say nothing.
  return null;
});
