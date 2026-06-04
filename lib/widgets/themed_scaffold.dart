// =============================================================================
// THEMED SCAFFOLD  (Master Sprint v2, 2026-05-27)
//
// Replaces bare `Scaffold(backgroundColor: colors.background)` with a
// theme-driven gradient backdrop so every theme actually transforms the
// app's *feel*, not just hex codes. Each theme paints:
//
//   • A deep radial halo from the top-left (the theme's `glow` color
//     bleeds out softly), giving depth.
//   • A second radial from the bottom-right with the accentSecondary,
//     creating a subtle two-tone wash.
//   • A vignette over the base background so foreground content reads
//     against a calm centre.
//
// Light themes get a brighter wash (lower opacity halos + a soft
// off-white centre) so text remains contrasted. Dark themes get richer
// halos. The whole stack is one single CustomPaint so it adds essentially
// zero cost vs. a flat color.
//
// Usage:
//   ThemedScaffold(
//     appBar: ...,
//     body: ...,
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';

class ThemedScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;
  final Color? overrideBackground;

  const ThemedScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
    this.overrideBackground,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      drawer: drawer,
      endDrawer: endDrawer,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Container(
        decoration: BoxDecoration(
          color: overrideBackground ?? colors.background,
          gradient: _buildThemeGradient(colors),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: glow halo from top-left
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.95),
                    radius: 1.4,
                    colors: [
                      colors.glow.withOpacity(colors.isDark ? 0.18 : 0.10),
                      colors.glow.withOpacity(colors.isDark ? 0.06 : 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
            ),
            // Layer 2: secondary halo from bottom-right
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.95, 1.0),
                    radius: 1.2,
                    colors: [
                      colors.accentSecondary.withOpacity(colors.isDark ? 0.10 : 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            // Layer 3 (light themes only): center wash so text reads cleanly
            if (!colors.isDark)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.4,
                      colors: [
                        colors.surface.withOpacity(0.95),
                        colors.surface.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            // Content
            if (body != null) body!,
          ],
        ),
      ),
    );
  }

  /// Subtle base gradient orthogonal to the halos so even with the radial
  /// layers off-axis you still get directional depth.
  Gradient _buildThemeGradient(AzamanColors colors) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colors.background,
        Color.alphaBlend(
          colors.accent.withOpacity(colors.isDark ? 0.04 : 0.025),
          colors.background,
        ),
      ],
    );
  }
}
