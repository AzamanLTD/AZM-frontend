// =============================================================================
// AZAMAN — GATEWAYS: MARKETPLACE MIX (category-first, cross-store)
//
// THE CANONICAL ENDPOINT (backend PR #349, merged on main):
//   `GET /api/discovery/items` — ONE bounded request per feed page. The old
//   composition (store search + per-store catalogue fan-out) and the
//   exploratory `/api/marketplace/mix/offers` sketch are both dead: this
//   build talks to the server's discovery surface only.
//
// SUPPORTED QUERY PARAMETERS (exactly what the merged implementation parses
// — see backend services/marketplace/discoveryService.js parseParams; sending
// anything else is a contract violation, not a soft no-op):
//   category · q · taxonomy (REPEATABLE: ?taxonomy=MEALS&taxonomy=DRINKS) ·
//   city · region · limit (1..50, server default 24) · cursor (opaque)
//
// FAILURE MODEL (typed, so the provider renders each state honestly):
//   404 → [MixEndpointDisabledException] — the discovery feature flag
//         (AZM_MARKETPLACE_DISCOVERY_ENABLED) is off or the surface is
//         unavailable. NOT an empty feed; NOT silently retried.
//   422 → [MixInvalidFilterException] — the server rejected a request
//         parameter (unknown category/chip, bad cursor, limit out of
//         range). Rendered as an invalid-request state; never retried
//         in a loop.
//   everything else (network loss, timeout, 5xx, 429, malformed body) →
//         [MixRetryableException] — the existing retryable failure path.
//
// NOT a Mix ranking source: the feed renders the server's order and
// `rank.score` untouched; no client-side scoring or re-sorting exists.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/services/api_client.dart';

/// Capabilities the Mix UI may truthfully render. A capability is only in the
/// set when a REAL backend contract backs it today.
enum MixCapability {
  /// Cross-store item discovery per category (canonical discovery endpoint).
  crossStoreCategoryBrowse,

  /// Item identity + offering business identity on every offer.
  offerIdentity,

  /// Verified GHS listing prices (`pricing.amount`, exact 2dp string from
  /// the effective BusinessPrice row) — display data, never a payment claim.
  ghsListPrice,

  /// Server-evaluated availability (`isAvailable`, `sectionWindowOpen`).
  availabilitySignal,

  /// Canonical taxonomy chips (`section.taxonomy` + the repeatable
  /// `taxonomy` filter parameter).
  taxonomyFilters,

  /// Item+store interaction recording via the real
  /// `POST /api/storefront/:businessProfileId/events` (`product_tap`).
  itemStoreInteractions,
}

/// One page of `GET /api/discovery/items`.
typedef MixDiscoveryPage = ({
  List<MixOffer> offers,
  String? nextCursor,
});

/// The discovery surface is not enabled/available (404). Distinct from both
/// an empty feed and a retryable failure.
class MixEndpointDisabledException implements Exception {
  const MixEndpointDisabledException();

  @override
  String toString() => 'MixEndpointDisabledException: discovery endpoint unavailable (404)';
}

/// The server rejected a request parameter (422). Carries the server's
/// message so the UI can surface an honest invalid-request state.
class MixInvalidFilterException implements Exception {
  final String message;
  const MixInvalidFilterException(this.message);

  @override
  String toString() => 'MixInvalidFilterException: $message';
}

/// Network/server failure (timeout, connection loss, 5xx, 429, malformed
/// success body). Retryable — the existing failure/retry experience.
class MixRetryableException implements Exception {
  final String message;
  const MixRetryableException(this.message);

  @override
  String toString() => 'MixRetryableException: $message';
}

abstract interface class MarketplaceMixGateway {
  /// Which capabilities this build can compute truthfully.
  Set<MixCapability> get supportedCapabilities;

  /// ONE page of cross-store offers from the canonical discovery endpoint.
  Future<MixDiscoveryPage> fetchItems({
    String? category,
    String? q,
    List<String> taxonomies,
    String? city,
    String? region,
    int limit,
    String? cursor,
  });
}

/// Builds the `/discovery/items` query string with PROPER encoding:
/// repeatable `taxonomy` parameters, encoded values, no invented parameters.
/// Pure + public for query-shape tests.
String buildDiscoveryItemsQuery({
  String? category,
  String? q,
  List<String>? taxonomies,
  String? city,
  String? region,
  int? limit,
  String? cursor,
}) {
  final params = <String>[];
  void add(String name, String? value) {
    if (value == null) return;
    final v = value.trim();
    if (v.isEmpty) return;
    params.add('$name=${Uri.encodeQueryComponent(v)}');
  }

  add('category', category);
  add('q', q);
  // Repeatable chips: one `taxonomy=` pair each, order preserved (the server
  // dedupes first-seen anyway).
  for (final t in taxonomies ?? const <String>[]) {
    add('taxonomy', t);
  }
  add('city', city);
  add('region', region);
  // The server caps limit at 50 (parseParams); a bigger value is a 422, so
  // the gateway clamps to the supported maximum rather than sending garbage.
  if (limit != null) params.add('limit=${limit.clamp(1, 50)}');
  add('cursor', cursor);
  return params.join('&');
}

