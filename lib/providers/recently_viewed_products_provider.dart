/// Recently viewed products (Overhaul 03 §2.5) — in-memory, per session.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class RecentlyViewedProductsNotifier extends StateNotifier<List<String>> {
  static const cap = 12;

  RecentlyViewedProductsNotifier() : super(const []);

  void record(String productId) {
    final next = [productId, ...state.where((id) => id != productId)];
    state = next.length > cap ? next.sublist(0, cap) : next;
  }

  void clear() => state = const [];
}

final recentlyViewedProductsProvider =
    StateNotifierProvider<RecentlyViewedProductsNotifier, List<String>>(
  (_) => RecentlyViewedProductsNotifier(),
);