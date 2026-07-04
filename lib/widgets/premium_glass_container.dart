// lib/widgets/premium_glass_container.dart
// =============================================================================
// PREMIUM GLASS CONTAINER — Reusable glassmorphic surface
//
// Wraps content in a BackdropFilter blur + tinted overlay + optional
// gradient sheen + rounded border. The key visual difference from a
// plain Container with color: light bends through it.
//
// Usage:
//   PremiumGlassContainer(
//     blur: 20,
//     opacity: 0.08,
//     child: ...
//   )
// =============================================================================
import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumGlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;           // sigma for BackdropFilter (default 20)
  final double opacity;        // overlay tint opacity (default 0.08)
  final Color? tintColor;      // override tint color (defaults to white)
  final double borderRadius;   // default 20
  final Border? border;        // optional custom border
  final Gradient? gradient;    // optional sheen gradient on top
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final bool enableShadow;     // default true

  const PremiumGlassContainer({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.08,
    this.tintColor,
    this.borderRadius = 20,
    this.border,
    this.gradient,
    this.padding,
    this.margin,
    this.enableShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = tintColor ?? (isDark ? Colors.white : Colors.black);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: enableShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint.withOpacity(opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ??
                  Border.all(
                    color: (isDark ? Colors.white : Colors.black)
                        .withOpacity(0.06),
                    width: 0.5,
                  ),
              gradient: gradient,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
