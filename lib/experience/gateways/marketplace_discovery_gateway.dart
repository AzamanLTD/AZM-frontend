// =============================================================================
// AZAMAN — GATEWAYS: MARKETPLACE DISCOVERY
//
// Wraps the existing business providers behind one typed surface so the
// portal never calls `BusinessService` directly, and so demo/preview adapters
// are possible. `supportedSignals` is the capability truth: a widget hides a
// signal that is not in the set — it never fabricates one.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'az_gateway_result.dart';

enum DiscoverySignal {
  openNow,
  nearby,
  topRated,
  recentlyAdded,
  departingSoon,
  availableTonight,
}

/// Immutable snapshot the portal renders from. Every list may be empty; the
/// UI renders nothing for empty lists (no fake richness).
class DiscoverySnapshot {
  /// `businessSearchProvider.results` — the whole catalog while on the portal.
  final List<BusinessProfile> catalog;

  /// `featuredBusinessesProvider`.
  final List<BusinessProfile> featured;

  /// Distance per `BusinessProfile.id`, from `nearbySearchProvider`; null when
  /// no location result has been loaded.
  final Map<String, double>? distanceKmByBusinessId;

  /// `savedBusinessesProvider` (keyed by `bizId`).
  final Set<String> savedBizIds;

  /// The clock the snapshot was derived with. Widgets never call
  /// `DateTime.now()` in `build`.
  final DateTime now;

  const DiscoverySnapshot({
    required this.catalog,
    required this.featured,
    required this.distanceKmByBusinessId,
    required this.savedBizIds,
    required this.now,
  });

  double? distanceOf(BusinessProfile b) => distanceKmByBusinessId?[b.id];
}

abstract interface class MarketplaceDiscoveryGateway {
  /// Which signals this build can compute truthfully.
  Set<DiscoverySignal> get supportedSignals;

  Future<AzGatewayResult<void>> refreshCatalog();
}

/// Real adapter over the EXISTING Riverpod business providers.
class RiverpodMarketplaceDiscoveryGateway implements MarketplaceDiscoveryGateway {
  RiverpodMarketplaceDiscoveryGateway(this.ref);
  final Ref ref;

  @override
  Set<DiscoverySignal> get supportedSignals => const {
        // Derived from BusinessLocation.operatingHours via BusinessHours.
        DiscoverySignal.openNow,
        // nearbySearchProvider distances.
        DiscoverySignal.nearby,
        // averageRating with enough reviews to mean something.
        DiscoverySignal.topRated,
        // recentlyAdded / departingSoon / availableTonight need fields the
        // snapshot does not expose (no createdAt; trip/room data lives per
        // business). Deliberately absent — do not add a fake.
      };

  @override
  Future<AzGatewayResult<void>> refreshCatalog() async {
    try {
      await ref.read(businessSearchProvider.notifier).search('', category: null);
      return const AzOk(null);
    } catch (e) {
      return AzFailed('Could not refresh businesses', cause: e);
    }
  }
}

final marketplaceDiscoveryGatewayProvider = Provider<MarketplaceDiscoveryGateway>(
  (ref) => RiverpodMarketplaceDiscoveryGateway(ref),
);