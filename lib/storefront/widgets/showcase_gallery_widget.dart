import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class ShowcaseGalleryWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ShowcaseGalleryWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? 'Gallery';
    final maxItems = props['maxItems'] ?? 8;
    final autoplay = props['autoplay'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: maxItems,
            itemBuilder: (ctx, i) => Container(
              width: 140,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.image, size: 36, color: Theme.of(ctx).colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
