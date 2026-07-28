import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/storefront_models.dart';
import '../services/storefront_tracking_service.dart';
import '../core/storefront_tracking_scope.dart';

class ProductGridWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ProductGridWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? 'Featured';
    final maxItems = props['maxItems'] ?? 6;
    final columns = props['columns'] ?? 2;
    final showPrice = props['showPrice'] ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemCount: maxItems,
          itemBuilder: (ctx, i) => _ProductCard(
            index: i,
            showPrice: showPrice,
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final int index;
  final bool showPrice;

  const _ProductCard({required this.index, required this.showPrice});

  void _trackTap(BuildContext context) {
    final bizId = StorefrontTrackingScope.of(context);
    if (bizId != null) {
      StorefrontTrackingService.instance.trackEvent(
        bizId,
        'product_tap',
        {'productIndex': index, 'widgetType': 'product_grid'},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _trackTap(context),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: Container(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.restaurant, size: 40, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Item ${index + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (showPrice)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('\$${(index + 1) * 5}.99', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
