// =============================================================================
// AZAMAN — G1: MIX DISCOVERY DEMO SEED (GET /discovery/items)
//
// The Mix tab's feed is served by the demo interceptor from
// DemoMarketplaceSeed.discoveryItems. This suite proves the demo path is a
// REAL feed, not a fabricated success:
//   1. offers span ALL FOUR seeded categories and parse through the REAL
//      MixOffer.fromDiscoveryDto with AUTHORITATIVE fixed GHS prices
//      (exact-2dp strings — never computed from a USDC value);
//   2. every row carries a REAL seeded business identity (bizId from
//      seededBusinessIds);
//   3. category / taxonomy / query filters genuinely change the result;
//   4. cursor pagination continues deterministically to exhaustion with
//      no duplicated or lost rows, and the envelope always declares
//      nextCursor;
//   5. an unparseable cursor is REFUSED, never answered with a fabricated
//      page;
//   6. the interceptor serves the endpoint end-to-end (demo mode flows
//      through the actual AppConfig.demoMode/interceptor path — no fake
//      production records).
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/data/demo_interceptor.dart';
import 'package:azaman/data/demo_seed_marketplace.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';

void main() {
  group('G1 — Mix discovery demo seed', () {
    test('catalog spans all four seeded categories and parses through the '
        'REAL DTO parser with authoritative GHS prices', () {
      final page = DemoMarketplaceSeed.discoveryItems(limit: 50);
      expect(page['success'], true);
      final rows = (page['items'] as List).cast<Map<String, dynamic>>();
      expect(rows.length, 12, reason: 'the demo catalog has 12 offers');

      final categories = rows
          .map((r) => r['businessCategory'].toString())
          .toSet();
      expect(categories, containsAll(<String>[
        'FOOD_BEVERAGE',
        'HOSPITALITY',
        'LOGISTICS',
        'RETAIL',
      ]));

      for (final row in rows) {
        // Parse with the REAL parser — a demo row that the app could not
        // parse is a broken seed, not a feed.
        final offer = MixOffer.fromDiscoveryDto(row);
        expect(offer.bizId, isNotEmpty);
        expect(
          DemoMarketplaceSeed.seededBusinessIds.contains(offer.bizId),
          isTrue,
          reason: 'offer ${offer.productId} must reference a REAL seeded '
              'business, got ${offer.bizId}',
        );
        // Authoritative GHS price: fixed status, exact-2dp string money.
        expect(offer.price.isKnown, isTrue,
            reason: '${offer.name} must carry a known GHS price');
        expect(offer.price.amountExact, matches(RegExp(r'^\d+\.\d{2}$')));
        expect(offer.name, isNotEmpty);
        expect(offer.businessName, isNotEmpty);
        expect(offer.primaryImage, isNotNull);
        expect(offer.capabilities.payableIn, equals(const ['USDC']),
            reason: 'payability stays USDC-only — same honest limit as the '
                'real gateway');
      }
    });

    test('category, taxonomy and query filters genuinely change results',
        () {
      final food = DemoMarketplaceSeed.discoveryItems(
          category: 'FOOD_BEVERAGE', limit: 50);
      expect((food['items'] as List).length, 4);
      for (final row in (food['items'] as List)) {
        expect(row['businessCategory'], 'FOOD_BEVERAGE');
      }

      final retail = DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['retail'], limit: 50);
      expect((retail['items'] as List).length, 4);

      final suya = DemoMarketplaceSeed.discoveryItems(q: 'suya', limit: 50);
      expect((suya['items'] as List).length, 2);

      // No matches is an HONEST empty success, never a fabricated offer.
      final none = DemoMarketplaceSeed.discoveryItems(
          q: 'zzz-not-a-thing', limit: 50);
      expect(none['success'], true);
      expect((none['items'] as List), isEmpty);
      expect(none.containsKey('nextCursor'), true);
      expect(none['nextCursor'], isNull);
    });

    test('cursor pagination continues deterministically to exhaustion — '
        'no duplicates, no losses, envelope always declares nextCursor',
        () {
      final seen = <String>[];
      String? cursor;
      var pages = 0;
      while (true) {
        final page =
            DemoMarketplaceSeed.discoveryItems(limit: 5, cursor: cursor);
        expect(page['success'], true);
        expect(page.containsKey('nextCursor'), true,
            reason: 'every envelope must declare its cursor');
        for (final row in (page['items'] as List)) {
          seen.add(row['id'].toString());
        }
        cursor = page['nextCursor'] as String?;
        pages++;
        if (cursor == null) break;
        expect(pages, lessThan(10), reason: 'pagination must terminate');
      }
      expect(pages, 3, reason: '12 offers at limit 5 = 3 pages');
      expect(seen.toSet().length, seen.length,
          reason: 'no offer may appear twice');
      expect(seen.length, 12, reason: 'every catalog offer must be served');

      // Continuation is stable: the same cursor yields the same page.
      final a = DemoMarketplaceSeed.discoveryItems(limit: 5, cursor: 'off-5');
      final b = DemoMarketplaceSeed.discoveryItems(limit: 5, cursor: 'off-5');
      expect(jsonEncode(a['items']), jsonEncode(b['items']));
    });

    test('an unparseable cursor is REFUSED — never a fabricated page', () {
      expect(
        () => DemoMarketplaceSeed.discoveryItems(cursor: 'garbage'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
      expect(
        () => DemoMarketplaceSeed.discoveryItems(cursor: 'off-not-a-number'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
    });

    test('the demo interceptor serves the endpoint end-to-end', () {
      final res = DemoInterceptor.tryGet('/discovery/items?limit=24');
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['success'], true);
      expect((body['items'] as List).length, 12);
      expect(body.containsKey('nextCursor'), true);

      final filtered = DemoInterceptor.tryGet(
          '/discovery/items?category=RETAIL&limit=24');
      expect(filtered, isNotNull);
      final fbody = jsonDecode(filtered!.body) as Map<String, dynamic>;
      expect((fbody['items'] as List).length, 4);
      for (final row in (fbody['items'] as List)) {
        expect(row['businessCategory'], 'RETAIL');
      }

      // The repeatable taxonomy parameter (one pair per chip) filters too.
      final tax = DemoInterceptor.tryGet(
          '/discovery/items?taxonomy=retail&taxonomy=logistics&limit=24');
      final tbody = jsonDecode(tax!.body) as Map<String, dynamic>;
      expect((tbody['items'] as List).length, 6);
    });
  });
}
