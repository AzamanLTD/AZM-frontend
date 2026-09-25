// =============================================================================
// Storefront Widget Registry
//
// Maps widgetType strings to their Flutter widget builders.
// The renderer uses this to look up the correct widget for each tile.
// =============================================================================

import 'package:flutter/widgets.dart';

import '../models/storefront_models.dart';
import '../widgets/hero_header_widget.dart';
import '../widgets/quick_info_bar_widget.dart';
import '../widgets/product_grid_widget.dart';
import '../widgets/showcase_gallery_widget.dart';
import '../widgets/review_carousel_widget.dart';
import '../widgets/contact_card_widget.dart';
import '../widgets/location_map_widget.dart';
import '../widgets/action_buttons_widget.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/promo_banner_widget.dart';
import '../widgets/social_feed_widget.dart';
import '../widgets/live_stats_widget.dart';
import '../widgets/animated_counter_widget.dart';
import '../widgets/custom_html_widget.dart';
import '../widgets/gradient_hero_widget.dart';
import '../widgets/retail_collection_box_widget.dart';
import '../../marketplace/experiences/retail/storefront_retail_checkout_gateway.dart';
import '../widgets/fallback_widget.dart';

typedef StorefrontWidgetBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> props,
  StorefrontBusinessInfo business,
  String? businessProfileId,
);

class StorefrontWidgetRegistry {
  static final Map<String, StorefrontWidgetBuilder> _registry = {
    'hero_header': (ctx, props, biz, _) => HeroHeaderWidget(props: props, business: biz),
    'quick_info_bar': (ctx, props, biz, _) => QuickInfoBarWidget(props: props, business: biz),
    'product_grid': (ctx, props, biz, _) => ProductGridWidget(props: props, business: biz),
    'showcase_gallery': (ctx, props, biz, _) => ShowcaseGalleryWidget(props: props, business: biz),
    'review_carousel': (ctx, props, biz, _) => ReviewCarouselWidget(props: props, business: biz),
    'contact_card': (ctx, props, biz, _) => ContactCardWidget(props: props, business: biz),
    'location_map': (ctx, props, biz, _) => LocationMapWidget(props: props, business: biz),
    'action_buttons': (ctx, props, biz, _) => ActionButtonsWidget(props: props, business: biz),
    'video_player': (ctx, props, biz, _) => VideoPlayerWidget(props: props, business: biz),
    'promo_banner': (ctx, props, biz, _) => PromoBannerWidget(props: props, business: biz),
    'social_feed': (ctx, props, biz, _) => SocialFeedWidget(props: props, business: biz),
    'live_stats': (ctx, props, biz, _) => LiveStatsWidget(props: props, business: biz),
    'animated_counter': (ctx, props, biz, _) => AnimatedCounterWidget(props: props, business: biz),
    'custom_html': (ctx, props, biz, _) => CustomHtmlWidget(props: props, business: biz),
    'gradient_hero': (ctx, props, biz, _) => GradientHeroWidget(props: props, business: biz),
    'retail_collection_box': (ctx, props, biz, businessProfileId) {
      return RetailCollectionBoxWidget(
        props: props,
        business: biz,
        checkoutGateway: businessProfileId != null
            ? StorefrontRetailCheckoutGateway(businessProfileId: businessProfileId)
            : null,
      );
    },
  };

  static StorefrontWidgetBuilder? getBuilder(String widgetType) => _registry[widgetType];

  static bool isRegistered(String widgetType) => _registry.containsKey(widgetType);

  static List<String> get registeredTypes => _registry.keys.toList();

  static Widget buildWidget(
    BuildContext context,
    RenderTile tile,
    StorefrontBusinessInfo business, {
    String? businessProfileId,
  }) {
    final builder = _registry[tile.widgetType];
    if (builder == null) return FallbackWidget(widgetType: tile.widgetType);
    return builder(context, tile.props, business, businessProfileId);
  }
}
