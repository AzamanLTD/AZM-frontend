import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';

void main() {
  const dish = RestaurantDish(
    id: 'd1',
    name: 'Jollof Rice',
    price: 60,
    currency: 'GHS',
    optionGroups: [
      RestaurantOptionGroup(
        id: 'g1',
        name: 'Protein',
        required: true,
        options: [RestaurantOption(id: 'o1', name: 'Chicken', priceDelta: 15)],
      ),
    ],
  );

  test('parses dish option groups', () {
    final parsed = RestaurantDish.fromJson({
      'dishId': 'd1',
      'title': 'Jollof Rice',
      'price': '60',
      'optionGroups': [
        {
          'id': 'g1',
          'name': 'Protein',
          'required': true,
          'options': [{'id': 'o1', 'name': 'Chicken', 'priceDelta': 15}],
        }
      ],
    });
    expect(parsed.optionGroups.single.required, isTrue);
    expect(parsed.optionGroups.single.options.single.priceDelta, 15);
  });

  test('same dish with different selections is separate tray line', () {
    final tray = const RestaurantTray()
        .add(dish, selections: const {'Protein': 'Chicken'})
        .add(dish, selections: const {'Protein': 'Fish'});
    expect(tray.lines, hasLength(2));
    expect(tray.itemCount, 2);
  });

  test('same dish and selections increments quantity', () {
    final tray = const RestaurantTray()
        .add(dish, selections: const {'Protein': 'Chicken'})
        .add(dish, selections: const {'Protein': 'Chicken'});
    expect(tray.lines, hasLength(1));
    expect(tray.lines.single.quantity, 2);
  });
}
