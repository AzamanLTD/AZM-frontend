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
        stage = _bookCtaCard(icon: BusinessCategories.fromWire(profile.categoryWire).icon, title: 'Browse Offerings', subtitle: 'See what this business offers and continue through its primary customer flow.', buttonLabel: profile.primaryActionLabel, onTap: onOpenOrderSheet ?? onOpenCatalogView, blueprint: blueprint);
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
    return _bookCtaCard(icon: BusinessCategories.fromWire(profile.categoryWire).icon, title: 'Browse Offerings', subtitle: 'See what this business offers and continue through its primary customer flow.', buttonLabel: profile.primaryActionLabel, onTap: onOpenOrderSheet ?? onOpenCatalogView, blueprint: _blueprint);
  }

  Widget _stageHeader(MarketplaceExperienceBlueprint blueprint, {required String title}) {
    if (!blueprint.showNavigationContext) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(blueprint.navigationLabel, style: TextStyle(color: colors.textTertiary, fontSize: 11))])), Text(blueprint.detailLabel, style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600))]));
  }

  Widget _restaurantStage(MarketplaceExperienceBlueprint blueprint) {
    final native = RestaurantCommitSurface(
      style: blueprint.commitStyle,
      childBuilder: (onCommitted) => RestaurantNativeMenuJourneyClean(
        businessName: business.businessName,
        sections: menuSections,
        uncategorisedProducts: uncategorisedProducts,
        dishesById: restaurantDishesById,
        colors: colors,
        onAddToTray: (product, selections, quantity) {
          onAddToTray?.call(product, selections, quantity);
          if (onAddToTray == null) onOrderProduct?.call(product);
          onCommitted();
        },
        showGallery: blueprint.showGallery,
        showSpecifications: blueprint.showSpecifications,
        showOptions: blueprint.showOptions,
        showQuantity: blueprint.showQuantity,
        dineInContext: blueprint.customerContext.enabled ? dineInContext : null,
        detailPresentation: blueprint.detailPresentation,
      ),
    );

    final reserveAction = blueprint.persistentTray
        ? Positioned(top: 10, right: 20, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.35)), backgroundColor: Colors.black.withValues(alpha: 0.28), shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9)), onPressed: onOpenOrderSheet, icon: const Icon(Icons.table_restaurant_outlined, size: 16), label: const Text('Reserve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))))
        : Positioned(left: 20, right: 20, bottom: 18, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white, elevation: 0, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: onOpenOrderSheet, icon: const Icon(Icons.table_restaurant_outlined, size: 19), label: const Text('Reserve a Table', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))));

    return Stack(fit: StackFit.expand, children: [native, Positioned(left: 0, right: 0, bottom: 0, child: IgnorePointer(child: Container(height: blueprint.persistentTray ? 54 : 96, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC060402)]))))), reserveAction]);
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
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onNavigate == null ? null : () => onNavigate!.call('/business-market/${business.bizId}/hotel-booking'), icon: Icon(blueprint.commitStyle == MarketplaceCommitStyle.liftIntoTray ? Icons.shopping_bag_outlined : Icons.hotel_outlined), label: Text(blueprint.persistentTray ? 'Open rooms & availability' : 'Continue to rooms')))),
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