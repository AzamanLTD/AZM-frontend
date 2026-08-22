// =============================================================================
// AZAMAN — Pull-to-Refresh wrapper
//
// Wraps AzLogoRefreshIndicator and enforces scroll physics that work with
// the bounce-reveal effect. Uses ClampingScrollPhysics so the content
// doesn't bounce on its own — instead, AzLogoRefreshIndicator translates
// the entire wrapped content down via Transform.translate when the
// user overscrolls, which pushes the whole page (headers, stories,
// lists) down to reveal the indicator at the TOP of the screen.
//
// Screens that want BouncingScrollPhysics (like the home screen) can
// still set it explicitly on their scroll view — the AzLogoRefreshIndicator
// handles both BouncingScrollPhysics (via ScrollUpdateNotification with
// negative pixels) and ClampingScrollPhysics (via OverscrollNotification).
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
        behavior: const _ClampScrollBehavior(),
        child: child,
      ),
    );
  }
}

/// Uses ClampingScrollPhysics + AlwaysScrollableScrollPhysics so the
/// AzLogoRefreshIndicator can translate the entire wrapped content via
/// OverscrollNotification. This ensures the whole page (not just the
/// list) gets pushed down to reveal the indicator at the top.
class _ClampScrollBehavior extends ScrollBehavior {
  const _ClampScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
