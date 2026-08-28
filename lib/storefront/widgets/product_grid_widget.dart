import 'package:flutter/material.dart';
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
    final maxItems = _positiveInt(props['maxItems'], fallback: 6, max: 50);
    final columns = _positiveInt(props['columns'], fallback: 2, max: 4);
    final showPrice = props['showPrice'] is bool ? props['showPrice'] as bool : true;
    final rawItems = props['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).take(maxItems).toList()
        : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (items.isEmpty)
          _EmptyProductState(),
        if (items.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.75,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, i) => _ProductCard(
              product: items[i],
              showPrice: showPrice,
            ),
          ),
      ],
    );
  }

  static int _positiveInt(dynamic value, {required int fallback, required int max}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed < 1) return fallback;
    return parsed.clamp(1, max);
  }
}

class _EmptyProductState extends StatelessWidget {
  const _EmptyProductState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 30, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('No products available yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Check back soon for new items.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool showPrice;

  const _ProductCard({required this.product, required this.showPrice});

  void _trackTap(BuildContext context) {
    final bizId = StorefrontTrackingScope.of(context);
    if (bizId == null) return;

    StorefrontTrackingService.instance.trackEvent(
      bizId,
      'product_tap',
      {
        'productId': product['id'] ?? product['productId'],
        'widgetType': 'product_grid',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (product['name'] ?? product['title'] ?? 'Product').toString();
    final imageUrl = (product['imageUrl'] ?? product['image'] ?? '').toString();
    final price = product['price'];

    return Semantics(
      button: true,
      label: name,
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: InkWell(
          onTap: () => _trackTap(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  width: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _ImageFallback(),
                        )
                      : _ImageFallback(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showPrice && price != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _formatPrice(price, product['currency']?.toString()),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatPrice(dynamic value, String? currency) {
    final symbol = switch (currency?.toUpperCase()) {
      'GHS' => 'GH₵',
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currency?.isNotEmpty == true ? '$currency ' : '',
    };
    if (value is num) return '$symbol${value.toStringAsFixed(2)}';
    return '$symbol$value';
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 34, color: scheme.onSurfaceVariant),
    );
  }
}
