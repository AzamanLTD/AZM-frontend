import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience_policy.dart';

void main() {
  const dishWithoutRequiredChoices = RestaurantDish(
    id: 'plain',
    name: 'Plain rice',
  );
  const dishWithRequiredModifier = RestaurantDish(
    id: 'custom',
    name: 'Custom bowl',
    optionGroups: [
      RestaurantOptionGroup(
        id: 'protein',
        name: 'Protein',
        required: true,
        options: [RestaurantOption(id: 'chicken', name: 'Chicken')],
      ),
    ],
  );
  const dishWithVariant = RestaurantDish(
    id: 'size',
    name: 'Family pizza',
    variants: [RestaurantProductVariant(id: 'large', name: 'Large')],
  );

  test('keeps merchant setting when no required choices exist', () {
    final blueprint = {
      'detail': {'showOptions': false},
    };

    final result = effectiveRestaurantExperience(
      experience: blueprint,
      dishes: const [dishWithoutRequiredChoices],
    );

    expect(result, same(blueprint));
    expect((result!['detail'] as Map)['showOptions'], isFalse);
  });

  test('forces options visible when a required modifier exists', () {
    final result = effectiveRestaurantExperience(
      experience: const {
        'preset': 'DINING_JOURNEY',
        'detail': {'showOptions': false, 'showQuantity': true},
      },
      dishes: const [dishWithRequiredModifier],
    );

    expect(result!['preset'], 'DINING_JOURNEY');
    final detail = result['detail'] as Map;
    expect(detail['showOptions'], isTrue);
    expect(detail['showQuantity'], isTrue);
  });

  test('forces options visible when variants are required to select a valid line', () {
    final result = effectiveRestaurantExperience(
      experience: const {'detail': {'showOptions': false}},
      dishes: const [dishWithVariant],
    );

    expect((result!['detail'] as Map)['showOptions'], isTrue);
  });

  test('does not mutate the persisted blueprint map', () {
    final blueprint = <String, dynamic>{
      'detail': <String, dynamic>{'showOptions': false},
    };

    final result = effectiveRestaurantExperience(
      experience: blueprint,
      dishes: const [dishWithRequiredModifier],
    );

    expect((blueprint['detail'] as Map)['showOptions'], isFalse);
    expect(identical(result, blueprint), isFalse);
  });
}
