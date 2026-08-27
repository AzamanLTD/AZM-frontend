// =============================================================================
// Storefront Renderer
//
// Takes a StorefrontRenderResponse and renders the complete SDUI storefront.
// The renderer iterates through tiles in order and delegates to the widget
// registry for each tile.
//
// When [businessProfileId] is provided, a StorefrontTrackingScope wraps the
// entire tree so widgets can fire analytics events, and each tile is wrapped
// with a StorefrontVisibilityDetector for widget_view tracking.
// =============================================================================

import 'package:flutter/material.dart';

import '../models/storefront_models.dart';
import 'storefront_theme_resolver.dart';
import 'storefront_widget_registry.dart';
import 'storefront_tracking_scope.dart';
import '../widgets/storefront_visibility_detector.dart';

class StorefrontRenderer extends StatelessWidget {
  final StorefrontRenderResponse response;

  /// When provided, enables analytics tracking for this render.
  final String? businessProfileId;

  const StorefrontRenderer({super.key, required this.response, this.businessProfileId});

  @override
  Widget build(BuildContext context) {
    final theme = StorefrontThemeResolver.resolve(response.theme);
    final spacingScale = response.theme.spacingScale ?? 1.0;
    final tiles = List<RenderTile>.from(response.layout.tiles)
      ..sort((a, b) {
        final rowCompare = a.position.row.compareTo(b.position.row);
        if (rowCompare != 0) return rowCompare;
        return a.position.col.compareTo(b.position.col);
      });

    // Use a lazy list rather than building every storefront tile eagerly.
    // Storefronts can grow to many sections, and some registered widgets may
    // contain image-heavy or otherwise expensive subtrees.
    final scrollChild = ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        return _TileWrapper(
          tile: tiles[index],
          spacingScale: spacingScale,
          business: response.business,
          businessProfileId: businessProfileId,
          widgetIndex: index,
        );
      },
    );

    return Theme(
      data: theme,
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: businessProfileId != null
            ? StorefrontTrackingScope(
                businessProfileId: businessProfileId,
                child: scrollChild,
              )
            : scrollChild,
      ),
    );
  }
}

class _TileWrapper extends StatelessWidget {
  final RenderTile tile;
  final double spacingScale;
  final StorefrontBusinessInfo business;
  final String? businessProfileId;
  final int widgetIndex;

  const _TileWrapper({
    required this.tile,
    required this.spacingScale,
    required this.business,
    this.businessProfileId,
    required this.widgetIndex,
  });

  @override
  Widget build(BuildContext context) {
    final padding = 16.0 * spacingScale;

    final child = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 0.4,
      ),
      child: StorefrontWidgetRegistry.buildWidget(
        context,
        tile,
        business,
      ),
    );

    // Wrap with visibility tracking only when businessProfileId is provided
    if (businessProfileId != null) {
      return StorefrontVisibilityDetector(
        businessProfileId: businessProfileId!,
        widgetType: tile.widgetType,
        widgetIndex: widgetIndex,
        child: child,
      );
    }

    return child;
  }
}

/// A preview widget for the layout editor (shows tiles in a grid).
class StorefrontPreviewRenderer extends StatelessWidget {
  final LayoutJson layout;
  final StorefrontTheme theme;
  final StorefrontBusinessInfo business;

  const StorefrontPreviewRenderer({
    super.key,
    required this.layout,
    required this.theme,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = StorefrontThemeResolver.resolve(
      StorefrontThemeInfo(
        id: theme.id,
        key: theme.key,
        name: theme.name,
        tokenSet: theme.tokenSet,
        typography: theme.typography,
        borderRadius: theme.borderRadius,
        spacingScale: theme.spacingScale,
      ),
    );

    final sortedTiles = List<LayoutTile>.from(layout.tiles)
      ..sort((a, b) {
        final rowCompare = a.position.row.compareTo(b.position.row);
        if (rowCompare != 0) return rowCompare;
        return a.position.col.compareTo(b.position.col);
      });
    final spacingScale = theme.spacingScale ?? 1.0;

    return Theme(
      data: themeData,
      child: Container(
        color: themeData.scaffoldBackgroundColor,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: sortedTiles.length,
          itemBuilder: (context, index) {
            final tile = sortedTiles[index];
            final padding = 16.0 * spacingScale;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: padding * 0.4,
              ),
              child: StorefrontWidgetRegistry.buildWidget(
                context,
                RenderTile(
                  id: tile.id,
                  widgetType: tile.widgetType,
                  position: tile.position,
                  props: tile.props,
                ),
                business,
              ),
            );
          },
        ),
      ),
    );
  }
}
