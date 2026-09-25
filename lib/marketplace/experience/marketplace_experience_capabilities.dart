import 'package:flutter/foundation.dart';

import 'package:azaman/models/business_models.dart';

/// Interaction primitives that define the customer experience for a
/// marketplace business. Category determines the defaults, while future
/// storefront configuration can add/remove capabilities after validation.
enum MarketplaceExperienceCapability {
  menuFlipbook,
  reservation,
  hotelFloorMap,
  roomExplorer,
  transitSeatMap,
  boardingPass,
  retailCollection,
  productVariants,
  pickup,
  delivery,
}

@immutable
class MarketplaceExperienceProfile {
  final String categoryWire;
  final String label;
  final Set<MarketplaceExperienceCapability> capabilities;
  final String primaryActionLabel;

  const MarketplaceExperienceProfile({
    required this.categoryWire,
    required this.label,
    required this.capabilities,
    required this.primaryActionLabel,
  });

  bool supports(MarketplaceExperienceCapability capability) =>
      capabilities.contains(capability);
}

/// Canonical category-to-capability mapping for the four primary marketplace
/// categories. This is deliberately data-driven so widgets can ask what a
/// business supports rather than scattering category comparisons throughout
/// the UI.
class MarketplaceExperienceCatalog {
  MarketplaceExperienceCatalog._();

  static const restaurant = MarketplaceExperienceProfile(
    categoryWire: 'FOOD_BEVERAGE',
    label: 'Restaurants',
    capabilities: {
      MarketplaceExperienceCapability.menuFlipbook,
      MarketplaceExperienceCapability.reservation,
      MarketplaceExperienceCapability.productVariants,
      MarketplaceExperienceCapability.pickup,
      MarketplaceExperienceCapability.delivery,
    },
    primaryActionLabel: 'View menu',
  );

  static const retail = MarketplaceExperienceProfile(
    categoryWire: 'RETAIL',
    label: 'Retail',
    capabilities: {
      MarketplaceExperienceCapability.retailCollection,
      MarketplaceExperienceCapability.productVariants,
      MarketplaceExperienceCapability.pickup,
      MarketplaceExperienceCapability.delivery,
    },
    primaryActionLabel: 'View store',
  );

  static const hotel = MarketplaceExperienceProfile(
    categoryWire: 'HOSPITALITY',
    label: 'Hotels',
    capabilities: {
      MarketplaceExperienceCapability.hotelFloorMap,
      MarketplaceExperienceCapability.roomExplorer,
      MarketplaceExperienceCapability.reservation,
    },
    primaryActionLabel: 'See rooms',
  );

  static const transit = MarketplaceExperienceProfile(
    categoryWire: 'LOGISTICS',
    label: 'Transit',
    capabilities: {
      MarketplaceExperienceCapability.transitSeatMap,
      MarketplaceExperienceCapability.boardingPass,
    },
    primaryActionLabel: 'Book a seat',
  );

  static MarketplaceExperienceProfile fromCategory(String? category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
        return restaurant;
      case 'RETAIL':
        return retail;
      case 'HOSPITALITY':
        return hotel;
      case 'LOGISTICS':
        return transit;
      default:
        final catalogCategory = BusinessCategories.fromWire(category);
        return MarketplaceExperienceProfile(
          categoryWire: catalogCategory.wire,
          label: catalogCategory.label,
          capabilities: const <MarketplaceExperienceCapability>{},
          primaryActionLabel: 'View business',
        );
    }
  }
}
