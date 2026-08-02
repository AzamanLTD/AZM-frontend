// =============================================================================
// Storefront Skeleton Loader
//
// Phase 9: Shimmer-based skeleton shown while the storefront SDUI payload loads.
// Mimics the layout of a real storefront (hero header, info bar, product grid,
// reviews) to reduce perceived load time.
// =============================================================================

import 'package:flutter/material.dart';
import '../../widgets/premium_shimmer.dart';

class StorefrontSkeleton extends StatelessWidget {
  const StorefrontSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E2329) : const Color(0xFFF0F0F0);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero header placeholder
            PremiumShimmerBox(
              width: double.infinity,
              height: 180,
              radius: 16,
              baseColor: baseColor,
            ),
            const SizedBox(height: 16),

            // Business name + rating row
            Row(
              children: [
                PremiumShimmerBox(width: 200, height: 24, radius: 8, baseColor: baseColor),
                const Spacer(),
                PremiumShimmerBox(width: 60, height: 20, radius: 8, baseColor: baseColor),
              ],
            ),
            const SizedBox(height: 12),

            // Quick info bar
            PremiumShimmerBox(width: double.infinity, height: 48, radius: 12, baseColor: baseColor),
            const SizedBox(height: 16),

            // Product grid (2x2)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: 4,
              itemBuilder: (_, __) => PremiumShimmerBox(
                width: double.infinity,
                height: 160,
                radius: 12,
                baseColor: baseColor,
              ),
            ),
            const SizedBox(height: 16),

            // Reviews carousel placeholder
            PremiumShimmerBox(width: double.infinity, height: 100, radius: 12, baseColor: baseColor),
          ],
        ),
      ),
    );
  }
}
