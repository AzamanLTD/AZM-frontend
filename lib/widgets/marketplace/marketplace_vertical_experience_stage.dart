import 'dart:async';

import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/marketplace/restaurant_native_menu_journey_clean.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';
import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/widgets/marketplace/hotel_floor_plan_preview.dart';
import 'package:azaman/widgets/marketplace/service_experience_stage.dart';
import 'package:azaman/widgets/marketplace/transit_seat_preview.dart';

class MarketplaceVerticalExperienceStage extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final void Function(String route)? onNavigate;
  final VoidCallback? onOpenOrderSheet;
  final VoidCallback? onOpenCatalogView;
  final List<CatalogSection> menuSections;
  final List<BusinessProduct> uncategorisedProducts;
  final void Function(BusinessProduct product)? onOrderProduct;
  final void Function(BusinessProduct product, Map<String, String> selections, int quantity)? onAddToTray;
  final Map<String, RestaurantDish> restaurantDishesById;
  final String? dineInContext;
  final Map<String, dynamic>? experience;

  const MarketplaceVerticalExperienceStage({
    super.key,
    required this.business,
    required this.colors,
    this.onNavigate,
    this.onOpenOrderSheet,
    this.onOpenCatalogView,
    this.menuSections = const [],
    this.uncategorisedProducts = const [],
    this.onOrderProduct,
    this.onAddToTray,
    this.restaurantDishesById = const {},
    this.dineInContext,
    this.experience,
  });

  bool get _hasMenu => menuSections.isNotEmpty || uncategorisedProducts.isNotEmpty;
  MarketplaceExperienceBlueprint get _blueprint => MarketplaceExperienceBlueprint.fromJson(experience, business.category);

  @override
  Widget build(BuildContext context) {
    final blueprint = _blueprint;
    final profile = MarketplaceExperienceCatalog.fromCategory(business.category);
    late final Widget stage;
    switch (blueprint.preset) {
      case 'DINING_JOURNEY':
        stage = _hasMenu && (onAddToTray != null || onOrderProduct != null)
            ? _restaurantStage(blueprint)
            : _bookCtaCard(icon: Icons.table_restaurant_outlined, title: 'Reserve a Table', subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.', buttonLabel: 'Request Reservation', onTap: onOpenOrderSheet, blueprint: blueprint);
        break;
      case 'SHOP_FLOOR':
        stage = _retailStage(blueprint);
        break;
      case 'BUILDING_WALK':
        stage = _hotelStage(blueprint);
        break;
      case 'TRAVEL_JOURNEY':
        stage = _transitStage(blueprint);
        break;
      case 'SERVICE_JOURNEY':
        stage = ServiceExperienceStage(
          business: business,
          colors: colors,
          offerings: business.products,
          blueprint: blueprint,
          onContinue: onOpenOrderSheet ?? onOpenCatalogView,
          onOpenCatalog: onOpenCatalogView,
        );
        break;
      default:
        stage = _legacyStage(profile);
        break;
    }
    return AnimatedSwitcher(duration: blueprint.motionDuration(context), switchInCurve: MotionTokens.enter, switchOutCurve: MotionTokens.exit, child: KeyedSubtree(key: ValueKey('${blueprint.preset}:${blueprint.motionTempo}'), child: stage));
  }

  Widget _legacyStage(MarketplaceExperienceProfile profile) {
    if (profile.supports(MarketplaceExperienceCapability.menuFlipbook)) {
      if (_hasMenu && (onAddToTray != null || onOrderProduct != null)) return _restaurantStage(_blueprint);
      if (profile.supports(MarketplaceExperienceCapability.reservation)) return _bookCtaCard(icon: Icons.table_restaurant_outlined, title: 'Reserve a Table', subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.', buttonLabel: 'Request Reservation', onTap: onOpenOrderSheet, blueprint: _blueprint);
    }
    if (profile.supports(MarketplaceExperienceCapability.retailCollection)) return _retailStage(_blueprint);
    if (profile.supports(MarketplaceExperienceCapability.hotelFloorMap)) return _hotelStage(_blueprint);
    if (profile.supports(MarketplaceExperienceCapability.transitSeatMap)) return _transitStage(_blueprint);
    return ServiceExperienceStage(
      business: business,
      colors: colors,
      offerings: business.products,
      blueprint: _blueprint,
      onContinue: onOpenOrderSheet ?? onOpenCatalogView,
      onOpenCatalog: onOpenCatalogView,
    );
  }

  Widget _stageHeader(MarketplaceExperienceBlueprint blueprint, {required String title}) {
    if (!blueprint.showNavigationContext) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(blueprint.navigationLabel, style: TextStyle(color: colors.textTertiary, fontSize: 11))])), Text(blueprint.detailLabel, style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600))]));
  }

  Widget _restaurantStage(MarketplaceExperienceBlueprint blueprint) {
    return RestaurantCommitSurface(
      style: blueprint.commitStyle,
      childBuilder: (onCommit) => RestaurantNativeMenuJourneyClean(
        businessName: business.businessName,
        sections: menuSections,
        uncategorisedProducts: uncategorisedProducts,
        dishesById: restaurantDishesById,
        colors: colors,
        onAddToTray: (product, selections, quantity) {
          unawaited(onCommit(() {
            if (onAddToTray != null) {
              onAddToTray!.call(product, selections, quantity);
            } else {
              onOrderProduct?.call(product);
            }
          }));
        },
        showGallery: blueprint.showGallery,
        showSpecifications: blueprint.showSpecifications,
        showOptions: blueprint.showOptions,
        showQuantity: blueprint.showQuantity,
        dineInContext: blueprint.customerContext.enabled ? dineInContext : null,
        detailPresentation: blueprint.detailPresentation,
      ),
    );
  }

  Widget _retailStage(MarketplaceExperienceBlueprint blueprint) {
    if (business.products.isEmpty) return _bookCtaCard(icon: Icons.shopping_bag_outlined, title: 'Shop the Catalog', subtitle: 'Browse this business\'s full catalog and check out with escrow-backed payment protection.', buttonLabel: 'Shop Now', onTap: onOpenCatalogView, blueprint: blueprint);
    final products = business.products.take(6).map((product) => RetailProduct(id: product.id, name: product.name, description: product.description, price: product.priceUsdc, currency: 'USDC', imageUrls: product.imageUrls, tags: product.tags, available: product.isActive)).toList(growable: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stageHeader(blueprint, title: 'Bestsellers'),
      RetailCollectionBox(collection: RetailCollection(id: 'marketplace-${business.bizId}', title: 'Shop the shelf', subtitle: 'Popular items from this store', products: products), onProductTap: (_) => onOpenCatalogView?.call()),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onOpenCatalogView, icon: Icon(blueprint.commitStyle == MarketplaceCommitStyle.liftIntoTray ? Icons.shopping_bag_outlined : Icons.arrow_forward_outlined), label: Text(blueprint.persistentTray ? 'Open full catalog' : 'Continue to catalog')))),
    ]);
  }

  Widget _hotelStage(MarketplaceExperienceBlueprint blueprint) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (blueprint.showNavigationContext) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: Text(blueprint.navigationLabel, style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600))),
      HotelFloorPlanPreview(products: business.products, selectedRoomId: null, onRoomSelected: (_) => onNavigate?.call('/business-market/${business.bizId}/hotel-booking'), colors: colors),
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onNavigate == null ? null : () => onNavigate!.call('/business-market/${business.bizId}/hotel-booking'), icon: const Icon(Icons.hotel_outlined), label: const Text('Continue to rooms')))),
    ]);
  }

  Widget _transitStage(MarketplaceExperienceBlueprint blueprint) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_stageHeader(blueprint, title: 'Choose your ride'), TransitSeatPreview(businessProfileId: business.id, colors: colors, onOpenTrips: () => onNavigate?.call('/business-market/${business.bizId}/transit'))]);
  }

  IconData _commitIcon(MarketplaceExperienceBlueprint blueprint) {
    switch (blueprint.commitStyle) {
      case MarketplaceCommitStyle.paperRip: return Icons.receipt_long_outlined;
      case MarketplaceCommitStyle.liftIntoTray: return Icons.shopping_bag_outlined;
      case MarketplaceCommitStyle.material: return Icons.arrow_forward_outlined;
    }
  }

  Widget _bookCtaCard({required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onTap, required MarketplaceExperienceBlueprint blueprint}) {
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: colors.accentSurface, shape: BoxShape.circle), child: Icon(icon, size: 40, color: colors.accent)), const SizedBox(height: 18), Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, fontSize: 13)), const SizedBox(height: 20), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)), onPressed: onTap, icon: Icon(_commitIcon(blueprint)), label: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)))])));
  }
}
