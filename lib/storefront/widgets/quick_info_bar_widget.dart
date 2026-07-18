import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class QuickInfoBarWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const QuickInfoBarWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final showHours = props['showHours'] ?? true;
    final showRating = props['showRating'] ?? true;
    final showCategory = props['showCategory'] ?? true;
    final customInfo = props['customInfo'] as String? ?? '';

    final items = <Widget>[];
    if (showCategory && business.category != null) {
      items.add(_chip(Icons.store, _formatCategory(business.category!)));
    }
    if (showHours) items.add(_chip(Icons.access_time, 'Open Now'));
    if (showRating) items.add(_chip(Icons.star, '4.5'));
    if (customInfo.isNotEmpty) items.add(_chip(Icons.info_outline, customInfo));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: items,
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Builder(builder: (ctx) {
      final accent = Theme.of(ctx).colorScheme.primary;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface)),
        ],
      );
    });
  }

  String _formatCategory(String category) {
    return category.split('_').map((w) =>
      w.isNotEmpty ? '${w[0]}${w.substring(1).toLowerCase()}' : w
    ).join(' ');
  }
}
