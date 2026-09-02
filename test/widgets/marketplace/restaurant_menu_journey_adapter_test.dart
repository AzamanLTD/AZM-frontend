import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/marketplace/restaurant_menu_journey_adapter.dart';

BusinessProduct _product(String name, {String? category, String? locationId}) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'business-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      description: null,
      category: category,
      locationId: locationId,
      priceUsdc: 10,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: true,
      totalOrders: 0,
    );

void main() {
  test('does not create the synthetic Other Items section', () {
    final sections = normalizeRestaurantMenuSections(
      sections: [
        CatalogSection(
          id: 'section-1',
          businessProfileId: 'business-1',
          name: 'Mains',
          description: null,
          displayOrder: 0,
          isActive: true,
          products: [_product('Jollof rice')],
        ),
      ],
      uncategorisedProducts: [_product('Mango juice', category: 'DRINKS')],
    );

    expect(sections.map((section) => section.name), contains('Drinks'));
    expect(sections.map((section) => section.name), isNot(contains('Other Items')));
    expect(sections.last.products.single.name, 'Mango juice');
  });

  test('keeps truly uncategorised products visible under a neutral menu continuation', () {
    final sections = normalizeRestaurantMenuSections(
      sections: const [],
      uncategorisedProducts: [_product('Chef special', locationId: 'location-1')],
    );

    expect(sections.single.name, 'Menu');
    expect(sections.single.locationId, 'location-1');
    expect(sections.single.products.single.name, 'Chef special');
  });

  test('required restaurant configuration forces option controls to remain reachable', () {
    final requiredOptions = RestaurantDish(
      id: 'dish-1',
      name: 'Configured dish',
      variants: const [RestaurantProductVariant(id: 'large', name: 'Large', priceDelta: 2)],
    );
    final optionalOnly = RestaurantDish(
      id: 'dish-2',
      name: 'Plain dish',
    );

    expect(restaurantRequiresVisibleOptions([requiredOptions]), isTrue);
    expect(restaurantRequiresVisibleOptions([optionalOnly]), isFalse);
  });
}
