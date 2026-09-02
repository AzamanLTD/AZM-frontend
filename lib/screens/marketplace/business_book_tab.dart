import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/floating_cart_bar.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

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

  Map<String, RestaurantDish> _dishMap(Map<String, dynamic>? rawData) {
    final rawProducts = rawData?['products'];
    if (rawProducts is! List) return const {};
    final result = <String, RestaurantDish>{};
    for (final value in rawProducts) {
      if (value is! Map) continue;
      final json = Map<String, dynamic>.from(value);
      final id = json['id']?.toString();
      if (id == null || id.isEmpty) continue;
      result[id] = RestaurantDish.fromBusinessProductJson(json);
    }
    return result;
  }

  double _selectedUnitPrice(BusinessProduct product, RestaurantDish dish, Map<String, String> selections) {
    var total = product.priceUsdc;
    final size = selections['size'];
    if (size != null && size.isNotEmpty) {
      final variant = dish.variants.where((item) => item.name == size).firstOrNull;
      if (variant != null) total += variant.priceDelta;
    }
    for (final group in dish.optionGroups) {
      final raw = selections[group.name];
      if (raw == null || raw.isEmpty) continue;
      final selected = raw.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
      for (final option in group.options.where((item) => selected.contains(item.name))) total += option.priceDelta;
    }
    return total;
  }

  Widget _stage(Map<String, dynamic>? experience, WidgetRef ref, BuildContext context, Map<String, RestaurantDish> dishesById) {
    final blueprint = MarketplaceExperienceBlueprint.fromJson(experience, business.category);
    final useRestaurantTray = blueprint.preset == 'DINING_JOURNEY' && blueprint.persistentTray && onOrderProduct != null;

    void handleRestaurantOrder(BusinessProduct product, Map<String, String> selections, int quantity) {
      if (!useRestaurantTray) {
        onOrderProduct?.call(product);
        return;
      }
      final dish = dishesById[product.id];
      final adjustedUnitPrice = dish == null ? product.priceUsdc : _selectedUnitPrice(product, dish, selections);
      _addToRestaurantTray(context, ref, product, selections: selections, quantity: quantity, unitPrice: adjustedUnitPrice);
    }

    final stage = MarketplaceVerticalExperienceStage(
      business: business,
      colors: colors,
      onNavigate: onNavigate,
      onOpenOrderSheet: onOpenOrderSheet,
      onOpenCatalogView: onOpenCatalogView,
      menuSections: menuSections,
      uncategorisedProducts: uncategorisedProducts,
      onOrderProduct: onOrderProduct,
      onAddToTray: handleRestaurantOrder,
      restaurantDishesById: dishesById,
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
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
        ),
      ],
    );
  }

  void _addToRestaurantTray(BuildContext context, WidgetRef ref, BusinessProduct product, {Map<String, String> selections = const {}, int quantity = 1, required double unitPrice}) {
    if (!product.isActive) {
      AzamanHaptics.warn();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This dish is currently unavailable.')));
      return;
    }

    final notifier = ref.read(cartProvider.notifier);
    final added = notifier.addItem(
      businessProfileId: business.id,
      businessName: business.businessName,
      productId: product.id,
      name: product.name,
      unitPrice: unitPrice,
      imageUrl: product.primaryImage,
      category: product.category,
      quantity: quantity,
      variants: selections,
    );

    if (added) {
      AzamanHaptics.confirm();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} added to your order tray.'), duration: const Duration(milliseconds: 1400)));
      return;
    }

    final currentCart = ref.read(cartProvider);
    if (currentCart.businessProfileId == null || currentCart.items.isEmpty) return;

    AzamanHaptics.warn();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new order?'),
        content: Text('Your current tray is from ${currentCart.businessName ?? 'another business'}. Replace it with this restaurant’s order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Keep tray')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              notifier.clearCart();
              notifier.addItem(businessProfileId: business.id, businessName: business.businessName, productId: product.id, name: product.name, unitPrice: unitPrice, imageUrl: product.primaryImage, category: product.category, quantity: quantity, variants: selections);
              AzamanHaptics.confirm();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} added to your new order tray.'), duration: const Duration(milliseconds: 1400)));
            },
            child: const Text('Replace tray'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final experience = ref.watch(storefrontExperienceProvider(business.id));
      final products = ref.watch(storefrontProductsProvider(business.id));
      final dishesById = products.whenOrNull(data: (value) => _dishMap(value)) ?? const <String, RestaurantDish>{};
      return experience.when(
        data: (value) => _stage(value, ref, context, dishesById),
        loading: () => _stage(null, ref, context, dishesById),
        error: (_, __) => _stage(null, ref, context, dishesById),
      );
    });
  }
}
