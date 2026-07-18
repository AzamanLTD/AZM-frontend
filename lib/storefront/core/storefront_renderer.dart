// =============================================================================
// Storefront Renderer
//
// Takes a StorefrontRenderResponse and renders the complete SDUI storefront.
// The renderer iterates through tiles in order and delegates to the widget
// registry for each tile.
// =============================================================================

import 'package:flutter/material.dart';

import '../models/storefront_models.dart';
import 'storefront_theme_resolver.dart';
import 'storefront_widget_registry.dart';

class StorefrontRenderer extends StatelessWidget {
  final StorefrontRenderResponse response;

  const StorefrontRenderer({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    final theme = StorefrontThemeResolver.resolve(response.theme);
    final spacingScale = response.theme.spacingScale ?? 1.0;
    final tiles = response.layout.tiles;

    // Sort tiles by position (row first, then col)
    final sortedTiles = List<RenderTile>.from(tiles)
      ..sort((a, b) {
        final rowCompare = a.position.row.compareTo(b.position.row);
        if (rowCompare != 0) return rowCompare;
        return a.position.col.compareTo(b.position.col);
      });

    return Theme(
      data: theme,
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: SingleChildScrollView(
          child: Column(
            children: sortedTiles.map((tile) {
              return _TileWrapper(
                tile: tile,
                spacingScale: spacingScale,
                business: response.business,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TileWrapper extends StatelessWidget {
  final RenderTile tile;
  final double spacingScale;
  final StorefrontBusinessInfo business;

  const _TileWrapper({
    required this.tile,
    required this.spacingScale,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final padding = 16.0 * spacingScale;

    return Padding(
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

    return Theme(
      data: themeData,
      child: Container(
        color: themeData.scaffoldBackgroundColor,
        child: SingleChildScrollView(
          child: Column(
            children: sortedTiles.map((tile) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
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
            }).toList(),
          ),
        ),
      ),
    );
  }
}
