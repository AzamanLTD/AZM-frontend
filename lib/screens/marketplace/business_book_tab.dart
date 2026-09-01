import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/floating_cart_bar.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

/// Customer-facing business experience surface.
///
/// The surrounding business profile stays shared, but the primary marketplace
/// journey can now be selected by the business's published Experience Blueprint.
/// Older businesses safely fall back to the capability catalog in the stage.
///
/// For dining journeys with a persistent tray, dish additions go into the
/// canonical multi-item cart instead of opening a one-off ticket. Reservation
/// remains a separate action so ordering and booking do not compete for the
/// same primary interaction.
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

  Widget _stage(Map<String, dynamic>? experience, WidgetRef ref, BuildContext context) {
    final blueprint = MarketplaceExperienceBlueprint.fromJson(
      experience,
      business.category,
    );
    final useRestaurantTray =
        blueprint.preset == 'DINING_JOURNEY' &&
        blueprint.persistentTray &&
        onOrderProduct != null;

    void handleRestaurantOrder(BusinessProduct product) {
      if (!useRestaurantTray) {
        onOrderProduct?.call(product);
        return;
      }
      _addToRestaurantTray(context, ref, product);
    }

    final stage = MarketplaceVerticalExperienceStage(
      business: business,
      colors: colors,
      onNavigate: onNavigate,
      onOpenOrderSheet: onOpenOrderSheet,
      onOpenCatalogView: onOpenCatalogView,
      menuSections: menuSections,
      uncategorisedProducts: uncategorisedProducts,
      onOrderProduct: useRestaurantTray
          ? handleRestaurantOrder
          : onOrderProduct,
      experience: experience,
    );

    if (!useRestaurantTray) return stage;

    return Stack(
      fit: StackFit.expand,
      children: [
        stage,
        Positioned(
          left: 0,
          right: 0,
          bottom: 84,
          child: FloatingCartBar(
            label: 'Open order tray',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartScreen()),
            ),
          ),
        ),
      ],
    );
  }

  void _addToRestaurantTray(
    BuildContext context,
    WidgetRef ref,
    BusinessProduct product,
  ) {
    if (!product.isActive) {
      AzamanHaptics.warn();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This dish is currently unavailable.')),
      );
      return;
    }

    final notifier = ref.read(cartProvider.notifier);
    final added = notifier.addItem(
      businessProfileId: business.id,
      businessName: business.businessName,
      productId: product.id,
      name: product.name,
      unitPrice: product.priceUsdc,
      imageUrl: product.primaryImage,
      category: product.category,
    );

    if (added) {
      AzamanHaptics.confirm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} added to your order tray.'),
          duration: const Duration(milliseconds: 1400),
        ),
      );
      return;
    }

    final currentCart = ref.read(cartProvider);
    if (currentCart.businessProfileId == null || currentCart.items.isEmpty) {
      return;
    }

    AzamanHaptics.warn();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new order?'),
        content: Text(
          'Your current tray is from ${currentCart.businessName ?? 'another business'}. Replace it with this restaurant’s order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep tray'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              notifier.clearCart();
              notifier.addItem(
                businessProfileId: business.id,
                businessName: business.businessName,
                productId: product.id,
                name: product.name,
                unitPrice: product.priceUsdc,
                imageUrl: product.primaryImage,
                category: product.category,
              );
              AzamanHaptics.confirm();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${product.name} added to your new order tray.'),
                  duration: const Duration(milliseconds: 1400),
                ),
              );
            },
            child: const Text('Replace tray'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final experience = ref.watch(storefrontExperienceProvider(business.id));
        return experience.when(
          data: (value) => _stage(value, ref, context),
          loading: () => _stage(null, ref, context),
          error: (_, __) => _stage(null, ref, context),
        );
      },
    );
  }
}
