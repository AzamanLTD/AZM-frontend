import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_tray_rules.dart';
import 'package:azaman/providers/cart_provider.dart';

void main() {
  const item = CartItem(productId: 'p', name: 'Shirt', unitPrice: 10, quantity: 1);

  test('hidden when cart empty', () {
    expect(retailTrayVisible(const CartState(businessProfileId: 'a'), businessId: 'a'), isFalse);
  });

  test('visible only for the business that owns the items', () {
    const cart = CartState(businessProfileId: 'a', items: [item]);
    expect(retailTrayVisible(cart, businessId: 'a'), isTrue);
    expect(retailTrayVisible(cart, businessId: 'b'), isFalse);
  });
}