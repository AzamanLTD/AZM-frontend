import 'package:flutter/material.dart';

class FallbackWidget extends StatelessWidget {
  final String widgetType;

  const FallbackWidget({super.key, required this.widgetType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension, size: 32, color: Theme.of(context).colorScheme.error.withOpacity(0.4)),
          const SizedBox(height: 8),
          Text('Unknown widget: $widgetType', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error.withOpacity(0.6))),
        ],
      ),
    );
  }
}
