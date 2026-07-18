import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class ReviewCarouselWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ReviewCarouselWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? 'Reviews';
    final maxReviews = props['maxReviews'] ?? 5;
    final minRating = props['minRating'] ?? 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: maxReviews,
            itemBuilder: (ctx, i) => Container(
              width: 240,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(ctx).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: List.generate(5, (s) => Icon(Icons.star, size: 14, color: s < minRating ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).dividerColor))),
                  const SizedBox(height: 6),
                  Text('Great experience!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text('Lorem ipsum dolor sit amet, consectetur adipiscing elit.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
