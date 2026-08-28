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
import '../widgets/fallback_widget.dart';

typedef StorefrontWidgetBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> props,
  StorefrontBusinessInfo business,
);

class StorefrontWidgetRegistry {
  static final Map<String, StorefrontWidgetBuilder> _registry = {
    'hero_header': (ctx, props, biz) => HeroHeaderWidget(props: props, business: biz),
    'quick_info_bar': (ctx, props, biz) => QuickInfoBarWidget(props: props, business: biz),
    'product_grid': (ctx, props, biz) => ProductGridWidget(props: props, business: biz),
    'showcase_gallery': (ctx, props, biz) => ShowcaseGalleryWidget(props: props, business: biz),
    'review_carousel': (ctx, props, biz) => ReviewCarouselWidget(props: props, business: biz),
    'contact_card': (ctx, props, biz) => ContactCardWidget(props: props, business: biz),
    'location_map': (ctx, props, biz) => LocationMapWidget(props: props, business: biz),
    'action_buttons': (ctx, props, biz) => ActionButtonsWidget(props: props, business: biz),
    'video_player': (ctx, props, biz) => VideoPlayerWidget(props: props, business: biz),
    'promo_banner': (ctx, props, biz) => PromoBannerWidget(props: props, business: biz),
    'social_feed': (ctx, props, biz) => SocialFeedWidget(props: props, business: biz),
    'live_stats': (ctx, props, biz) => LiveStatsWidget(props: props, business: biz),
    'animated_counter': (ctx, props, biz) => AnimatedCounterWidget(props: props, business: biz),
    'custom_html': (ctx, props, biz) => CustomHtmlWidget(props: props, business: biz),
    'gradient_hero': (ctx, props, biz) => GradientHeroWidget(props: props, business: biz),
    'retail_collection_box': (ctx, props, biz) => RetailCollectionBoxWidget(props: props, business: biz),
  };

  static StorefrontWidgetBuilder? getBuilder(String widgetType) => _registry[widgetType];

  static bool isRegistered(String widgetType) => _registry.containsKey(widgetType);

  static List<String> get registeredTypes => _registry.keys.toList();

  static Widget buildWidget(
    BuildContext context,
    RenderTile tile,
    StorefrontBusinessInfo business,
  ) {
    final builder = _registry[tile.widgetType];
    if (builder == null) return FallbackWidget(widgetType: tile.widgetType);
    return builder(context, tile.props, business);
  }
}
