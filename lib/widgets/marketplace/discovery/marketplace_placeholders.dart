// Data-driven search placeholders per scope/world (UI Correction v3 §5.4).

import 'package:azaman/providers/marketplace_search_provider.dart';

abstract final class MarketplacePlaceholders {
  static const List<String> marketplace = [
    'Search restaurants near you',
    'Find a store or vendor',
    'Try "jollof" or "barber"',
    'Search places on Azaman',
  ];

  static List<String> forScope(MarketplaceSearchScope scope,
      {String? world, String? storeName}) {
    final s = storeName ?? 'this store';
    // The category dial sends REAL_ESTATE for hotels.
    final w = world == 'REAL_ESTATE' ? 'HOSPITALITY' : world;
    return switch ((scope, w)) {
      (MarketplaceSearchScope.store, 'FOOD_BEVERAGE') => [
          'Search for food in "$s"',
          'Find a dish at $s',
          "Hungry? Search $s's menu",
        ],
      (MarketplaceSearchScope.store, 'RETAIL') => [
          'Search products in "$s"',
          'What are you looking for at $s?',
        ],
      (MarketplaceSearchScope.store, 'HOSPITALITY') => [
          'Search rooms at "$s"',
          'Dates, room type…',
        ],
      (MarketplaceSearchScope.store, 'LOGISTICS') => [
          'Search trips from "$s"',
          'Where are you going?',
        ],
      (MarketplaceSearchScope.store, _) => ['Search in "$s"'],
      (MarketplaceSearchScope.world, 'FOOD_BEVERAGE') => [
          'Search restaurants',
          'Try "waakye" or "pizza"',
        ],
      (MarketplaceSearchScope.world, 'RETAIL') => ['Search shops and products'],
      (MarketplaceSearchScope.world, 'HOSPITALITY') => ['Search hotels and stays'],
      (MarketplaceSearchScope.world, 'LOGISTICS') => ['Search routes and operators'],
      _ => marketplace,
    };
  }
}