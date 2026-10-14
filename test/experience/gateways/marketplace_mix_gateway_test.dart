// =============================================================================
// MARKETPLACE MIX — gateway tests over the CANONICAL discovery endpoint
// (`GET /api/discovery/items`, backend PR #349).
//
// Wire-level pins (MockClient + the real ApiClient, exactly as the backend
// sees the requests):
//   • the request path, PROPER query encoding and the repeatable `taxonomy`
//     parameters (one pair per chip — never a comma list)
//   • only supported parameters are ever sent (no mode/lat/lng/radiusKm/
//     session — the merged implementation would 422 a `limit` beyond 50, so
//     the gateway clamps)
//   • 200 envelope parsing (success/items/nextCursor) and DTO handoff
//   • the typed failure model: 404 → disabled, 422 → invalid filter,
//     5xx/429/network/malformed → retryable
//   • a REAL empty success (items: []) is a page, not an error
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/services/api_client.dart';

class _Wire {
  final requests = <http.Request>[];
  http.Response? reply;
  Object? throwOnCall;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (throwOnCall != null) throw throwOnCall!;
    return reply ?? http.Response('{"success":true,"items":[],"nextCursor":null}', 200);
  });
}

ApiClient _api(_Wire wire) => ApiClient(client: wire.client);

Map<String, dynamic> _envelope({List<Map<String, dynamic>>? items, String? next}) => {
      'success': true,
      'items': items ?? const [],
      'nextCursor': next,
      'cache': {'hit': false},
    };

Map<String, dynamic> _row(String id, String businessId) => {
      'id': id,
      'businessId': businessId,
      'bizId': 'BIZ-$businessId',
      'businessName': 'Store $businessId',
      'businessCategory': 'FOOD_BEVERAGE',
      'item': {
        'name': 'Item $id',
        'images': [],
        'tags': [],
      },
      'pricing': {'amount': '10.00', 'currency': 'GHS', 'displayCurrency': 'GHS'},
      'availability': {
        'isAvailable': true,
        'sectionWindowOpen': true,
        'preparationMins': null,
        'deliveryTerms': null,
        'estimatedDelivery': null,
      },
      'location': null,
      'section': null,
      'action': 'ENQUIRE',
      'capabilities': {
        'orderable': true,
        'bookable': false,
        'deliverable': false,
        'dineIn': false,
        'payableIn': ['USDC'],
      },
      'rank': {'score': 0.1, 'label': null},
    };

