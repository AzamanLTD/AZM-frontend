// =============================================================================
// RATING STARS — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Reusable 0–5 star rating display. Filled stars use colors.warning, empty
// stars use colors.divider, and a half-step renders a half star. Optionally
// appends the numeric rating after the stars.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/providers/theme_provider.dart';

class RatingStars extends ConsumerWidget {
  final double rating; // 0–5
  final double size;
  final bool showNumber;

  const RatingStars({
    super.key,
    required this.rating,
    this.size = 16,
    this.showNumber = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final clamped = rating.clamp(0.0, 5.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 5; i++) _star(i, clamped, colors),
        if (showNumber) ...[
          SizedBox(width: size * 0.35),
          Text(
            clamped.toStringAsFixed(1),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: size * 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _star(int index, double value, AzamanColors colors) {
    final filledThreshold = index + 1;
    final halfThreshold = index + 0.5;

    IconData icon;
    Color color;
    if (value >= filledThreshold) {
      icon = Icons.star_outline;
      color = colors.warning;
    } else if (value >= halfThreshold) {
      icon = Icons.star_half;
      color = colors.warning;
    } else {
      icon = Icons.star_outline;
      color = colors.divider;
    }

    return Padding(
      padding: EdgeInsets.only(right: size * 0.06),
      child: Icon(icon, size: size, color: color),
    );
  }
}
