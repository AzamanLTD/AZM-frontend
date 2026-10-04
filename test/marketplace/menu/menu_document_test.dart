import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/menu/menu_document.dart';
import 'package:azaman/models/business_models.dart';

BusinessProduct _p(String id, String name, {String? description, List<String> tags = const [], bool active = true}) =>
    BusinessProduct(
      id: id,
      businessProfileId: 'biz',
      name: name,
      slug: id,
      priceUsdc: 5,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: active,
      totalOrders: 0,
      tags: tags,
      description: description,
    );

CatalogSection _s(String id, String name, int order, List<BusinessProduct> products,
        {String? from, String? to, bool active = true}) =>
    CatalogSection(
      id: id,
      businessProfileId: 'biz',
      name: name,
      displayOrder: order,
      isActive: active,
      availableFrom: from,
      availableTo: to,
      products: products,
    );

void main() {
  final noon = DateTime(2026, 10, 5, 12);

  group('MenuDocument.build', () {
    test('orders chapters by displayOrder and appends More for uncategorised', () {
      final doc = MenuDocument.build(
        sections: [
          _s('mains', 'Mains', 2, [_p('m1', 'Jollof')]),
          _s('starters', 'Starters', 1, [_p('s1', 'Kelewele')]),
        ],
        uncategorised: [_p('u1', 'Water')],
        dishesById: const {},
        now: noon,
      );
      expect(doc.chapters.map((c) => c.title), ['Starters', 'Mains', 'More']);
      expect(doc.chapters.last.id, MenuChapter.moreId);
      expect(doc.byId('u1')?.product.name, 'Water');
    });

    test('drops inactive sections and carries dishes', () {
      const dish = RestaurantDish(id: 'm1', name: 'Jollof');
      final doc = MenuDocument.build(
        sections: [
          _s('mains', 'Mains', 1, [_p('m1', 'Jollof')]),
          _s('old', 'Old', 2, [_p('o1', 'Gone')], active: false),
        ],
        uncategorised: const [],
        dishesById: {'m1': dish},
        now: noon,
      );
      expect(doc.chapters.length, 1);
      expect(doc.byId('m1')?.dish, same(dish));
      expect(doc.byId('o1'), isNull);
    });

    test('availability window marks items unavailable outside hours', () {
      final doc = MenuDocument.build(
        sections: [
          _s('bf', 'Breakfast', 1, [_p('b1', 'Waakye')], from: '06:00', to: '11:00'),
        ],
        uncategorised: const [],
        dishesById: const {},
        now: noon,
      );
      expect(doc.chapters.single.availabilityLabel, '06:00 – 11:00');
      expect(doc.byId('b1')!.availableNow, isFalse);

      final morning = MenuDocument.build(
        sections: [
          _s('bf', 'Breakfast', 1, [_p('b1', 'Waakye')], from: '06:00', to: '11:00'),
        ],
        uncategorised: const [],
        dishesById: const {},
        now: DateTime(2026, 10, 5, 8),
      );
      expect(morning.byId('b1')!.availableNow, isTrue);
    });

    test('malformed window never hides food', () {
      final doc = MenuDocument.build(
        sections: [
          _s('x', 'X', 1, [_p('x1', 'Thing')], from: 'dawn', to: 'dusk'),
        ],
        uncategorised: const [],
        dishesById: const {},
        now: noon,
      );
      expect(doc.byId('x1')!.availableNow, isTrue);
    });

    test('inactive product is unavailable even inside window', () {
      final doc = MenuDocument.build(
        sections: [_s('m', 'M', 1, [_p('m1', 'Off', active: false)])],
        uncategorised: const [],
        dishesById: const {},
        now: noon,
      );
      expect(doc.byId('m1')!.availableNow, isFalse);
    });
  });

  group('filtered', () {
    final doc = MenuDocument.build(
      sections: [
        _s('mains', 'Mains', 1, [_p('m1', 'Jollof', tags: ['rice']), _p('m2', 'Banku', description: 'with tilapia')]),
        _s('drinks', 'Drinks', 2, [_p('d1', 'Sobolo')]),
      ],
      uncategorised: const [],
      dishesById: const {},
      now: noon,
    );

    test('empty query preserves identity', () {
      expect(identical(doc.filtered(''), doc), isTrue);
      expect(identical(doc.filtered('   '), doc), isTrue);
    });

    test('matches name, description and tags; drops empty chapters', () {
      expect(doc.filtered('RICE').items.map((i) => i.id), ['m1']);
      expect(doc.filtered('tilapia').items.map((i) => i.id), ['m2']);
      final f = doc.filtered('sobolo');
      expect(f.chapters.map((c) => c.title), ['Drinks']);
      expect(doc.filtered('pizza').isEmpty, isTrue);
    });
  });

  group('mealPathChapters', () {
    test('returns courses in meal order, empty under two courses', () {
      final doc = MenuDocument.build(
        sections: [
          _s('d', 'Desserts', 1, [_p('d1', 'Cake')]),
          _s('m', 'Main dishes', 2, [_p('m1', 'Jollof')]),
          _s('s', 'Starters & bites', 3, [_p('s1', 'Spring roll')]),
          _s('o', 'Chef picks', 4, [_p('o1', 'Special')]),
        ],
        uncategorised: const [],
        dishesById: const {},
        now: noon,
      );
      expect(mealPathChapters(doc).map((c) => c.id), ['s', 'm', 'd']);
      final single = MenuDocument.build(
        sections: [_s('m', 'Mains', 1, [_p('m1', 'Jollof')])],
        uncategorised: const [],
        dishesById: const {},
        now: noon,
      );
      expect(mealPathChapters(single), isEmpty);
    });
  });
}