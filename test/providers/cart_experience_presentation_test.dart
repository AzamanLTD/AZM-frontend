import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/cart_provider.dart';

void main() {
  test('persists the experience preset with the cart presentation state', () {
    const state = CartState(
      businessProfileId: 'biz-1',
      businessName: 'The Copper Spoon',
      experiencePreset: 'DINING_JOURNEY',
      items: [
        CartItem(
          productId: 'dish-1',
          name: 'Jollof',
          unitPrice: 8,
          quantity: 2,
          variants: {'size': 'Large'},
        ),
      ],
    );

    final restored = CartState.fromPersistJson(state.toPersistJson());

    expect(restored.experiencePreset, 'DINING_JOURNEY');
    expect(restored.businessProfileId, 'biz-1');
    expect(restored.items.single.lineKey, state.items.single.lineKey);
  });

  test('legacy persisted carts without a preset remain compatible', () {
    final restored = CartState.fromPersistJson({
      'businessProfileId': 'biz-1',
      'businessName': 'Legacy Store',
      'items': [
        {
          'productId': 'product-1',
          'name': 'Widget',
          'unitPrice': 3.5,
          'quantity': 1,
          'imageUrl': null,
          'notes': null,
          'category': 'RETAIL',
          'variants': {},
        },
      ],
    });

    expect(restored.experiencePreset, isNull);
    expect(restored.items.single.productId, 'product-1');
  });

  test('experience presentation metadata is never sent to checkout', () {
    const state = CartState(
      businessProfileId: 'biz-1',
      businessName: 'Restaurant',
      experiencePreset: 'DINING_JOURNEY',
      items: [
        CartItem(
          productId: 'dish-1',
          name: 'Waakye',
          unitPrice: 12,
          quantity: 1,
          variants: {'protein': 'Chicken'},
        ),
      ],
    );

    expect(state.toCheckoutItems(), [
      {
        'productId': 'dish-1',
        'quantity': 1,
        'variants': {'protein': 'Chicken'},
      },
    ]);
  });
}
