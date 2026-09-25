// lib/widgets/skeleton_loader.dart
//
// Lightweight shimmer-style skeleton used across the app in place of
// boring CircularProgressIndicators. Respects the active AzamanColors
// palette so it tints correctly on every theme.
//
// Usage:
//   SkeletonBlock(height: 200, width: double.infinity)
//   SkeletonLine(width: 120)
//   SkeletonList(itemHeight: 80, count: 6)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class SkeletonBlock extends ConsumerStatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final EdgeInsets margin;

  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.margin = EdgeInsets.zero,
  });

  @override
  ConsumerState<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends ConsumerState<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        color: colors.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: [
                  colors.card,
                  colors.surface,
                  colors.divider.withValues(alpha: 0.35),
                  colors.surface,
                  colors.card,
                ],
                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                begin: Alignment(-1.0 + _ctrl.value * 2, 0),
                end: Alignment(1.0 + _ctrl.value * 2, 0),
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Container(color: colors.card),
          );
        },
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonLine({super.key, this.width = 80, this.height = 12});

  @override
  Widget build(BuildContext context) =>
      SkeletonBlock(width: width, height: height);
}

class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  final EdgeInsets padding;
  const SkeletonList({
    super.key,
    this.count = 6,
    this.itemHeight = 80,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => SkeletonBlock(
        height: itemHeight,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
