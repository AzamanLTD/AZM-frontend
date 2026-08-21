// =============================================================================
// AZAMAN — Pull-to-Refresh wrapper
//
// Wraps AzLogoRefreshIndicator and enforces BouncingScrollPhysics on all
// child scroll views via ScrollConfiguration. This ensures the bounce-
// reveal effect works on every screen — the content bounces down and the
// logo indicator is revealed behind it.
//
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
      child: ScrollConfiguration(
        behavior: const _BounceScrollBehavior(),
        child: child,
      ),
    );
  }
}

/// Forces BouncingScrollPhysics + AlwaysScrollableScrollPhysics on all
/// scrollables inside AzPullToRefresh, so the bounce-reveal effect works
/// universally regardless of platform defaults.
class _BounceScrollBehavior extends ScrollBehavior {
  const _BounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  // Preserve default copy behavior (text selection, etc.)
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No glow/overscroll indicator — our custom indicator handles it.
    return child;
  }
}
