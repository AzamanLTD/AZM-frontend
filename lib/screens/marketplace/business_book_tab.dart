import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

/// Customer-facing business experience surface.
///
/// The surrounding business profile stays shared, but each primary marketplace
/// category now gets its own interaction primitive: restaurant menu book,
/// retail shelf, hotel floor plan, or transit seat map.
class BusinessBookTab extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final void Function(String route)? onNavigate;
  final VoidCallback? onOpenOrderSheet;
  final VoidCallback? onOpenCatalogView;

  final List<CatalogSection> menuSections;
  final List<BusinessProduct> uncategorisedProducts;
  final void Function(BusinessProduct product)? onOrderProduct;

  const BusinessBookTab({
    super.key,
    required this.business,
    required this.colors,
    this.onNavigate,
    this.onOpenOrderSheet,
    this.onOpenCatalogView,
    this.menuSections = const [],
    this.uncategorisedProducts = const [],
    this.onOrderProduct,
  });

  @override
  Widget build(BuildContext context) {
    return MarketplaceVerticalExperienceStage(
      business: business,
      colors: colors,
      onNavigate: onNavigate,
      onOpenOrderSheet: onOpenOrderSheet,
      onOpenCatalogView: onOpenCatalogView,
      menuSections: menuSections,
      uncategorisedProducts: uncategorisedProducts,
      onOrderProduct: onOrderProduct,
    );
  }
}
