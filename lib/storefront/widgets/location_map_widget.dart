import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class LocationMapWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const LocationMapWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? 'Find Us';
    final zoom = props['zoom'] ?? 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.location_on, size: 48, color: Theme.of(context).colorScheme.primary),
                ),
                Positioned(
                  bottom: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Text('Zoom: $zoom', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
