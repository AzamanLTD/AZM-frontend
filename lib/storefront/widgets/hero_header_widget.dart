import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/storefront_models.dart';

class HeroHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const HeroHeaderWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final mediaUrl = props['mediaUrl'] as String?;
    final title = props['title'] as String? ?? business.name;
    final subtitle = props['subtitle'] as String?;
    final overlayOpacity = (props['overlayOpacity'] ?? 0.3).toDouble();
    final height = props['height'] as String? ?? 'standard';

    final heightValue = switch (height) {
      'compact' => 140.0,
      'tall' => 260.0,
      _ => 200.0,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: heightValue,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (mediaUrl != null && mediaUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: mediaUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surface),
                errorWidget: (_, __, ___) => _gradientBackground(context),
              )
            else
              _gradientBackground(context),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(overlayOpacity),
                    Colors.black.withOpacity(overlayOpacity * 1.5),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20, right: 20, bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBackground(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.7), accent.withOpacity(0.4)],
        ),
      ),
    );
  }
}
