// =============================================================================
// AZAMAN — Custom Pull-to-Refresh Indicator
//
// Now uses the AzLogoRefreshIndicator — a mini version of the logo with a
// tracing line animation instead of the default Material circular spinner.
// Respects reduced-motion (falls back to standard RefreshIndicator).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/az_logo_refresh_indicator.dart';

class AzPullToRefresh extends ConsumerWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  const AzPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Respect reduced-motion: fall back to standard Material indicator
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
