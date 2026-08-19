// =============================================================================
// AZAMAN — Custom Pull-to-Refresh Indicator
//
// Uses the AzLogoRefreshIndicator — a mini version of the logo with a
// tracing line animation instead of the default Material circular spinner.
// Accepts (and ignores) color/backgroundColor for drop-in compatibility
// with code that previously used RefreshIndicator. Respects reduced-motion.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/az_logo_refresh_indicator.dart';

class AzPullToRefresh extends ConsumerWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  /// Ignored — kept for drop-in compatibility with RefreshIndicator.
  final Color? color;
  /// Ignored — kept for drop-in compatibility with RefreshIndicator.
  final Color? backgroundColor;
  /// Ignored — kept for drop-in compatibility with RefreshIndicator.
  final double displacement;
  /// Ignored — kept for drop-in compatibility with RefreshIndicator.
  final double strokeWidth;

  const AzPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.displacement = 40,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        backgroundColor: colors.surface,
        color: colors.accent,
        displacement: 40,
        strokeWidth: 1,
        child: child,
      );
    }

    return AzLogoRefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}