void main() {
  group('buildDiscoveryItemsQuery — proper encoding, supported params only', () {
    test('category + limit + cursor encode cleanly', () {
      final q = buildDiscoveryItemsQuery(
          category: 'FOOD_BEVERAGE', limit: 24, cursor: 'abc123');
      expect(q, 'category=FOOD_BEVERAGE&limit=24&cursor=abc123');
    });

    test('taxonomy is REPEATABLE: one pair per chip, never a comma list', () {
      final q = buildDiscoveryItemsQuery(taxonomies: ['MEALS', 'DRINKS']);
      expect(q, 'taxonomy=MEALS&taxonomy=DRINKS');
      expect(q.contains(','), isFalse);
    });

    test('empty-string and null values are omitted entirely', () {
      final q = buildDiscoveryItemsQuery(
          category: ' ', q: null, taxonomies: ['', ' '], city: null);
      expect(q, isEmpty);
    });

    test('values are URI-encoded (a chip with a space cannot break the query)',
        () {
      final q = buildDiscoveryItemsQuery(q: 'banku & tilapia', city: 'Kumasi');
      expect(q, contains(Uri.encodeQueryComponent('banku & tilapia')));
      expect(q, contains('city=${Uri.encodeQueryComponent('Kumasi')}'));
    });

    test('limit is clamped to the server maximum of 50 — never sent above',
        () {
      expect(buildDiscoveryItemsQuery(limit: 500), 'limit=50');
      expect(buildDiscoveryItemsQuery(limit: 24), 'limit=24');
      expect(buildDiscoveryItemsQuery(limit: 0), 'limit=1');
    });

    test('no unsupported parameter ever appears (mode/lat/lng/radiusKm/session)',
        () {
      final q = buildDiscoveryItemsQuery(
          category: 'RETAIL',
          q: 'kente',
          taxonomies: ['RETAIL_ITEMS'],
          city: 'Accra',
          region: 'Greater Accra',
          limit: 24,
          cursor: 'xyz');
      for (final banned in ['mode=', 'lat=', 'lng=', 'radiusKm=', 'session=']) {
        expect(q.contains(banned), isFalse, reason: '$banned must never be sent');
      }
      expect(q,
          'category=RETAIL&q=${Uri.encodeQueryComponent('kente')}&taxonomy=RETAIL_ITEMS&city=${Uri.encodeQueryComponent('Accra')}&region=${Uri.encodeQueryComponent('Greater Accra')}&limit=24&cursor=xyz');
    });
  });

  group('the wire request', () {
    test('hits the canonical endpoint once, unauthenticated, cursor preserved',
        () async {
      final wire = _Wire();
      final gateway = HttpMarketplaceMixGateway(apiClient: _api(wire));
      await gateway.fetchItems(
          category: 'FOOD_BEVERAGE',
          taxonomies: ['MEALS'],
          limit: 24,
          cursor: 'CUR-2');

      expect(wire.requests, hasLength(1));
      final req = wire.requests.single;
      expect(req.url.path, contains('/api/discovery/items'));
      expect(req.url.queryParametersAll['category'], ['FOOD_BEVERAGE']);
      expect(req.url.queryParametersAll['taxonomy'], ['MEALS']);
      expect(req.url.queryParametersAll['cursor'], ['CUR-2']);
      expect(req.url.queryParametersAll['limit'], ['24']);
      expect(req.headers.containsKey('Authorization'), isFalse,
          reason: 'public surface — browsable pre-login');
    });

    test('a 200 envelope parses into offers + nextCursor', () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode(_envelope(items: [_row('p1', 'b1'), _row('p2', 'b2')], next: 'CUR-9')),
            200);
      final page = await HttpMarketplaceMixGateway(apiClient: _api(wire))
          .fetchItems(category: 'FOOD_BEVERAGE');

      expect(page.offers, hasLength(2));
      expect(page.offers.first.offerKey, 'b1:p1');
      expect(page.offers.first.price.amountExact, '10.00');
      expect(page.nextCursor, 'CUR-9');
    });

    test('a genuinely empty success is a page — zero offers, no error', () async {
      final wire = _Wire()
        ..reply = http.Response(jsonEncode(_envelope(items: [])), 200);
      final page = await HttpMarketplaceMixGateway(apiClient: _api(wire))
          .fetchItems(category: 'FOOD_BEVERAGE');
      expect(page.offers, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('an explicit nextCursor: null is the valid end-of-feed', () async {
      final wire = _Wire()
        ..reply = http.Response(jsonEncode(_envelope()), 200);
      final page = await HttpMarketplaceMixGateway(apiClient: _api(wire))
          .fetchItems();
      expect(page.nextCursor, isNull);
      expect(page.offers, isEmpty);
    });

    test('a MISSING nextCursor key is a malformed success → retryable, never a silent end-of-feed',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({'success': true, 'items': []}), 200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('an EMPTY-STRING nextCursor is a malformed success → retryable',
        () async {
      // The server never sends '' for end-of-feed — it sends null. An empty
      // string on the wire means the envelope is broken.
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({'success': true, 'items': [], 'nextCursor': ''}), 200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('a WRONG-TYPED nextCursor (number) is a malformed success → retryable',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({'success': true, 'items': [], 'nextCursor': 7}), 200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('a WRONG-TYPED nextCursor (bool) is a malformed success → retryable',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({'success': true, 'items': [], 'nextCursor': false}),
            200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('a NON-MAP item row fails the whole page as retryable — never a silent truncation',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({
              'success': true,
              'items': [
                _row('i-1', 'bp-1'),
                'a broken string row', // silently dropped would fake a page
                _row('i-2', 'bp-2'),
              ],
              'nextCursor': null,
            }),
            200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });
  });

  group('typed failure model', () {
    test('404 maps to MixEndpointDisabledException (flag off — NOT an empty feed)',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({'success': false, 'message': 'Not found'}), 404);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixEndpointDisabledException>()),
      );
    });

    test('422 maps to MixInvalidFilterException carrying the server message',
        () async {
      final wire = _Wire()
        ..reply = http.Response(
            jsonEncode({
              'success': false,
              'message': 'unknown category: FOO',
              'field': 'category'
            }),
            422);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire))
            .fetchItems(category: 'FOO'),
        throwsA(isA<MixInvalidFilterException>()
            .having((e) => e.message, 'message', contains('unknown category'))),
      );
    });

    test('500 and 429 map to MixRetryableException', () async {
      for (final status in [500, 429, 503]) {
        final wire = _Wire()
          ..reply = http.Response(
              jsonEncode({'success': false, 'message': 'boom'}), status);
        await expectLater(
          HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
          throwsA(isA<MixRetryableException>()),
          reason: 'status $status must be retryable, not disabled/invalid',
        );
      }
    });

    test('a transport error maps to MixRetryableException', () async {
      final wire = _Wire()..throwOnCall = Exception('connection reset');
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('a 200 that is not the envelope is retryable, never an empty success',
        () async {
      final wire = _Wire()
        ..reply = http.Response('<html>proxy error page</html>', 200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });

    test('success: false with 200 is retryable, never an empty success',
        () async {
      final wire = _Wire()
        ..reply =
            http.Response(jsonEncode({'success': false}), 200);
      await expectLater(
        HttpMarketplaceMixGateway(apiClient: _api(wire)).fetchItems(),
        throwsA(isA<MixRetryableException>()),
      );
    });
  });

  group('capability truth', () {
    test('the gateway reports exactly the real contracts it consumes', () {
      final caps = HttpMarketplaceMixGateway().supportedCapabilities;
      expect(caps, containsAll({
        MixCapability.crossStoreCategoryBrowse,
        MixCapability.offerIdentity,
        MixCapability.ghsListPrice,
        MixCapability.availabilitySignal,
        MixCapability.taxonomyFilters,
        MixCapability.itemStoreInteractions,
      }));
    });
  });
}
