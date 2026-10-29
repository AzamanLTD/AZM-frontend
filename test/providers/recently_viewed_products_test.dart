import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/recently_viewed_products_provider.dart';

void main() {
  test('most recent first, de-duplicated, capped', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(recentlyViewedProductsProvider.notifier);

    n.record('a');
    n.record('b');
    n.record('a');
    expect(container.read(recentlyViewedProductsProvider), ['a', 'b']);

    for (var i = 0; i < 20; i++) {
      n.record('p$i');
    }
    final list = container.read(recentlyViewedProductsProvider);
    expect(list.length, RecentlyViewedProductsNotifier.cap);
    expect(list.first, 'p19');

    n.clear();
    expect(container.read(recentlyViewedProductsProvider), isEmpty);
  });
}