import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/marketplace/marketplace_dossier_sheet.dart';
import 'package:azaman/widgets/marketplace/marketplace_experience_scope.dart';
import 'package:azaman/widgets/marketplace/retail_dossier_picker.dart';
import 'package:azaman/widgets/marketplace/restaurant_menu_journey_adapter.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';
import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/marketplace_tempo.dart';
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
        stage = _retailStage(context, blueprint);
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
        stage = _legacyStage(context, profile);
        break;
    }
    return MarketplaceExperienceScope(
      blueprint: blueprint,
      colors: colors,
      child: AnimatedSwitcher(
        duration: MarketplaceTempo.standard(context, blueprint.motionTempo),
        switchInCurve: MarketplaceTempo.enterCurve(blueprint.motionTempo),
        switchOutCurve: MarketplaceTempo.exitCurve(blueprint.motionTempo),
        child: KeyedSubtree(
          key: ValueKey('${blueprint.preset}:${blueprint.motionTempo}'),
          child: stage,
        ),
      ),
    );
  }

  Widget _legacyStage(BuildContext context, MarketplaceExperienceProfile profile) {
    if (profile.supports(MarketplaceExperienceCapability.menuFlipbook)) {
      if (_hasMenu && (onAddToTray != null || onOrderProduct != null)) return _restaurantStage(_blueprint);
      if (profile.supports(MarketplaceExperienceCapability.reservation)) return _bookCtaCard(icon: Icons.table_restaurant_outlined, title: 'Reserve a Table', subtitle: 'Request a dine-in reservation — the business will confirm or counter-propose a time.', buttonLabel: 'Request Reservation', onTap: onOpenOrderSheet, blueprint: _blueprint);
    }
    if (profile.supports(MarketplaceExperienceCapability.retailCollection)) return _retailStage(context, _blueprint);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(AzRadius.md),
            ),
            child: Icon(_navigationGlyph(blueprint.navigationMode), size: 18, color: colors.accent),
          ),
          const SizedBox(width: AzSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AzText.titleL.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AzSpace.xxs),
                Text(blueprint.navigationLabel, style: AzText.caption.copyWith(color: colors.textTertiary)),
              ],
            ),
          ),
          Text(blueprint.detailLabel, style: AzText.caption.copyWith(color: colors.textTertiary)),
        ],
      ),
    );
  }

  /// Per-navigation-mode glyph. Names verified in-repo (see the icon table in
  /// TASK-008 Step 5b); all four exist in `hugeicons_pro`.
  IconData _navigationGlyph(MarketplaceNavigationMode mode) {
    switch (mode) {
      case MarketplaceNavigationMode.contextual:
        return HugeIconsSolid.flash;
      case MarketplaceNavigationMode.floorTraverse:
        return HugeIconsSolid.bank;
      case MarketplaceNavigationMode.aisleTraverse:
        return HugeIconsSolid.store01;
      case MarketplaceNavigationMode.journeyTimeline:
        return HugeIconsSolid.arrowDataTransferHorizontal;
    }
  }

  Widget _restaurantStage(MarketplaceExperienceBlueprint blueprint) {
    return RestaurantCommitSurface(
      style: blueprint.commitStyle,
      motionTempo: blueprint.motionTempo,
      childBuilder: (onCommit) => RestaurantMenuJourneyAdapter(
        businessName: business.businessName,
        sections: menuSections,
        uncategorisedProducts: uncategorisedProducts,
        dishesById: restaurantDishesById,
        colors: colors,
        onAddToTray: (product, selections, quantity) {
          unawaited(onCommit(
            () {
              if (onAddToTray != null) {
                onAddToTray!.call(product, selections, quantity);
              } else {
                onOrderProduct?.call(product);
              }
            },
            label: product.name,
            subtitle: '${quantity} × ${product.priceUsdc.toStringAsFixed(2)} USDC',
          ));
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

  Widget _retailStage(BuildContext context, MarketplaceExperienceBlueprint blueprint) {
    if (business.products.isEmpty) return _bookCtaCard(icon: Icons.shopping_bag_outlined, title: 'Shop the Catalog', subtitle: 'Browse this business\'s full catalog and check out with escrow-backed payment protection.', buttonLabel: 'Shop Now', onTap: onOpenCatalogView, blueprint: blueprint);
    final products = business.products.take(6).map((product) => RetailProduct(id: product.id, name: product.name, description: product.description, price: product.priceUsdc, currency: 'USDC', imageUrls: product.imageUrls, tags: product.tags, available: product.isActive)).toList(growable: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stageHeader(blueprint, title: 'Bestsellers'),
      RetailCollectionBox(collection: RetailCollection(id: 'marketplace-${business.bizId}', title: 'Shop the shelf', subtitle: 'Popular items from this store', products: products), onProductTap: (product) => _openRetailDetail(context, blueprint, product)),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onOpenCatalogView, icon: Icon(blueprint.commitStyle == MarketplaceCommitStyle.liftIntoTray ? Icons.shopping_bag_outlined : Icons.arrow_forward_outlined), label: Text(blueprint.persistentTray ? 'Open full catalog' : 'Continue to catalog')))),
    ]);
  }

  /// `morph` keeps the shipped behaviour (tap -> full catalog). Every other
  /// presentation opens the shared dossier sheet, so a tap on a product now
  /// actually shows the product.
  void _openRetailDetail(BuildContext context, MarketplaceExperienceBlueprint blueprint, RetailProduct product) {
    AzamanHaptics.selection();
    if (blueprint.detailPresentation == MarketplaceDetailPresentation.morph) {
      onOpenCatalogView?.call();
      return;
    }
    showMarketplaceDossierSheet(
      context,
      presentation: blueprint.detailPresentation,
      title: product.name,
      colors: colors,
      tempo: blueprint.motionTempo,
      content: (_) => _productDossierContent(product),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onOpenCatalogView == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onOpenCatalogView!();
                },
          icon: const Icon(Icons.arrow_forward_outlined),
          label: const Text('Open full catalog'),
        ),
      ),
    );
  }

  /// The minimal `productDossier` body. TASK-012 upgrades this with swatch
  /// variants and a quantity row; the scaffold itself does not change.
  Widget _productDossierContent(RetailProduct product) {
    final price = product.price;
    final isGhs = (product.currency ?? '').toUpperCase() == 'GHS';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (product.imageUrls.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AzRadius.lg),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AzamanNetworkImage(imageUrl: product.imageUrls.first, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: AzSpace.lg),
        ],
        if (price != null) ...[
          Text(
            isGhs ? AzMoney.ghs(price) : AzMoney.usdc(price),
            style: AzText.money(colors.textPrimary, size: AzText.sizeTitleXl),
          ),
          const SizedBox(height: AzSpace.sm),
        ],
        if (product.description != null && product.description!.isNotEmpty)
          Text(product.description!, style: AzText.body.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AzSpace.md),
        Wrap(
          spacing: AzSpace.xs,
          runSpacing: AzSpace.xs,
          children: [
            _statusPill(product.available),
            for (final tag in product.tags.take(3)) _tagPill(tag),
          ],
        ),
        RetailDossierPicker(
          product: product,
          businessProfileId: business.id,
          businessName: business.businessName,
        ),
      ],
    );
  }

  Widget _statusPill(bool available) {
    return Container(
      padding: AzSpace.tag,
      decoration: BoxDecoration(
        color: available ? colors.accentSurface : colors.softSurface,
        borderRadius: AzRadius.brPill,
      ),
      child: Text(
        available ? 'In stock' : 'Unavailable',
        style: AzText.label.copyWith(color: available ? colors.accent : colors.textTertiary),
      ),
    );
  }

  Widget _tagPill(String tag) {
    return Container(
      padding: AzSpace.tag,
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: AzRadius.brPill,
      ),
      child: Text(tag, style: AzText.caption.copyWith(color: colors.textSecondary)),
    );
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