/// Real adapter over the canonical discovery endpoint.
class HttpMarketplaceMixGateway implements MarketplaceMixGateway {
  HttpMarketplaceMixGateway({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Backend server default page size (discoveryService DEFAULT_LIMIT).
  static const int kDefaultLimit = 24;

  @override
  Set<MixCapability> get supportedCapabilities => const {
        MixCapability.crossStoreCategoryBrowse,
        MixCapability.offerIdentity,
        MixCapability.ghsListPrice,
        MixCapability.availabilitySignal,
        MixCapability.taxonomyFilters,
        MixCapability.itemStoreInteractions,
        // Deliberately absent (do not add without a real contract):
        //  - GHS payment/settlement (payableIn reports USDC only today)
        //  - price-on-request (the feed excludes unpriced items entirely)
        //  - same-item-across-stores grouping (no global item identity)
        //  - analytics-backed ranking labels (rank.label is null until P3)
      };

  @override
  Future<MixDiscoveryPage> fetchItems({
    String? category,
    String? q,
    List<String> taxonomies = const [],
    String? city,
    String? region,
    int? limit,
    String? cursor,
  }) async {
    final query = buildDiscoveryItemsQuery(
      category: category,
      q: q,
      taxonomies: taxonomies,
      city: city,
      region: region,
      limit: limit ?? kDefaultLimit,
      cursor: cursor,
    );
    final path = '/discovery/items${query.isEmpty ? '' : '?$query'}';

    String body;
    try {
      // Public, unauthenticated by contract (browsable pre-login, like
      // business search).
      final res = await _apiClient.get(path, requireAuth: false);
      body = res.body;
    } on ApiException catch (e) {
      throw _mapApiException(e);
    } catch (e) {
      throw MixRetryableException(e.toString());
    }

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) throw const FormatException('not an object');
      decoded = parsed;
    } on FormatException {
      // A 200 that is not the discovery envelope is a broken surface —
      // retryable, never an empty success.
      throw const MixRetryableException('discovery response was not the expected envelope');
    }

    if (decoded['success'] != true) {
      throw const MixRetryableException('discovery request was not successful');
    }

    final rows = decoded['items'];
    if (rows is! List) {
      throw const MixRetryableException('discovery response carried no items array');
    }
    // A malformed row fails the WHOLE page as retryable — it is never
    // silently dropped (which would fake a truncated, successful page).
    final offers = <MixOffer>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const MixRetryableException(
            'discovery page contained a malformed item row');
      }
      offers.add(MixOffer.fromDiscoveryDto(Map<String, dynamic>.from(row)));
    }

    // The envelope must declare its cursor: `nextCursor: null` is the valid
    // end-of-feed value; a non-empty string is the next page cursor. A
    // MISSING key, an empty string, or a wrong-typed value means the
    // envelope is malformed — retryable, never a silent end-of-feed.
    if (!decoded.containsKey('nextCursor')) {
      throw const MixRetryableException(
          'discovery envelope did not declare nextCursor');
    }
    final next = decoded['nextCursor'];
    String? nextCursor;
    if (next == null) {
      nextCursor = null; // the valid, server-declared end of feed
    } else if (next is String && next.isNotEmpty) {
      nextCursor = next;
    } else {
      throw const MixRetryableException(
          'discovery envelope carried a malformed nextCursor');
    }

    return (offers: offers, nextCursor: nextCursor);
  }

  /// Maps the ApiClient's [ApiException] (thrown for every non-2xx by
  /// ApiClient._handleResponse) onto the typed discovery failure model.
  Exception _mapApiException(ApiException e) {
    switch (e.statusCode) {
      case 404:
        // The flag is deliberately off by default — indistinguishable from
        // an unknown route. Honest state: the surface does not exist yet.
        return const MixEndpointDisabledException();
      case 422:
        return MixInvalidFilterException(e.message);
      default:
        return MixRetryableException('server error (${e.statusCode})');
    }
  }
}

final marketplaceMixGatewayProvider = Provider<MarketplaceMixGateway>(
  (ref) => HttpMarketplaceMixGateway(),
);
