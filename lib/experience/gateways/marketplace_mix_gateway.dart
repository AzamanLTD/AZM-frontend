// =============================================================================
// AZAMAN — GATEWAYS: MARKETPLACE MIX (category-first, cross-store)
//
// Mirrors `marketplace_discovery_gateway.dart`: a typed surface the Mix screen
// reads through, with the CAPABILITY TRUTH declared on the gateway — the UI
// hides any signal this build cannot compute from real backend data.
//
// COMPOSITION (real endpoints only — see lib/marketplace/mix/mix_models.dart
// for the full capability matrix):
//   1. `GET /api/business/search?q=&category=<wire>` — stores in the selected
//      category, cursor-paginated (server default sort: totalEscrows desc).
//   2. `GET /api/business/<bizId>/products?limit=…` — each store's listings,
//      raw rows (carries `priceUsdc` and `isAvailable`).
// No endpoint is invented, no DTO field is guessed, no price is fabricated.
//
// NOT a Mix ranking source: the round-robin interleave across stores is
// presentation only and never masquerades as server-backed ranking.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';

/// Capabilities the Mix UI may truthfully render. A capability is only in the
/// set when a REAL backend contract backs it today.
enum MixCapability {
  /// Browse items across many stores within one category (composed fan-out).
  crossStoreCategoryBrowse,

  /// Item identity + offering business identity on every offer.
  offerIdentity,

  /// The USDC list price from the public product payloads.
  usdcListPrice,

  /// Raw availability (`isAvailable`) from the product payloads.
  availabilitySignal,

  /// Item+store interaction recording via the real
  /// `POST /api/storefront/:businessProfileId/events` (`product_tap`).
  itemStoreInteractions,
}

/// One page of stores from `GET /api/business/search`.
typedef MixStorePage = ({
  List<MixStore> stores,
  bool hasMore,
  String? nextCursor,
});

/// One store's offers from `GET /api/business/:bizId/products`.
typedef MixStoreOffers = ({
  MixStore store,
  List<MixOffer> offers,
});

abstract interface class MarketplaceMixGateway {
  /// Which capabilities this build can compute truthfully.
  Set<MixCapability> get supportedCapabilities;

  /// Stores in `category` (server wire value, e.g. `FOOD_BEVERAGE`).
  Future<MixStorePage> searchStores({
    required String category,
    int limit = 10,
    String? cursor,
  });

  /// The raw listings of one store, as offer pairs carrying the store identity.
  Future<MixStoreOffers> productsFor(MixStore store, {int limit = 50});
}

/// Real adapter over the EXISTING public marketplace endpoints.
class HttpMarketplaceMixGateway implements MarketplaceMixGateway {
  HttpMarketplaceMixGateway({BusinessService? businessService, ApiClient? apiClient})
      : _businessService = businessService ?? BusinessService(),
        _apiClient = apiClient ?? ApiClient();

  final BusinessService _businessService;
  final ApiClient _apiClient;

  @override
  Set<MixCapability> get supportedCapabilities => const {
        MixCapability.crossStoreCategoryBrowse,
        MixCapability.offerIdentity,
        MixCapability.usdcListPrice,
        MixCapability.availabilitySignal,
        MixCapability.itemStoreInteractions,
        // Deliberately absent (do not add without a real contract):
        //  - a GHS listing price (BusinessPrice has no public surface yet)
        //  - price-on-request (no quotation opt-in flag on any payload)
        //  - same-item-across-stores grouping (no global item identity)
        //  - server ranking / engagement labels (MarketplaceDiscoveryEvent
        //    is planned, not shipped)
      };

  @override
  Future<MixStorePage> searchStores({
    required String category,
    int limit = 10,
    String? cursor,
  }) async {
    final page = await _businessService.searchBusinesses(
      q: '',
      category: category,
      limit: limit,
      cursor: cursor,
    );
    final stores = page.businesses
        .map((b) => MixStore(
              id: b.id,
              bizId: b.bizId,
              businessName: b.businessName,
              category: b.category,
            ))
        .toList();
    return (
      stores: stores,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<MixStoreOffers> productsFor(MixStore store, {int limit = 50}) async {
    // Raw rows, not the shared BusinessProduct model: the model's
    // `_toDouble(null) == 0.0` default would silently turn a MISSING price
    // into zero. The raw row keeps the missing field absent so the parser
    // can mark the price unknown.
    final res = await _apiClient.get(
      '/business/${store.bizId}/products?limit=$limit',
      requireAuth: false,
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    // Real controller failures surface as `success: false` (or a non-2xx via
    // ApiException). The demo seeds' `{'products': [...]}` shape carries no
    // `success` key — only an explicit false is an error.
    if (body['success'] == false) {
      throw Exception(body['message'] ?? 'Store listings failed');
    }
    final rows = body['products'];
    final offers = rows is List
        ? rows
            .whereType<Map>()
            .map((m) => MixOffer.fromJson(
                  Map<String, dynamic>.from(m),
                  businessProfileId: store.id,
                  bizId: store.bizId,
                  businessName: store.businessName,
                  businessCategory: store.category,
                ))
            .toList()
        : <MixOffer>[];
    return (store: store, offers: offers);
  }
}

final marketplaceMixGatewayProvider = Provider<MarketplaceMixGateway>(
  (ref) => HttpMarketplaceMixGateway(),
);
