// =============================================================================
// AZAMAN — Custom Pull-to-Refresh Indicator
//
// Branded wrapper around Material RefreshIndicator with AZAMAN theme colors.
// Respects reduced-motion (thinner stroke when animations are disabled).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

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

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: colors.surface,
      color: colors.accent,
      displacement: 40,
      strokeWidth: reduceMotion ? 1 : 2.5,
      child: child,
    );
  }
}
