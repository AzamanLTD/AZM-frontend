// =============================================================================
// AZAMAN — Pull-to-Refresh wrapper
//
// Wraps AzLogoRefreshIndicator and enforces ClampingScrollPhysics so the
// content doesn't bounce on its own. Instead, AzLogoRefreshIndicator uses
// a Column with an animated-height indicator row at the top. When the
// user overscrolls at the top of the scroll view, the indicator row
// grows (real layout space), pushing the content down — no transform,
// no z-index conflicts. The indicator is naturally above the content.
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

/// ClampingScrollPhysics + AlwaysScrollableScrollPhysics so overscroll at
/// the top generates OverscrollNotification (which the indicator uses to
/// grow its height). No bounce — the indicator provides the visual
/// feedback instead.
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
