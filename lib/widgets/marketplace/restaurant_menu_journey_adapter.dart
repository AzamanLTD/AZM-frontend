import 'package:flutter/widgets.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/restaurant_native_menu_journey.dart';

List<CatalogSection> normalizeRestaurantMenuSections({
  required List<CatalogSection> sections,
  required List<BusinessProduct> uncategorisedProducts,
}) {
  final normalized = <CatalogSection>[...sections];
  if (uncategorisedProducts.isEmpty) return normalized;

  final grouped = <String, List<BusinessProduct>>{};
  for (final product in uncategorisedProducts) {
    final rawCategory = product.category?.trim();
    final key = rawCategory == null || rawCategory.isEmpty ? 'MENU' : rawCategory.toUpperCase();
    grouped.putIfAbsent(key, () => <BusinessProduct>[]).add(product);
  }

  var order = normalized.length + 1000;
  for (final entry in grouped.entries) {
    final products = entry.value;
    normalized.add(CatalogSection(
      id: 'catalog-fallback-${entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      businessProfileId: products.first.businessProfileId,
      locationId: products.map((p) => p.locationId).firstWhere((id) => id != null && id.isNotEmpty, orElse: () => null),
      name: entry.key == 'MENU' ? 'Menu' : _humanizeRestaurantCategory(entry.key),
      description: null,
      displayOrder: order++,
      isActive: true,
      products: products,
    ));
  }
  return normalized;
}

String _humanizeRestaurantCategory(String value) => value
    .toLowerCase()
    .split(RegExp(r'[_\-\s]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

bool restaurantRequiresVisibleOptions(Iterable<RestaurantDish> dishes) => dishes.any(
      (dish) => dish.variants.isNotEmpty || dish.optionGroups.any((group) => group.required),
    );

class RestaurantMenuJourneyAdapter extends StatelessWidget {
  final String businessName;
  final List<CatalogSection> sections;
  final List<BusinessProduct> uncategorisedProducts;
  final Map<String, RestaurantDish> dishesById;
  final AzamanColors colors;
  final void Function(BusinessProduct product, Map<String, String> selections, int quantity) onAddToTray;
  final bool showGallery;
  final bool showSpecifications;
  final bool showOptions;
  final bool showQuantity;
  final String? dineInContext;
  final MarketplaceDetailPresentation detailPresentation;

  const RestaurantMenuJourneyAdapter({
    super.key,
    required this.businessName,
    required this.sections,
    required this.uncategorisedProducts,
    required this.dishesById,
    required this.colors,
    required this.onAddToTray,
    this.showGallery = true,
    this.showSpecifications = true,
    this.showOptions = true,
    this.showQuantity = true,
    this.dineInContext,
    this.detailPresentation = MarketplaceDetailPresentation.dishDossier,
  });

  @override
  Widget build(BuildContext context) => RestaurantNativeMenuJourney(
        businessName: businessName,
        sections: normalizeRestaurantMenuSections(sections: sections, uncategorisedProducts: uncategorisedProducts),
        uncategorisedProducts: const [],
        dishesById: dishesById,
        colors: colors,
        onAddToTray: onAddToTray,
        showGallery: showGallery,
        showSpecifications: showSpecifications,
        showOptions: showOptions || restaurantRequiresVisibleOptions(dishesById.values),
        showQuantity: showQuantity,
        dineInContext: dineInContext,
        detailPresentation: detailPresentation,
      );
}
