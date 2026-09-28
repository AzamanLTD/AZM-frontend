// lib/widgets/premium_glass_container.dart
// =============================================================================
// PREMIUM GLASS CONTAINER — Reusable glassmorphic surface
//
// Wraps content in a BackdropFilter blur + tinted overlay + optional
// gradient sheen + rounded border. The key visual difference from a
// plain Container with color: light bends through it.
//
// ── v2 (directional light) ───────────────────────────────────────────────────
// v1 drew a uniform 0.5px white border and one centred shadow, which reads as
// "a rectangle with a blur" rather than as a pane of glass. v2 adds the four
// things real glass needs:
//
//   1. SPECULAR  — a soft highlight from the top-left corner inward. This is
//                  what the eye reads as light bending through the surface.
//   2. RIM       — top/left edge lighter than bottom/right, because the app
//                  has one implied light source (top-left).
//   3. THICKNESS — a 1px inset hairline along the bottom edge, so the pane
//                  reads as a physical slab rather than a flat fill.
//   4. DEPTH     — two shadows: a tight dark contact shadow (close) plus a
//                  wide faint ambient shadow (raised). One shadow = a sticker.
//
// All four are controlled by `directionalLight` / `specular`, both defaulting
// to true. If a specific surface regresses, pass `directionalLight: false` at
// that one call site rather than reverting the widget.
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

import 'package:azaman/theme/az_elevation.dart';

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

  // ── v2 additions (all optional — v1 call sites are unaffected) ──────────

  /// Draw the top-left specular streak + directional rim + bottom inner shade.
  /// Default true. Set false to reproduce the exact v1 appearance on a surface
  /// that regresses.
  final bool directionalLight;

  /// Draw only the specular streak. Ignored when [directionalLight] is false.
  final bool specular;

  /// Peak alpha of the specular streak at the top-left corner. Default 0.14.
  /// Keep <= 0.20 — beyond that the streak reads as a rendering artefact.
  final double sheenOpacity;

  /// How far down the surface the specular streak reaches, as a fraction of
  /// the widget height (0.0–1.0). Default 0.55.
  final double sheenExtent;

  /// Multiplier applied to both shadow alphas. Use < 1 to settle a surface
  /// into its surroundings, > 1 to lift it. Default 1.0.
  final double shadowStrength;

  /// Override the shadow colour. Defaults to black.
  final Color? shadowColor;

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
    this.directionalLight = true,
    this.specular = true,
    this.sheenOpacity = 0.14,
    this.sheenExtent = 0.55,
    this.shadowStrength = 1.0,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = tintColor ?? (isDark ? Colors.white : Colors.black);

    final radius = BorderRadius.circular(borderRadius);

    // Rim: one implied light source at the top-left. When `directionalLight`
    // is off we fall back to v1's uniform hairline so existing surfaces that
    // relied on it keep their exact appearance.
    // Rim: one implied light source at the top-left. A `Border` can only carry
    // a *uniform* colour when the decoration has a non-zero borderRadius, so
    // the directional rim is painted as a gradient stroke (see the rim layer in
    // the Stack) and `rim` stays null. The v1 uniform hairline is preserved
    // exactly for callers that relied on it.
    final Border? rim = border ??
        (directionalLight
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.12),
                width: 0.5,
              ));

    final shadows = enableShadow
        ? (directionalLight
            ? AzElevation.level2(isDark, color: shadowColor).map((s) {
                // Rebuild each shadow with the strength multiplier applied so a
                // caller can settle or lift a single surface.
                if (shadowStrength == 1.0) return s;
                return BoxShadow(
                  // Clamp so the documented shadowStrength > 1 lift affordance
                  // can never produce an invalid colour alpha.
                  color: s.color.withValues(
                    alpha:
                        (s.color.a * shadowStrength).clamp(0.0, 1.0).toDouble(),
                  ),
                  blurRadius: s.blurRadius,
                  spreadRadius: s.spreadRadius,
                  offset: s.offset,
                );
              }).toList(growable: false)
            : <BoxShadow>[
                BoxShadow(
                  color: (shadowColor ?? Colors.black)
                      .withValues(alpha: (isDark ? 0.3 : 0.08) * shadowStrength),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ])
        : null;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              // 1. Specular streak — drawn FIRST so the translucent tint and
              //    the content sit on top of it. A highlight painted over text
              //    would wash the text out.
              if (directionalLight && specular)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment(0.35, sheenExtent * 2 - 1),
                          colors: <Color>[
                            Colors.white.withValues(alpha: sheenOpacity),
                            Colors.white.withValues(alpha: sheenOpacity * 0.25),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.0, 0.35, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. Tinted glass body + directional rim.
              Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: opacity),
                  borderRadius: radius,
                  border: rim,
                  gradient: gradient,
                ),
                child: child,
              ),

              // 2b. Directional rim. A gradient stroke reads as a single lit
              //     edge (bright top-left falling to a shaded bottom-right),
              //     which a per-side `Border` cannot express on a rounded box.
              if (rim == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (Rect rect) => const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Colors.white, Colors.white],
                      ).createShader(rect),
                      child: _GradientRim(
                        radius: radius,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ),

              // 3. Thickness — a 1px inset hairline along the bottom edge.
              //    Clipped by the parent ClipRRect so it follows the radius.
              if (directionalLight)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: AzElevation.innerBottomShade(isDark),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a rounded outline painted with a top-left highlight to bottom-right
/// shade gradient. A per-side [Border] cannot express this on a rounded box
/// (its side colours must be uniform), so the stroke is painted as a
/// gradient-filled rounded rectangle masked to its own outline.
class _GradientRim extends StatelessWidget {
  const _GradientRim({required this.radius, required this.isDark});

  final BorderRadius radius;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: 0.75),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AzElevation.rimHighlight(isDark),
              AzElevation.rimHighlight(isDark),
              AzElevation.rimShade(isDark),
              AzElevation.rimShade(isDark),
            ],
            stops: const <double>[0.0, 0.35, 0.7, 1.0],
          ),
        ),
      ),
    );
  }
}
