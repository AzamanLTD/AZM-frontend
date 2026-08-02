import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class SocialFeedWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const SocialFeedWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final platform = props['platform'] as String? ?? 'instagram';
    final handle = props['handle'] as String? ?? '';
    final maxPosts = props['maxPosts'] ?? 6;

    final icon = switch (platform) {
      'tiktok' => Icons.music_note,
      'facebook' => Icons.facebook,
      _ => Icons.camera_alt,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(handle.isNotEmpty ? '@$handle' : 'Social Feed', style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        SizedBox(
          height: 180,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: maxPosts,
            itemBuilder: (ctx, i) => Container(
              width: 90,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 28, color: Theme.of(ctx).colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
