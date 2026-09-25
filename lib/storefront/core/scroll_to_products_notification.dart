import 'package:flutter/widgets.dart';

// Notification dispatched by SDUI action buttons (e.g. "Order Now") to tell
// the parent StorefrontScreen to scroll down to the products section.
class ScrollToProductsNotification extends Notification {
  final String action;
  ScrollToProductsNotification({this.action = 'order'});
}
