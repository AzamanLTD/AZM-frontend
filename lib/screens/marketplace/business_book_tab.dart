import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience_policy.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_order_mode.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';
import 'package:azaman/widgets/marketplace/restaurant_tray_rail.dart';

class BusinessBookTab extends ConsumerStatefulWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final void Function(String route)? onNavigate;
  final VoidCallback? onOpenOrderSheet;
  final VoidCallback? onOpenCatalogView;
  final List<CatalogSection> menuSections;
  final List<BusinessProduct> uncategorisedProducts;
  final void Function(BusinessProduct product)? onOrderProduct;
  final Future<void> Function(BusinessProduct product, Map<String, String> selections, int quantity)? onDineInAddToTab;
  final String? dineInContext;

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
    this.onDineInAddToTab,
    this.dineInContext,
  });

  @override
  ConsumerState<BusinessBookTab> createState() => _BusinessBookTabState();
}

class _BusinessBookTabState extends ConsumerState<BusinessBookTab> {
  late RestaurantOrderMode _orderMode;

  @override
  void initState() {
    super.initState();
    _orderMode = widget.onDineInAddToTab != null ? RestaurantOrderMode.dineIn : RestaurantOrderMode.takeaway;
  }

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

  /// Canonical TASK-013 cart unit price (TASK-013 financial-consistency
  /// correction): the mutation starts from the SAME effective base price as
  /// the detail surface and build sheet — `RestaurantDish.price ??
  /// BusinessProduct.priceUsdc` — then applies the selected variant and
  /// modifier deltas. Fail-closed: a null result must never create a
  /// payable cart line.
  double? _selectedUnitPrice(BusinessProduct product, RestaurantDish dish, Map<String, String> selections) {
    return restaurantEffectiveUnitPrice(
      dish: dish,
      fallbackPrice: product.priceUsdc,
      selections: selections,
    );
  }

  /// Fail-closed catalog fallback for products without a storefront dish
  /// configuration: a non-finite or non-positive catalog price is unknown,
  /// not 0.00, and must not create a payable line.
  double? _catalogUnitPrice(BusinessProduct product) {
    return product.priceUsdc.isFinite && product.priceUsdc > 0 ? product.priceUsdc : null;
  }

  Widget _stage(Map<String, dynamic>? experience, BuildContext context, Map<String, RestaurantDish> dishesById) {
    final effectiveExperience = effectiveRestaurantExperience(
      experience: experience,
      dishes: dishesById.values,
    );
    final blueprint = MarketplaceExperienceBlueprint.fromJson(effectiveExperience, widget.business.category);
    final useRestaurantTray = blueprint.preset == 'DINING_JOURNEY' && blueprint.persistentTray && (widget.onOrderProduct != null || widget.onDineInAddToTab != null);

    void handleRestaurantOrder(BusinessProduct product, Map<String, String> selections, int quantity) {
      if (_orderMode == RestaurantOrderMode.dineIn && widget.onDineInAddToTab != null) {
        unawaited(widget.onDineInAddToTab!(product, selections, quantity).catchError((error) {
          if (!context.mounted) return;
          AzamanHaptics.warn();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add ${product.name}: $error')));
        }));
        return;
      }
      if (!useRestaurantTray) {
        if (_orderMode != RestaurantOrderMode.dineIn && widget.onOrderProduct == null) {
          AzamanHaptics.warn();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Takeaway ordering is not available for this restaurant yet.')));
          return;
        }
        widget.onOrderProduct?.call(product);
        return;
      }
      final dish = dishesById[product.id];
      final effectiveUnitPrice = dish == null ? _catalogUnitPrice(product) : _selectedUnitPrice(product, dish, selections);
      if (effectiveUnitPrice == null) {
        // Fail closed: no payable cart line for an unknown price.
        AzamanHaptics.warn();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No price available for ${product.name} — nothing was added to the tray.')));
        return;
      }
      _addToRestaurantTray(
        context,
        product,
        experiencePreset: blueprint.preset,
        selections: selections,
        quantity: quantity,
        unitPrice: effectiveUnitPrice,
        notes: _orderMode.cartNote,
      );
    }

    final stage = MarketplaceVerticalExperienceStage(
      business: widget.business,
      colors: widget.colors,
      onNavigate: widget.onNavigate,
      onOpenOrderSheet: widget.onOpenOrderSheet,
      onOpenCatalogView: widget.onOpenCatalogView,
      menuSections: widget.menuSections,
      uncategorisedProducts: widget.uncategorisedProducts,
      onOrderProduct: widget.onOrderProduct,
      onAddToTray: handleRestaurantOrder,
      restaurantDishesById: dishesById,
      dineInContext: blueprint.customerContext.enabled ? widget.dineInContext : null,
      orderMode: _orderMode,
      onOrderModeChanged: (mode) => setState(() => _orderMode = mode),
      dineInAvailable: widget.onDineInAddToTab != null,
      experience: effectiveExperience,
    );

    if (!useRestaurantTray) return stage;

    return Stack(
      fit: StackFit.expand,
      children: [
        stage,
        Positioned(
          left: 12,
          right: 12,
          bottom: 84,
          child: RestaurantTrayRail(
            label: 'Open order tray',
            onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
        ),
      ],
    );
  }

  void _addToRestaurantTray(
    BuildContext context,
    BusinessProduct product, {
    required String experiencePreset,
    Map<String, String> selections = const {},
    int quantity = 1,
    required double unitPrice,
    String? notes,
  }) {
    if (!product.isActive) {
      AzamanHaptics.warn();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This dish is currently unavailable.')));
      return;
    }

    final notifier = ref.read(cartProvider.notifier);
    final added = notifier.addItem(
      businessProfileId: widget.business.id,
      businessName: widget.business.businessName,
      productId: product.id,
      name: product.name,
      unitPrice: unitPrice,
      imageUrl: product.primaryImage,
      category: product.category,
      experiencePreset: experiencePreset,
      quantity: quantity,
      variants: selections,
      notes: notes,
    );

    if (added) {
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
              notifier.addItem(businessProfileId: widget.business.id, businessName: widget.business.businessName, productId: product.id, name: product.name, unitPrice: unitPrice, imageUrl: product.primaryImage, category: product.category, experiencePreset: experiencePreset, quantity: quantity, variants: selections, notes: notes);
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
    final experience = ref.watch(storefrontExperienceProvider(widget.business.id));
    final products = ref.watch(storefrontProductsProvider(widget.business.id));
    final dishesById = products.whenOrNull(data: (value) => _dishMap(value)) ?? const <String, RestaurantDish>{};
    return experience.when(
      data: (value) => _stage(value, context, dishesById),
      loading: () => _stage(null, context, dishesById),
      error: (_, __) => _stage(null, context, dishesById),
    );
  }
}
