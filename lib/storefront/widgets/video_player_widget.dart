import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class VideoPlayerWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const VideoPlayerWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final videoUrl = props['videoUrl'] as String?;
    final posterUrl = props['posterUrl'] as String?;
    final autoplay = props['autoplay'] ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 220,
        width: double.infinity,
        color: Colors.black87,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (videoUrl != null && videoUrl.isNotEmpty)
              const Center(child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70))
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_library, size: 40, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text('No video configured', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
