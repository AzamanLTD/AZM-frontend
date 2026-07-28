// =============================================================================
// THEMED APP BACKDROP  (Master Sprint v2, 2026-05-27)
//
// Wraps the entire MaterialApp router output. Paints the active theme's
// signature gradient halos behind every screen so theme switches genuinely
// transform the app's *feel* — not just hex codes on a flat background.
//
// Each theme contributes:
//   • A glow halo from the top-left
//   • A secondary accent halo from the bottom-right
//   • (Light themes) a soft surface wash so text remains contrasted
//
// Scaffolds in the app should use `backgroundColor: Colors.transparent`
// (or the convenience `ThemedScaffold` widget) so the backdrop shows
// through. Bare Scaffolds with their default opaque background still
// work — they just hide the backdrop.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';

class ThemedAppBackdrop extends ConsumerWidget {
  final Widget child;
  const ThemedAppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: only repaint when colors swap (theme switch), not on
    // unrelated provider notifies.
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.background,
            Color.alphaBlend(
              colors.accent.withValues(alpha: colors.isDark ? 0.06 : 0.030),
              colors.background,
            ),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Glow halo — top-left
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.85, -0.95),
                  radius: 1.4,
                  colors: [
                    colors.glow.withValues(alpha: colors.isDark ? 0.20 : 0.10),
                    colors.glow.withValues(alpha: colors.isDark ? 0.06 : 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          // Secondary accent halo — bottom-right
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.95, 1.0),
                  radius: 1.2,
                  colors: [
                    colors.accentSecondary.withValues(alpha: colors.isDark ? 0.12 : 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Subtle center wash on light themes so text reads cleanly
          if (!colors.isDark)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.4,
                    colors: [
                      colors.surface.withValues(alpha: 0.80),
                      colors.surface.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
