import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/storefront_models.dart';
import '../services/storefront_tracking_service.dart';
import '../core/storefront_tracking_scope.dart';
import '../core/scroll_to_products_notification.dart';

class ActionButtonsWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ActionButtonsWidget({super.key, required this.props, required this.business});

  void _trackCta(BuildContext context, String action) {
    final bizId = StorefrontTrackingScope.of(context);
    if (bizId != null) {
      StorefrontTrackingService.instance.trackEvent(
        bizId,
        'cta_click',
        {'action': action, 'widgetType': 'action_buttons'},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOrder = props['showOrder'] ?? true;
    final showBook = props['showBook'] ?? false;
    final showFollow = props['showFollow'] ?? true;
    final showShare = props['showShare'] ?? true;

    final buttons = <Widget>[];
    if (showOrder) buttons.add(ElevatedButton.icon(
      onPressed: () {
        _trackCta(context, 'order');
        ScrollToProductsNotification(action: 'order').dispatch(context);
      },
      icon: const Icon(Icons.shopping_bag, size: 18),
      label: const Text('Order Now'),
    ));
    if (showBook) buttons.add(ElevatedButton.icon(
      onPressed: () => _trackCta(context, 'book'),
      icon: const Icon(Icons.calendar_today, size: 18),
      label: const Text('Book'),
    ));
    if (showFollow) buttons.add(OutlinedButton.icon(
      onPressed: () => _trackCta(context, 'follow'),
      icon: const Icon(Icons.person_add, size: 18),
      label: const Text('Follow'),
    ));
    if (showShare) buttons.add(OutlinedButton.icon(
      onPressed: () {
        _trackCta(context, 'share');
        final bizId = StorefrontTrackingScope.of(context);
        if (bizId != null) {
          Share.share('Check out this storefront on AZAMAN! https://azaman.app/storefront/$bizId');
        }
      },
      icon: const Icon(Icons.share, size: 18),
      label: const Text('Share'),
    ));

    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: buttons);
  }
}
