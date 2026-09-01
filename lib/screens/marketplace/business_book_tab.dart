import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

/// Customer-facing business experience surface.
///
/// The surrounding business profile stays shared, but the primary marketplace
/// journey can now be selected by the business's published Experience Blueprint.
/// Older businesses safely fall back to the capability catalog in the stage.
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

  Widget _stage(Map<String, dynamic>? experience) {
    return MarketplaceVerticalExperienceStage(
      business: business,
      colors: colors,
      onNavigate: onNavigate,
      onOpenOrderSheet: onOpenOrderSheet,
      onOpenCatalogView: onOpenCatalogView,
      menuSections: menuSections,
      uncategorisedProducts: uncategorisedProducts,
      onOrderProduct: onOrderProduct,
      experience: experience,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final experience = ref.watch(storefrontExperienceProvider(business.id));
        return experience.when(
          data: _stage,
          loading: () => _stage(null),
          error: (_, __) => _stage(null),
        );
      },
    );
  }
}
