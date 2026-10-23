// =============================================================================
// AZAMAN — G1: MIX DISCOVERY DEMO SEED (GET /discovery/items)
//
// The Mix tab's feed is served by the demo interceptor from
// DemoMarketplaceSeed.discoveryItems. This suite proves the demo path is a
// REAL feed, not a fabricated success:
//   1. every offer is DERIVED from the seed's own ground truth and parses
//      through the REAL MixOffer.fromDiscoveryDto with AUTHORITATIVE fixed
//      GHS prices (exact-2dp strings — never computed from a USDC value);
//      item identity (id, name, description, images, tags) and owning
//      business are verified against the seeded menus/tickets/products and
//      room registry — never merely because the bizId exists;
//   2. taxonomy chips are wire-exact with MixTaxonomy.canonical (the real
//      UI's chip values): canonical chips return the right items whose
//      DTOs carry the chip, canonical-but-unseeded chips are an honest
//      empty success, and an unknown chip is REFUSED like the server's
//      422;
//   3. city and region filters use the seeded STRUCTURED location metadata
//      — an offer located in Accra matches city=Accra even when its
//      display label reads "Spintex Road";
//   4. cursor pagination continues deterministically to exhaustion with
//      no duplicated or lost rows, and the envelope always declares
//      nextCursor;
//   5. an unparseable cursor is REFUSED, never answered with a fabricated
//      page;
//   6. the interceptor serves the endpoint end-to-end (demo mode flows
//      through the actual interceptor path — no fake production records).
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/data/demo_interceptor.dart';
import 'package:azaman/data/demo_seed_marketplace.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';

