// =============================================================================
// Storefront Tracking Scope
//
// InheritedWidget that makes the businessProfileId available to all
// storefront widgets in the tree. Widgets use this to fire analytics events
// (cta_click, product_tap, etc.) without changing the widget registry interface.
// =============================================================================

import 'package:flutter/material.dart';

class StorefrontTrackingScope extends InheritedWidget {
  /// The businessProfileId to send analytics events to.
  /// When null, tracking is disabled (e.g., in the layout editor preview).
  final String? businessProfileId;

  const StorefrontTrackingScope({
    super.key,
    this.businessProfileId,
    required super.child,
  });

  /// Get the tracking businessProfileId from the nearest ancestor scope.
  static String? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StorefrontTrackingScope>();
    return scope?.businessProfileId;
  }

  @override
  bool updateShouldNotify(StorefrontTrackingScope oldWidget) {
    return businessProfileId != oldWidget.businessProfileId;
  }
}
