// =============================================================================
// PROMOTED AD BADGE  (Master Sprint, 2026-05-27)
//
// "BOOSTED" pill rendered on top of vendor ad cards that won the AZM
// auction. Slim, gold-gradient pill with a flame icon — mirrors the
// "AI" badge already used on VendorAdCard.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PromotedAdBadge extends StatelessWidget {
  final int? rank;
  const PromotedAdBadge({super.key, this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB800), Color(0xFFFF6A00)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB800).withOpacity(0.45),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            rank != null ? 'BOOSTED #$rank' : 'BOOSTED',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 2200.ms,
          color: Colors.white.withOpacity(0.40),
        );
  }
}
