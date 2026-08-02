import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class LiveStatsWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const LiveStatsWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final showFollowers = props['showFollowers'] ?? true;
    final showReviews = props['showReviews'] ?? true;
    final showOrders = props['showOrders'] ?? true;
    final showRating = props['showRating'] ?? true;

    final stats = <_StatItem>[];
    if (showFollowers) stats.add(const _StatItem(Icons.people, '1.2K', 'Followers'));
    if (showReviews) stats.add(const _StatItem(Icons.star, '348', 'Reviews'));
    if (showOrders) stats.add(const _StatItem(Icons.shopping_bag, '5.4K', 'Orders'));
    if (showRating) stats.add(const _StatItem(Icons.thumb_up, '4.5', 'Rating'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats.map((s) => _buildStat(context, s)).toList(),
      ),
    );
  }

  Widget _buildStat(BuildContext context, _StatItem stat) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(stat.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(stat.icon, size: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 3),
          Text(stat.label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
        ]),
      ],
    );
  }
}

class _StatItem {
  final IconData icon;
  final String value;
  final String label;
  const _StatItem(this.icon, this.value, this.label);
}
