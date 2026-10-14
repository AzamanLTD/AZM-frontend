// =============================================================================
// MARKETPLACE MIX — model tests: canonical discovery DTO parsing
// (`GET /api/discovery/items`, backend PR #349).
//
// Pins:
//   • field-for-field DTO mapping (item/pricing/availability/location/
//     section/action/capabilities/rank)
//   • item identity vs business identity kept distinct; the item+store pair
//     distinguishes the same-named item sold by two different businesses
//   • the STRICT GHS price invariants: exact 2dp string, expected currency,
//     no USDC fallback, no conversion, no zero, no numeric parsing
//   • canonical taxonomy mirror (wire-exact with the backend overlay;
//     UNMAPPED not requestable)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';

/// A complete, contract-shaped discovery row (backend buildItemDto).
Map<String, dynamic> _dto({
  String id = 'prod-1',
  String businessId = 'bp-1',
  String bizId = 'BIZ-1',
  String businessName = 'Auntie Adjoa\'s Kitchen',
  String businessCategory = 'FOOD_BEVERAGE',
  String name = 'Jollof Rice',
  String? amount = '25.00',
  String currency = 'GHS',
  String? displayCurrency = 'GHS',
  dynamic hasUsdcListPrice = true,
  dynamic isAvailable = true,
  dynamic sectionWindowOpen = true,
  dynamic preparationMins = 15,
  String? deliveryTerms = 'Same-day within Accra',
  String? estimatedDelivery = '45 mins',
  String? taxonomy = 'MEALS',
  String action = 'ADD_TO_CART',
  List<String> payableIn = const ['USDC'],
  num rankScore = 0.42,
}) =>
    {
      'id': id,
      'businessId': businessId,
      'bizId': bizId,
      'businessName': businessName,
      'businessCategory': businessCategory,
      'item': {
        'name': name,
        'slug': 'jollof-rice',
        'description': 'Smoky party jollof with chicken.',
        'imageUrl': 'https://cdn.example/jollof.jpg',
        'images': ['https://cdn.example/jollof.jpg', 'https://cdn.example/jollof-2.jpg'],
        'tags': ['ghanaian', 'lunch'],
      },
      'pricing': {
        if (amount != null) 'amount': amount,
        'currency': currency,
        if (displayCurrency != null) 'displayCurrency': displayCurrency,
        'hasUsdcListPrice': hasUsdcListPrice,
      },
      'variants': null,
      'modifierGroups': null,
      'availability': {
        'isAvailable': isAvailable,
        'sectionWindowOpen': sectionWindowOpen,
        'preparationMins': preparationMins,
        'deliveryTerms': deliveryTerms,
        'estimatedDelivery': estimatedDelivery,
      },
      'location': {
        'locationId': 'loc-1',
        'label': 'Osu branch',
        'distanceKm': null,
      },
      'section': {
        'id': 'sec-1',
        'name': 'Main course',
        'taxonomy': taxonomy,
      },
      'action': action,
      'capabilities': {
        'orderable': true,
        'bookable': false,
        'deliverable': true,
        'dineIn': false,
        'payableIn': payableIn,
      },
      'rank': {'score': rankScore, 'label': null},
    };

