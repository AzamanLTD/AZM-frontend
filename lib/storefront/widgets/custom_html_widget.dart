import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class CustomHtmlWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const CustomHtmlWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final html = props['html'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: html.isEmpty
          ? Text('Custom HTML content will appear here', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)))
          : Text(html, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
    );
  }
}
