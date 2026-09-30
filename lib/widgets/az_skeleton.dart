import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Universal skeleton loading widget for Azaman.
/// Use this for EVERY primary list screen on first load.
/// Never use CircularProgressIndicator for full-screen loading.
class AzSkeleton extends ConsumerWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AzSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final base = colors.softSurface;
    final highlight = colors.isDark ? colors.card : colors.background;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton for a typical chat/transaction list item
class AzSkeletonListItem extends StatelessWidget {
  final bool hasAvatar;
  final bool hasSubtitle;

  const AzSkeletonListItem({
    super.key,
    this.hasAvatar = true,
    this.hasSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (hasAvatar) ...[
            const AzSkeleton(width: 48, height: 48, borderRadius: 24),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AzSkeleton(width: MediaQuery.of(context).size.width * 0.4, height: 14),
                if (hasSubtitle) ...[
                  const SizedBox(height: 6),
                  AzSkeleton(width: MediaQuery.of(context).size.width * 0.6, height: 12),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AzSkeleton(width: 40, height: 12),
              SizedBox(height: 6),
              AzSkeleton(width: 20, height: 12, borderRadius: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// A full skeleton list page — drop this in as the loading state
class AzSkeletonList extends StatelessWidget {
  final int itemCount;

  const AzSkeletonList({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (_, i) => const AzSkeletonListItem(),

    );
  }
}

/// Skeleton for a marketplace grid tile
class AzSkeletonGridTile extends StatelessWidget {
  const AzSkeletonGridTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AzSkeleton(height: 120, borderRadius: 12),
        SizedBox(height: 8),
        AzSkeleton(height: 14),
        SizedBox(height: 4),
        AzSkeleton(width: 60, height: 12),
      ],
    );
  }
}
