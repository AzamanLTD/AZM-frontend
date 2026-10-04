import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';

class _SeededCart extends CartNotifier {
  _SeededCart(CartState seed) {
    state = seed;
  }
}

void main() {
  final now = DateTime(2026, 10, 4, 12, 0);

  ProviderContainer make({CartState? cart, DateTime Function()? clock}) {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      discoveryClockProvider.overrideWithValue(clock ?? () => now),
      worldMemoryProvider.overrideWith((_) => WorldMemoryNotifier(clock: clock ?? () => now)),
      if (cart != null) cartProvider.overrideWith((_) => _SeededCart(cart)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('nothing to resume → null', () {
    final c = make();
    expect(c.read(marketplaceResumeProvider), isNull);
  });

  test('non-empty cart wins and carries business + totals', () {
    final c = make(
      cart: const CartState(
        businessProfileId: 'bp-1',
        businessName: 'Auntie Muni',
        items: [
          CartItem(productId: 'p1', name: 'Waakye', unitPrice: 25, quantity: 2),
          CartItem(productId: 'p2', name: 'Egg', unitPrice: 5, quantity: 1),
        ],
      ),
    );
    final r = c.read(marketplaceResumeProvider)!;
    expect(r.kind, ResumeKind.cart);
    expect(r.title, 'Finish your order at Auntie Muni');
    expect(r.subtitle, '3 items · GH₵ 55.00');
    expect(r.businessProfileId, 'bp-1');
  });

  test('cart mid-checkout is not offered', () {
    final c = make(
      cart: const CartState(
        isCheckingOut: true,
        items: [CartItem(productId: 'p1', name: 'X', unitPrice: 1, quantity: 1)],
      ),
    );
    expect(c.read(marketplaceResumeProvider), isNull);
  });

  test('fresh world memory with a query becomes a world-search intent', () {
    final c = make();
    c.read(worldMemoryProvider.notifier).remember('RETAIL', query: 'sneakers');
    final r = c.read(marketplaceResumeProvider)!;
    expect(r.kind, ResumeKind.worldSearch);
    expect(r.title, 'Back to "sneakers"');
    expect(r.subtitle, 'in Retail');
    expect(r.worldWire, 'RETAIL');
  });

  test('world memory without a query is not a resume intent', () {
    final c = make();
    c.read(worldMemoryProvider.notifier).remember('RETAIL', scrollOffset: 300);
    expect(c.read(marketplaceResumeProvider), isNull);
  });

  test('stale world memory is ignored', () {
    var t = now;
    final c = make(clock: () => t);
    c.read(worldMemoryProvider.notifier).remember('RETAIL', query: 'sneakers');
    t = now.add(const Duration(hours: 1));
    // Re-evaluate: invalidate the derived provider since the clock is a closure.
    c.invalidate(marketplaceResumeProvider);
    expect(c.read(marketplaceResumeProvider), isNull);
  });
}