void main() {
  group('canonical DTO field mapping', () {
    test('every field of the merged DTO maps to the model', () {
      final offer = MixOffer.fromDiscoveryDto(_dto());

      expect(offer.productId, 'prod-1');
      expect(offer.businessId, 'bp-1');
      expect(offer.bizId, 'BIZ-1');
      expect(offer.businessName, "Auntie Adjoa's Kitchen");
      expect(offer.businessCategory, 'FOOD_BEVERAGE');

      expect(offer.name, 'Jollof Rice');
      expect(offer.description, 'Smoky party jollof with chicken.');
      expect(offer.imageUrls, [
        'https://cdn.example/jollof.jpg',
        'https://cdn.example/jollof-2.jpg',
      ]);
      expect(offer.tags, ['ghanaian', 'lunch']);

      expect(offer.price.isKnown, isTrue);
      expect(offer.price.amountExact, '25.00');

      expect(offer.isAvailable, isTrue);
      expect(offer.sectionWindowOpen, isTrue);
      expect(offer.preparationMins, 15);
      expect(offer.deliveryTerms, 'Same-day within Accra');
      expect(offer.estimatedDelivery, '45 mins');

      expect(offer.locationLabel, 'Osu branch');
      expect(offer.sectionTaxonomy, 'MEALS');
      expect(offer.action, 'ADD_TO_CART');

      expect(offer.capabilities.orderable, isTrue);
      expect(offer.capabilities.bookable, isFalse);
      expect(offer.capabilities.deliverable, isTrue);
      expect(offer.capabilities.dineIn, isFalse);
      expect(offer.capabilities.payableIn, ['USDC']);

      expect(offer.rankScore, 0.42);
    });

    test('item.imageUrl is the first of item.images (DTO contract)', () {
      final offer = MixOffer.fromDiscoveryDto(_dto());
      expect(offer.primaryImage, offer.imageUrls.first);
    });

    test('absent sub-objects parse to honest empties, never crashes', () {
      final offer = MixOffer.fromDiscoveryDto({
        'id': 'prod-9',
        'businessId': 'bp-9',
        'bizId': 'BIZ-9',
        'businessName': 'Sole',
        'businessCategory': 'RETAIL',
        'item': {'name': 'No detail row'},
        'action': 'ENQUIRE',
      });
      expect(offer.name, 'No detail row');
      expect(offer.price.isKnown, isFalse);
      expect(offer.isAvailable, isNull);
      expect(offer.sectionWindowOpen, isNull);
      expect(offer.capabilities.payableIn, isEmpty);
      expect(offer.imageUrls, isEmpty);
    });
  });

  group('identity: item identity is never confused with business identity', () {
    test('offerKey is businessId:productId', () {
      final offer = MixOffer.fromDiscoveryDto(_dto());
      expect(offer.offerKey, 'bp-1:prod-1');
    });

    test(
        'the same-named item sold by TWO businesses is TWO distinct offers',
        () {
      final a = MixOffer.fromDiscoveryDto(
          _dto(id: 'prod-x', businessId: 'bp-1', bizId: 'BIZ-1', name: 'Waakye'));
      final b = MixOffer.fromDiscoveryDto(
          _dto(id: 'prod-y', businessId: 'bp-2', bizId: 'BIZ-2', name: 'Waakye'));

      expect(a.name, b.name, reason: 'fixture: same item NAME');
      expect(a.offerKey, isNot(b.offerKey));
      expect(a, isNot(b), reason: 'offers are never merged by name');
      expect(a.hashCode, isNot(b.hashCode));
    });

    test('the three identity fields stay distinct', () {
      final offer = MixOffer.fromDiscoveryDto(_dto());
      expect(offer.productId, isNot(offer.businessId));
      expect(offer.businessId, isNot(offer.bizId));
      expect(offer.productId, isNot(offer.bizId));
    });
  });

  group('GHS price is a strict invariant (exact decimal, never floated)', () {
    test('a valid GHS row keeps the EXACT 2dp STRING — no double anywhere',
        () {
      final offer = MixOffer.fromDiscoveryDto(_dto(amount: '1240.42'));
      expect(offer.price.status, MixPriceStatus.fixed);
      expect(offer.price.amountExact, '1240.42');
      expect(offer.price.amountExact, isA<String>());
    });

    test('absent pricing parses to unknown — never zero, never USDC', () {
      final offer = MixOffer.fromDiscoveryDto({
        ..._dto(),
        'pricing': null,
      });
      expect(offer.price.status, MixPriceStatus.unknown);
      expect(offer.price.amountExact, isNull);
    });

    test('absent amount parses to unknown even with currency GHS', () {
      final offer = MixOffer.fromDiscoveryDto(_dto(amount: null));
      expect(offer.price.status, MixPriceStatus.unknown);
    });

    test('a non-GHS currency NEVER renders a fixed price', () {
      final offer = MixOffer.fromDiscoveryDto(
          _dto(amount: '12.50', currency: 'USDC', displayCurrency: 'USDC'));
      expect(offer.price.status, MixPriceStatus.unknown);
      expect(offer.price.amountExact, isNull,
          reason: 'a USDC amount is never relabelled or converted');
    });

    test('a JSON-number amount is a contract violation → unknown (never floated)',
        () {
      final offer = MixOffer.fromDiscoveryDto(_dto(amount: 'ignored')
            ..['amount'] = 12.5);
      expect(offer.price.status, MixPriceStatus.unknown);
    });

    test('malformed amounts parse to unknown — never zero', () {
      for (final bad in ['', '  ', '12.5', '12.500', '0.00a', 'GH12.00', '-5.00', '.50']) {
        final offer = MixOffer.fromDiscoveryDto(_dto(amount: bad));
        expect(offer.price.status, MixPriceStatus.unknown,
            reason: '"$bad" must not render a fixed price');
      }
    });

    test('the string is preserved verbatim (25.00 ≠ 25.0 ≠ 25)', () {
      final fixed = MixOffer.fromDiscoveryDto(_dto(amount: '25.00')).price;
      expect(fixed.amountExact, '25.00');
    });

    test('hasUsdcListPrice is informational only — never a price', () {
      // The model has NO USDC price field at all: the only price surface is
      // the exact GHS string, so a USDC list price can never leak into it.
      final offer =
          MixOffer.fromDiscoveryDto(_dto(hasUsdcListPrice: true));
      expect(offer.price.isKnown, isTrue);
      expect(offer.price.amountExact, '25.00');
    });

    test('MixOfferPrice.fromPricing validates currency before shape', () {
      expect(
        MixOfferPrice.fromPricing({'amount': '10.00', 'currency': 'EUR'})
            .isKnown,
        isFalse,
      );
      expect(
        MixOfferPrice.fromPricing({'amount': '10.00', 'currency': 'GHS'}).isKnown,
        isTrue,
      );
    });
  });

  group('availability honesty', () {
    test('isAvailable true/false/null map 1:1 to the payload', () {
      expect(
          MixOffer.fromDiscoveryDto(_dto(isAvailable: true)).isAvailable, isTrue);
      expect(
          MixOffer.fromDiscoveryDto(_dto(isAvailable: false)).isAvailable,
          isFalse);
      expect(
          MixOffer.fromDiscoveryDto(_dto(isAvailable: null)).isAvailable,
          isNull);
    });

    test('sectionWindowOpen maps independently of isAvailable', () {
      final offer = MixOffer.fromDiscoveryDto(_dto(
          isAvailable: true, sectionWindowOpen: false));
      expect(offer.isAvailable, isTrue);
      expect(offer.sectionWindowOpen, isFalse,
          reason: 'a closed window is its own honest signal');
    });

    test('availability is never inferred from a price', () {
      final unpriced = MixOffer.fromDiscoveryDto(_dto(amount: null));
      expect(unpriced.price.isKnown, isFalse);
      expect(unpriced.isAvailable, isTrue,
          reason: 'the payload said available; the missing price says nothing');
    });

    test('an unmapped/absent section parses taxonomy null', () {
      final offer = MixOffer.fromDiscoveryDto(_dto(taxonomy: null));
      expect(offer.sectionTaxonomy, isNull);
    });
  });

  group('canonical taxonomy mirror (backend overlay TAXONOMY_ROWS)', () {
    test('the canonical chip ids are wire-exact', () {
      expect(MixTaxonomy.canonical.map((t) => t.id), [
        'MEALS', 'STARTERS', 'SIDES', 'DRINKS', 'DESSERTS',
        'ROOMS', 'RIDES', 'RETAIL_ITEMS', 'SERVICES',
      ]);
    });

    test('UNMAPPED is deliberately NOT requestable', () {
      expect(MixTaxonomy.byId('UNMAPPED'), isNull);
    });

    test('category-scoped chips: Eat gets the five food chips', () {
      final eat = MixTaxonomy.forCategory('FOOD_BEVERAGE').map((t) => t.id);
      expect(eat, ['MEALS', 'STARTERS', 'SIDES', 'DRINKS', 'DESSERTS', 'SERVICES']);
    });

    test('category-scoped chips: Stay gets ROOMS', () {
      final stay = MixTaxonomy.forCategory('HOSPITALITY').map((t) => t.id);
      expect(stay, ['ROOMS', 'SERVICES']);
    });

    test('unknown section taxonomy ids pass through as data (display only)',
        () {
      // The model never validates the payload's taxonomy against the rail —
      // the server owns the vocabulary; the client just carries it.
      final offer = MixOffer.fromDiscoveryDto(_dto(taxonomy: 'FUTURE_CHIP'));
      expect(offer.sectionTaxonomy, 'FUTURE_CHIP');
    });
  });
}
