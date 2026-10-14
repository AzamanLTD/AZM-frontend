// =============================================================================
// MARKETPLACE MIX — model & mapping contract tests.
//
// Pins the identity, price-truth and availability invariants from
// lib/marketplace/mix/mix_models.dart:
//   • offer identity = item+store pair — names never merge offers
//   • a missing price NEVER becomes zero
//   • availability is only ever rendered when the payload said so
//   • decimals arrive as numbers OR strings (Prisma Decimal) and both parse
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/utils/az_money.dart';

Map<String, dynamic> _row({
  String id = 'prod-1',
  String name = 'Jollof Rice',
  dynamic price = 12.0,
  dynamic isAvailable = _absent,
  List<String> images = const ['https://img.example/a.jpg'],
}) =>
    {
      'id': id,
      'name': name,
      if (price != _absent) 'priceUsdc': price,
      if (isAvailable != _absent) 'isAvailable': isAvailable,
      'imageUrls': images,
      'tags': ['spicy'],
    };

const _absent = '__absent__';

MixOffer _offer({
  String productId = 'prod-1',
  String profileId = 'bp-1',
  String bizId = 'BIZ-1',
  String store = 'Auntie Adjoa\'s Kitchen',
  Map<String, dynamic> row = const {},
}) =>
    MixOffer.fromJson(
      row.isNotEmpty ? row : _row(id: productId),
      businessProfileId: profileId,
      bizId: bizId,
      businessName: store,
      businessCategory: 'FOOD_BEVERAGE',
    );

void main() {
  group('MixCategory', () {
    test('values cover the four discovery categories with real wire values',
        () {
      expect(MixCategory.values.map((c) => c.wire), [
        'FOOD_BEVERAGE',
        'RETAIL',
        'LOGISTICS',
        'HOSPITALITY',
      ]);
      expect(MixCategory.values.map((c) => c.label),
          containsAll(['Eat', 'Shop', 'Ride', 'Stay']));
    });

    test('byWire resolves known wires and rejects unknown ones', () {
      expect(MixCategory.byWire('RETAIL')?.label, 'Shop');
      expect(MixCategory.byWire('NOT_A_CATEGORY'), isNull);
      expect(MixCategory.byWire(null), isNull);
    });
  });

  group('price truth', () {
    test('a numeric price parses as fixed USDC', () {
      final o = _offer(row: _row(price: 12.5));
      expect(o.price.status, MixPriceStatus.fixed);
      expect(o.price.amount, 12.5);
      expect(o.price.currency, 'USDC');
    });

    test('a Prisma Decimal string price parses as fixed', () {
      final o = _offer(row: _row(price: '25.00'));
      expect(o.price.isKnown, isTrue);
      expect(o.price.amount, 25.0);
    });

    test('a MISSING price is unknown — never zero', () {
      final o = _offer(row: _row()..remove('priceUsdc'));
      expect(o.price.status, MixPriceStatus.unknown, reason: 'null → unknown');
      expect(o.price.isKnown, isFalse);
    });

    test('an unparseable price string is unknown — never zero', () {
      final o = _offer(row: _row(price: ''));
      expect(o.price.isKnown, isFalse);
    });

    test('no state of the model can render a zero-invented price', () {
      // The only two states are fixed (real payload price) and unknown.
      expect(MixPriceStatus.values.length, 2);
      // AzMoney.usdc formats a real 12.5 price; the unknown state's renderer
      // is "Price unavailable" (pinned in the card test), never a 0.00 string.
      expect(AzMoney.usdc(12.5), '12.50\u00A0USDC');
    });
  });

  group('availability truth', () {
    test('isAvailable false parses as false', () {
      expect(_offer(row: _row(isAvailable: false)).isAvailable, isFalse);
    });

    test('isAvailable true parses as true', () {
      expect(_offer(row: _row(isAvailable: true)).isAvailable, isTrue);
    });

    test('an absent availability field parses as null (unknown)', () {
      final o = _offer(row: _row());
      expect(o.isAvailable, isNull);
    });

    test('availability is independent of price presence', () {
      final unavailableWithPrice = _offer(row: _row(isAvailable: false));
      final availableUnknownPrice = _offer(row: _row()..remove('priceUsdc'));
      expect(unavailableWithPrice.isAvailable, isFalse);
      expect(unavailableWithPrice.price.isKnown, isTrue);
      expect(availableUnknownPrice.isAvailable, isNull);
      expect(availableUnknownPrice.price.isKnown, isFalse);
    });
  });

  group('offer identity (item + store pair)', () {
    test('offerKey is businessProfileId:productId', () {
      final o = _offer(profileId: 'bp-9', productId: 'prod-3');
      expect(o.offerKey, 'bp-9:prod-3');
    });

    test('the same item name in two stores is TWO distinct offers', () {
      final a = _offer(profileId: 'bp-1', bizId: 'BIZ-1', store: 'Kitchen A');
      final b = _offer(profileId: 'bp-2', bizId: 'BIZ-2', store: 'Kitchen B');
      expect(a.name, b.name);
      expect(a.offerKey, isNot(b.offerKey));
      expect(a, isNot(b));
    });

    test('identical ids across different businesses stay distinct', () {
      final a = _offer(productId: 'prod-1', profileId: 'bp-1', bizId: 'BIZ-1');
      final b = _offer(productId: 'prod-1', profileId: 'bp-2', bizId: 'BIZ-2');
      expect(a.offerKey, isNot(b.offerKey));
    });

    test('business identity fields are carried and kept distinct', () {
      final o = _offer(profileId: 'bp-1', bizId: 'BIZ-1', store: 'Kitchen A');
      expect(o.businessProfileId, 'bp-1');
      expect(o.bizId, 'BIZ-1');
      expect(o.businessName, 'Kitchen A');
      expect(o.businessCategory, 'FOOD_BEVERAGE');
    });
  });

  group('payload mapping', () {
    test('maps item fields, images and tags', () {
      final o = _offer(row: _row(
        id: 'prod-7',
        name: 'Waakye & Stew',
        images: ['https://img.example/w.jpg'],
      ));
      expect(o.productId, 'prod-7');
      expect(o.name, 'Waakye & Stew');
      expect(o.primaryImage, 'https://img.example/w.jpg');
      expect(o.tags, ['spicy']);
    });

    test('a missing image list does not crash and yields no primary image',
        () {
      final o = _offer(row: {'id': 'prod-1', 'name': 'Jollof', 'priceUsdc': 1});
      expect(o.imageUrls, isEmpty);
      expect(o.primaryImage, isNull);
    });
  });
}
