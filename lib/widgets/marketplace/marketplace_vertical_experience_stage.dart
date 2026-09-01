import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/widgets/restaurant_menu_flip_book.dart';
import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/widgets/marketplace/hotel_floor_plan_preview.dart';
import 'package:azaman/widgets/marketplace/transit_seat_preview.dart';

/// Category-native business experience stage used by marketplace business
/// pages. The shared shell stays stable while the interaction surface changes
/// to match what the business actually sells.
///
/// When a published Experience Blueprint is available, its constrained preset
/// is the rendering authority. The capability catalog remains the safe
/// compatibility fallback for older businesses without a published blueprint.
class MarketplaceVerticalExperienceStage extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final void Function(String route)? onNavigate;
  final VoidCallback? onOpenOrderSheet;
  final VoidCallback? onOpenCatalogView;
  final List<CatalogSection> menuSections;
  final List<BusinessProduct> uncategorisedProducts;
  final void Function(BusinessProduct product)? onOrderProduct;
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
    this.experience,
  });

  bool get _hasMenu =>
      menuSections.isNotEmpty || uncategorisedProducts.isNotEmpty;

  String? get _preset => experience?['preset'] as String?;

  @override
  Widget build(BuildContext context) {
    final profile = MarketplaceExperienceCatalog.fromCategory(business.category);

    // Published experience contract takes precedence over legacy category
    // branching. It describes the journey grammar, while domain capabilities
    // still decide whether the necessary source data/action is available.
    switch (_preset) {
      case 'DINING_JOURNEY':
        if (_hasMenu && onOrderProduct != null) return _restaurantStage();
        return _bookCtaCard(
          icon: Icons.table_restaurant_outlined,
          title: 'Reserve a Table',
          subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.',
          buttonLabel: 'Request Reservation',
          onTap: onOpenOrderSheet,
        );
      case 'SHOP_FLOOR':
        return _retailStage();
      case 'BUILDING_WALK':
        return _hotelStage();
      case 'TRAVEL_JOURNEY':
        return _transitStage();
      case 'SERVICE_JOURNEY':
        return _bookCtaCard(
          icon: BusinessCategories.fromWire(profile.categoryWire).icon,
          title: 'Browse Offerings',
          subtitle: 'See what this business offers and continue through its primary customer flow.',
          buttonLabel: profile.primaryActionLabel,
          onTap: onOpenOrderSheet ?? onOpenCatalogView,
        );
    }

    // Legacy compatibility path for businesses that have not published an
    // Experience Blueprint yet.
    if (profile.supports(MarketplaceExperienceCapability.menuFlipbook)) {
      if (_hasMenu && onOrderProduct != null) return _restaurantStage();
      if (profile.supports(MarketplaceExperienceCapability.reservation)) {
        return _bookCtaCard(
          icon: Icons.table_restaurant_outlined,
          title: 'Reserve a Table',
          subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.',
          buttonLabel: 'Request Reservation',
          onTap: onOpenOrderSheet,
        );
      }
    }

    if (profile.supports(MarketplaceExperienceCapability.retailCollection)) {
      return _retailStage();
    }
    if (profile.supports(MarketplaceExperienceCapability.hotelFloorMap)) {
      return _hotelStage();
    }
    if (profile.supports(MarketplaceExperienceCapability.transitSeatMap)) {
      return _transitStage();
    }

    return _bookCtaCard(
      icon: BusinessCategories.fromWire(profile.categoryWire).icon,
      title: 'Browse Offerings',
      subtitle: 'See what this business offers and continue through its primary customer flow.',
      buttonLabel: profile.primaryActionLabel,
      onTap: onOpenOrderSheet ?? onOpenCatalogView,
    );
  }

  Widget _restaurantStage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        RestaurantMenuFlipBook(
          businessName: business.businessName,
          logoUrl: business.logoUrl,
          sections: menuSections,
          uncategorisedProducts: uncategorisedProducts,
          colors: colors,
          onOrder: onOrderProduct!,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              height: 96,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC060402)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: onOpenOrderSheet,
            icon: const Icon(Icons.table_restaurant_outlined, size: 19),
            label: const Text(
              'Reserve a Table',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _retailStage() {
    if (business.products.isEmpty) {
      return _bookCtaCard(
        icon: Icons.shopping_bag_outlined,
        title: 'Shop the Catalog',
        subtitle: 'Browse this business\'s full catalog and check out with escrow-backed payment protection.',
        buttonLabel: 'Shop Now',
        onTap: onOpenCatalogView,
      );
    }

    final products = business.products
        .take(6)
        .map((product) => RetailProduct(
              id: product.id,
              name: product.name,
              description: product.description,
              price: product.priceUsdc,
              currency: 'USDC',
              imageUrls: product.imageUrls,
              tags: product.tags,
              available: product.isActive,
            ))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            'Bestsellers',
            style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        RetailCollectionBox(
          collection: RetailCollection(
            id: 'marketplace-${business.bizId}',
            title: 'Shop the shelf',
            subtitle: 'Popular items from this store',
            products: products,
          ),
          onProductTap: (_) => onOpenCatalogView?.call(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenCatalogView,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Open full catalog'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hotelStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HotelFloorPlanPreview(
          products: business.products,
          selectedRoomId: null,
          onRoomSelected: (_) => onNavigate?.call('/business-market/${business.bizId}/hotel-booking'),
          colors: colors,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNavigate == null ? null : () => onNavigate!.call('/business-market/${business.bizId}/hotel-booking'),
              icon: const Icon(Icons.hotel_outlined),
              label: const Text('Open rooms & availability'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _transitStage() {
    return TransitSeatPreview(
      businessProfileId: business.id,
      colors: colors,
      onOpenTrips: () => onNavigate?.call('/business-market/${business.bizId}/transit'),
    );
  }

  Widget _bookCtaCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onTap,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: colors.accentSurface, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: colors.accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: onTap,
              child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