void main() {
  List<Map<String, dynamic>> items(Map<String, dynamic> page) =>
      (page['items'] as List).cast<Map<String, dynamic>>();

  group('G1 — item identity: offers derive from the seeded ground truth', () {
    test('every offer references a REAL seeded item of its owning business '
        'with coherent displayed identity', () {
      final rows = items(DemoMarketplaceSeed.discoveryItems(limit: 50));
      expect(rows.length, 12, reason: 'the demo catalog has 12 offers');

      final categories =
          rows.map((r) => r['businessCategory'].toString()).toSet();
      expect(categories, containsAll(<String>[
        'FOOD_BEVERAGE',
        'HOSPITALITY',
        'LOGISTICS',
        'RETAIL',
      ]));

      for (final row in rows) {
        // Parse with the REAL parser — a demo row the app could not parse
        // is a broken seed, not a feed.
        final offer = MixOffer.fromDiscoveryDto(row);
        expect(offer.bizId, isNotEmpty);
        expect(
          DemoMarketplaceSeed.seededBusinessIds.contains(offer.bizId),
          isTrue,
          reason: 'offer ${offer.productId} must reference a REAL seeded '
              'business, got ${offer.bizId}',
        );

        // ITEM identity — verified against the seeded source, not merely
        // because the bizId exists.
        final isDish = offer.productId.startsWith('dish') ||
            offer.productId.startsWith('drink') ||
            offer.productId.startsWith('dessert');
        final isRoom = offer.productId.startsWith('room-');
        final isTicketOrRetail = offer.productId.startsWith('prod-');

        if (isDish) {
          // The seeded menu of this business must contain the dish, with
          // this name, description, images and tags.
          final menu = DemoMarketplaceSeed.getMenu(offer.bizId);
          Map<String, dynamic>? source;
          for (final section in (menu['sections'] as List)) {
            for (final p in (section['products'] as List)) {
              if (p['id'] == offer.productId) source = p;
            }
          }
          expect(source, isNotNull,
              reason: '${offer.productId} must be a seeded menu item of '
                  '${offer.bizId}');
          // The seeded menus key dishes to the BUSINESS (bizId) — the
          // menu was fetched through getMenu(offer.bizId), so ownership is
          // proven by that lookup plus this explicit equality.
          expect(source!['businessProfileId'], offer.bizId,
              reason: 'the dish must belong to the named business');
          expect(source['name'], offer.name,
              reason: 'displayed name must match the seeded dish');
          expect(source['description'], offer.description);
          expect((source['imageUrls'] as List).first, offer.primaryImage);
          expect((source['tags'] as List).join(' '),
              offer.tags.join(' '));
        } else if (isRoom) {
          // Seeded room registry: room-<profileId>-<floor*100+n>; Floor 1
          // rooms 01-02 are Deluxe Suites (the documented seed truth).
          final parts = offer.productId.split('-');
          expect(offer.businessId, '${parts[1]}-${parts[2]}',
              reason: 'the room id encodes its owning profile');
          final roomNumber = int.parse(offer.productId.split('-').last);
          final floor = roomNumber ~/ 100;
          final expectedType = roomNumber % 100 <= 2
              ? 'Deluxe Suite'
              : (roomNumber % 100 <= 4 ? 'Standard Room' : 'Economy Room');
          expect(offer.name, 'Room $roomNumber');
          expect(offer.description, '$expectedType on Floor $floor');
        } else {
          expect(isTicketOrRetail, isTrue);
          // Transit tickets and retail products are in the PUBLIC seeded
          // catalogue — verify name, description and ownership there.
          final source = (DemoMarketplaceSeed.getProductById(offer.productId)
              ['product'] as Map<String, dynamic>);
          expect(source['businessProfileId'], offer.businessId,
              reason: '${offer.productId} must be OWNED by '
                  '${offer.businessId}');
          expect(source['name'], offer.name,
              reason: 'displayed name must match the seeded product '
                  '(e.g. prod-tshirt is Cotton Crew Tee)');
          expect(source['description'], offer.description);
          expect((source['imageUrls'] as List).first, offer.primaryImage);
        }

        // Authoritative GHS price: fixed status, exact-2dp string money.
        expect(offer.price.isKnown, isTrue,
            reason: '${offer.name} must carry a known GHS price');
        expect(offer.price.amountExact, matches(RegExp(r'^\d+\.\d{2}$')));
        expect(offer.capabilities.payableIn, equals(const ['USDC']),
            reason: 'payability stays USDC-only — same honest limit as the '
                'real gateway');
      }
    });

    test('the previously wrong identities are gone: prod-tshirt is Cotton '
        'Crew Tee and the transit ticket is a real seeded ticket', () {
      final rows = items(DemoMarketplaceSeed.discoveryItems(limit: 50));
      final byId = {
        for (final r in rows) r['id'].toString(): r,
      };

      final tee = byId['prod-tshirt']!;
      expect((tee['item'] as Map)['name'], 'Cotton Crew Tee');
      expect(tee['businessId'], 'retail-001');

      final std = byId['prod-transit-001-std']!;
      expect((std['item'] as Map)['name'], 'Standard Ticket');
      expect(std['businessName'], 'Advenr');

      final room = byId['room-hotel-001-101']!;
      expect((room['item'] as Map)['name'], 'Room 101');
      expect((room['item'] as Map)['description'],
          'Deluxe Suite on Floor 1');
    });
  });

  group('G1 — taxonomy chips: wire-exact canonical values', () {
    test('real chip values return the expected items and the DTOs carry '
        'the chip', () {
      // FOOD chips
      final starters = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['STARTERS'], limit: 50));
      expect(starters, isNotEmpty);
      for (final row in starters) {
        expect(row['section']['taxonomy'], 'STARTERS');
        expect(row['businessCategory'], 'FOOD_BEVERAGE');
      }

      final meals = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['MEALS'], limit: 50));
      expect(meals, isNotEmpty);
      expect(meals.first['item']['name'], 'Chicken Suya');

      final drinks = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['DRINKS'], limit: 50));
      expect(drinks, isNotEmpty);
      expect(drinks.first['item']['name'], 'Sobolo');

      final desserts = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['DESSERTS'], limit: 50));
      expect(desserts, isNotEmpty);
      expect(desserts.first['item']['name'], 'Bofrot Trio');

      // ROOMS
      final rooms = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['ROOMS'], limit: 50));
      expect(rooms.length, 2);
      for (final row in rooms) {
        expect(row['section']['taxonomy'], 'ROOMS');
        expect(row['businessCategory'], 'HOSPITALITY');
        expect(row['id'], startsWith('room-'));
      }

      // RIDES
      final rides = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['RIDES'], limit: 50));
      expect(rides.length, 2);
      for (final row in rides) {
        expect(row['section']['taxonomy'], 'RIDES');
        expect(row['businessCategory'], 'LOGISTICS');
      }

      // RETAIL_ITEMS
      final retail = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['RETAIL_ITEMS'], limit: 50));
      expect(retail.length, 4);
      for (final row in retail) {
        expect(row['section']['taxonomy'], 'RETAIL_ITEMS');
        expect(row['businessCategory'], 'RETAIL');
      }

      // Repeatable chips union, order preserved.
      final union = items(DemoMarketplaceSeed.discoveryItems(
          taxonomies: const ['ROOMS', 'RIDES'], limit: 50));
      expect(union.length, 4);
      expect(
        union.map((r) => r['section']['taxonomy']).toSet(),
        {'ROOMS', 'RIDES'},
      );
    });

    test('canonical-but-unseeded chips (SIDES, SERVICES) are an HONEST '
        'empty success — the documented unmapped behaviour', () {
      for (final chip in ['SIDES', 'SERVICES']) {
        final page = DemoMarketplaceSeed.discoveryItems(
            taxonomies: [chip], limit: 50);
        expect(page['success'], true);
        expect(items(page), isEmpty);
        expect(page.containsKey('nextCursor'), true);
        expect(page['nextCursor'], isNull);
      }
    });

    test('an UNKNOWN chip is REFUSED like the server 422 — never a '
        'fabricated result set', () {
      expect(
        () => DemoMarketplaceSeed.discoveryItems(
            taxonomies: const ['food_beverage']),
        throwsA(isA<DemoEndpointNotSeededException>()),
        reason: 'the old lowercase slug is not a canonical chip value',
      );
      expect(
        () => DemoMarketplaceSeed.discoveryItems(
            taxonomies: const ['retail']),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
      // A canonical chip mixed with an unknown one still refuses.
      expect(
        () => DemoMarketplaceSeed.discoveryItems(
            taxonomies: const ['MEALS', 'not-a-chip']),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
    });
  });

  group('G1 — city/region: structured seeded metadata, not label text', () {
    test('city=Accra includes offers whose LABEL lacks the word Accra '
        '(the Spintex grill house)', () {
      final accra = items(
          DemoMarketplaceSeed.discoveryItems(city: 'Accra', limit: 50));
      expect(accra.length, 10, reason: 'everything but Cape Coast and Ho');
      final suya = accra.firstWhere(
          (r) => r['id'] == 'dish2-suya',
          orElse: () => throw StateError(
              'the Spintex offer must be found by city even though its '
              'label reads "Mama Titi\'s - Spintex"'));
      expect(suya['location']['label'], "Mama Titi's - Spintex",
          reason: 'the established display label is preserved');
      expect(suya['location']['city'], 'Accra');
      expect(suya['location']['region'], 'Greater Accra');
      for (final row in accra) {
        expect(row['location']['city'], 'Accra');
      }
    });

    test('city and region reflect the actual seeded locations', () {
      final capeCoast = items(
          DemoMarketplaceSeed.discoveryItems(city: 'Cape Coast', limit: 50));
      expect(capeCoast.length, 1);
      expect(capeCoast.first['id'], 'room-hotel-002-201');

      final ho =
          items(DemoMarketplaceSeed.discoveryItems(city: 'Ho', limit: 50));
      expect(ho.length, 1);
      expect(ho.first['id'], 'prod-transit-002-vip');

      final greaterAccra = items(
          DemoMarketplaceSeed.discoveryItems(region: 'Greater Accra',
              limit: 50));
      expect(greaterAccra.length, 10);
      expect(
        greaterAccra
            .map((r) => r['location']['city'].toString())
            .toSet(),
        {'Accra'},
      );

      final central = items(
          DemoMarketplaceSeed.discoveryItems(region: 'Central', limit: 50));
      expect(central.length, 1);
      expect(central.first['id'], 'room-hotel-002-201');

      final volta = items(
          DemoMarketplaceSeed.discoveryItems(region: 'Volta', limit: 50));
      expect(volta.length, 1);
      expect(volta.first['id'], 'prod-transit-002-vip');
    });

    test('a city with no seeded offers is an honest empty success with '
        'the established DTO envelope', () {
      final none = DemoMarketplaceSeed.discoveryItems(
          city: 'Tamale', limit: 50);
      expect(none['success'], true);
      expect(items(none), isEmpty);
      expect(none.containsKey('nextCursor'), true);
      expect(none['nextCursor'], isNull);
    });
  });

  group('G1 — category, query and empty honesty', () {
    test('category and query genuinely change results', () {
      final food = items(DemoMarketplaceSeed.discoveryItems(
          category: 'FOOD_BEVERAGE', limit: 50));
      expect(food.length, 4);
      for (final row in food) {
        expect(row['businessCategory'], 'FOOD_BEVERAGE');
      }

      final jollof =
          items(DemoMarketplaceSeed.discoveryItems(q: 'jollof', limit: 50));
      expect(jollof.length, 1);
      expect(jollof.first['item']['name'], 'Jollof Rice');

      // No matches is an HONEST empty success, never a fabricated offer.
      final none = DemoMarketplaceSeed.discoveryItems(
          q: 'zzz-not-a-thing', limit: 50);
      expect(none['success'], true);
      expect(items(none), isEmpty);
      expect(none.containsKey('nextCursor'), true);
      expect(none['nextCursor'], isNull);
    });
  });

  group('G1 — cursor pagination', () {
    test('continuation is deterministic to exhaustion — no duplicates, no '
        'losses, envelope always declares nextCursor', () {
      final seen = <String>[];
      String? cursor;
      var pages = 0;
      while (true) {
        final page =
            DemoMarketplaceSeed.discoveryItems(limit: 5, cursor: cursor);
        expect(page['success'], true);
        expect(page.containsKey('nextCursor'), true,
            reason: 'every envelope must declare its cursor');
        for (final row in items(page)) {
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
  });

  group('G1 — interceptor end-to-end', () {
    test('serves the endpoint, real chip values, structured city filter',
        () {
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
        expect(row['section']['taxonomy'], 'RETAIL_ITEMS');
      }

      // Real chip values through the actual query-string path.
      final rooms =
          DemoInterceptor.tryGet('/discovery/items?taxonomy=ROOMS&limit=24');
      final rbody = jsonDecode(rooms!.body) as Map<String, dynamic>;
      expect((rbody['items'] as List).length, 2);

      final rides =
          DemoInterceptor.tryGet('/discovery/items?taxonomy=RIDES&limit=24');
      final rideBody = jsonDecode(rides!.body) as Map<String, dynamic>;
      expect((rideBody['items'] as List).length, 2);

      final retailChips = DemoInterceptor.tryGet(
          '/discovery/items?taxonomy=RETAIL_ITEMS&limit=24');
      final retailBody =
          jsonDecode(retailChips!.body) as Map<String, dynamic>;
      expect((retailBody['items'] as List).length, 4);

      // The structured city filter reaches the wire too.
      final accra = DemoInterceptor.tryGet(
          '/discovery/items?city=Accra&limit=24');
      final accraBody = jsonDecode(accra!.body) as Map<String, dynamic>;
      expect((accraBody['items'] as List).length, 10);
    });

    test('an unknown chip through the interceptor surfaces the demo '
        'not-seeded error, exactly like the server 422 path', () {
      expect(
        () => DemoInterceptor.tryGet(
            '/discovery/items?taxonomy=food_beverage&limit=24'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
    });
  });
}
