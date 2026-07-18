import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class PromoBannerWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const PromoBannerWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? '';
    final subtitle = props['subtitle'] as String? ?? '';
    final ctaText = props['ctaText'] as String? ?? 'Shop Now';
    final backgroundColor = props['backgroundColor'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: backgroundColor != null
              ? [_parseColor(backgroundColor), _parseColor(backgroundColor).withOpacity(0.8)]
              : [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty) Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Theme.of(context).colorScheme.primary, elevation: 0),
            child: Text(ctaText),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    try { return Color(int.parse(h, radix: 16)); } catch (_) { return const Color(0xFF6C4FD1); }
  }
}
