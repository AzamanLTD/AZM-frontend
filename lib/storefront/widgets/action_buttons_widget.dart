import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class ActionButtonsWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ActionButtonsWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final showOrder = props['showOrder'] ?? true;
    final showBook = props['showBook'] ?? false;
    final showFollow = props['showFollow'] ?? true;
    final showShare = props['showShare'] ?? true;

    final buttons = <Widget>[];
    if (showOrder) buttons.add(ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.shopping_bag, size: 18), label: const Text('Order Now')));
    if (showBook) buttons.add(ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.calendar_today, size: 18), label: const Text('Book')));
    if (showFollow) buttons.add(OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add, size: 18), label: const Text('Follow')));
    if (showShare) buttons.add(OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.share, size: 18), label: const Text('Share')));

    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: buttons);
  }
}
