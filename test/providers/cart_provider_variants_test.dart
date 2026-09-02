import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/cart_provider.dart';

defines() {}

void main() {
  test('different selections remain separate cart lines', () {
    final cart = CartNotifier();
    cart.clearCart();

    final first = cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 12,
      variants: const {'size': 'Large', 'Sauce': 'Pepper'},
    );
    final second = cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 10,
      variants: const {'size': 'Regular', 'Sauce': 'Pepper'},
    );

    expect(first, isTrue);
    expect(second, isTrue);
    expect(cart.state.items, hasLength(2));
    expect(cart.state.items[0].quantity, 1);
    expect(cart.state.items[1].quantity, 1);
    expect(cart.state.items[0].lineKey, isNot(cart.state.items[1].lineKey));
  });

  test('same selections increment the existing cart line', () {
    final cart = CartNotifier();
    cart.clearCart();

    cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 12,
      quantity: 1,
      variants: const {'Sauce': 'Pepper'},
    );
    cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 12,
      quantity: 2,
      variants: const {'Sauce': 'Pepper'},
    );

    expect(cart.state.items, hasLength(1));
    expect(cart.state.items.single.quantity, 3);
  });

  test('line quantity and removal can target one configured line', () {
    final cart = CartNotifier();
    cart.clearCart();
    cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 12,
      variants: const {'size': 'Large'},
    );
    cart.addItem(
      businessProfileId: 'bp-1',
      businessName: 'Restaurant',
      productId: 'dish-1',
      name: 'Jollof Rice',
      unitPrice: 10,
      variants: const {'size': 'Regular'},
    );
    final regularKey = cart.state.items.last.lineKey;

    cart.updateLineQuantity(regularKey, 4);
    expect(cart.state.items.last.quantity, 4);

    cart.removeLine(regularKey);
    expect(cart.state.items, hasLength(1));
    expect(cart.state.items.single.variants['size'], 'Large');
  });
}