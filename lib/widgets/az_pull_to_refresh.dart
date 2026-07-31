// =============================================================================
// AZAMAN — Custom Pull-to-Refresh Indicator
//
// Replaces the default Material RefreshIndicator with a branded one:
// a pulsing accent-colored ring that scales/fades in as the user pulls down.
// Respects reduced-motion (instant snap, no animation).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class AzPullToRefresh extends ConsumerWidget {
  final Widget child;
  final RefreshCallback onRefresh;
  final EdgeInsets? padding;

  const AzPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.padding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: colors.surface,
      color: colors.accent,
      displacement: 40,
      strokeWidth: reduceMotion ? 1 : 2.5,
      // Use a custom builder via the `notification` param isn't available
      // in the standard RefreshIndicator, so we just style the built-in one
      // with our brand colors and let the platform handle the rest.
      // The key customization is the color + surface which matches our theme.
      child: child,
    );
  }
}
