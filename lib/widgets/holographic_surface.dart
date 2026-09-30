// lib/widgets/holographic_surface.dart
// =============================================================================
// HOLOGRAPHIC SURFACE — the hero substrate
//
// A surface that reads as a physical, iridescent material catching a light.
// It is the substrate for the ONE most important object on a screen: the balance
// card, a membership tier, a boarding pass, a "PAID" seal.
//
// ── THE PHYSICS (why it reads as real) ───────────────────────────────────────
// Two layers, and only one of them moves:
//
//   1. THE MATERIAL — an anisotropic gradient in the accent's hue family. This
//      is the surface's own iridescence. It is FIXED: real anodised/holographic
//      material does not change colour when you look at it from a different
//      angle, only the light on it does.
//
//   2. THE LIGHT — a soft specular band whose position follows the user's
//      pointer, and which springs back to rest when the finger lifts. This is
//      the ONLY moving part.
//
// Keeping the material still and moving only the light is what separates this
// from "an animated gradient". An animated gradient reads as decoration; a
// moving highlight on a fixed material reads as a real object.
//
// ── WHY NOT TILT (sensors_plus) ──────────────────────────────────────────────
// Deliberate decision: no sensor dependency. It would add a package, require
// permissions on some platforms, be untestable in CI, and drain battery for an
// effect the user only sees while the card is under their finger anyway.
// Pointer-driven light delivers the same feeling with zero dependencies.
//
// ── GESTURE SAFETY ───────────────────────────────────────────────────────────
// This widget uses `Listener`, NOT `GestureDetector`. `Listener` observes
// pointers WITHOUT entering the gesture arena, so it cannot steal a drag from a
// parent scroll view. A card inside a horizontal deck can therefore be scrolled
// AND catch light at the same time.
//
// ── REDUCED MOTION ───────────────────────────────────────────────────────────
// When the OS requests reduced motion the surface becomes fully static — no
// pointer tracking, no settle. The material's gradient and the rim light remain,
// so the object is still dimensional; it simply does not react.
//
// ── USAGE ────────────────────────────────────────────────────────────────────
//   HolographicSurface(
//     base: colors.card,
//     tint: colors.accent,
//     borderRadius: AzRadius.xl,
//     padding: const EdgeInsets.all(AzSpace.xl),
//     child: ...,
//   )
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';

class HolographicSurface extends StatefulWidget {
  const HolographicSurface({
    super.key,
    required this.child,
    required this.base,
    required this.tint,
    this.borderRadius = 20,
    this.padding,
    this.margin,
    this.interactive = true,
    this.intensity = 1.0,
    this.sheenPeak = 0.18,
    this.enableShadow = true,
    this.shadowColor,
  });

  final Widget child;

  /// The deep base colour of the material — the card's own background.
  final Color base;

  /// The accent hue that drives the iridescence and the sheen. Usually
  /// `colors.accent`, but a premium tier might pass `colors.accentSecondary`.
  final Color tint;

  final double borderRadius;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  /// Whether the specular band follows the pointer. Set false for a static
  /// decorative surface.
  final bool interactive;

  /// Scales the whole holographic effect. 1.0 is the designed default; use
  /// 0.6–0.8 for a secondary surface so it does not compete with the hero.
  final double intensity;

  /// Peak alpha of the specular band. Keep ≤ 0.22 — beyond that the band reads
  /// as a rendering artefact rather than as light.
  final double sheenPeak;

  final bool enableShadow;
  final Color? shadowColor;

  @override
  State<HolographicSurface> createState() => _HolographicSurfaceState();
}

class _HolographicSurfaceState extends State<HolographicSurface>
    with SingleTickerProviderStateMixin {
  /// Normalised sheen offset, −0.45 … +0.45 in each axis. 0,0 is centred/rest.
  double _dx = 0.0;
  double _dy = 0.0;

  /// The offset the settle animation starts from.
  double _restFromDx = 0.0;
  double _restFromDy = 0.0;

  late final AnimationController _rest;

  @override
  void initState() {
    super.initState();
    _rest = AnimationController(
      vsync: this,
      duration: MotionTokens.emphasized,
    )
      ..addListener(() {
        // _sheenOffset reads the controller's current progress; rebuild each
        // frame so the return-to-rest is actually visible after pointer-up.
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _dx = 0.0;
            _dy = 0.0;
            _restFromDx = 0.0;
            _restFromDy = 0.0;
          });
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AzMotion.of(context).travel) {
      _rest.stop();
      _dx = _dy = _restFromDx = _restFromDy = 0;
    }
  }

  @override
  void dispose() {
    _rest.dispose();
    super.dispose();
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (!widget.interactive) return;
    if (size.width <= 0 || size.height <= 0) return;

    // Stop any in-flight settle so the finger always wins.
    _rest.stop();

    final nx = (event.localPosition.dx / size.width).clamp(0.0, 1.0);
    final ny = (event.localPosition.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _dx = (nx - 0.5) * 0.9;
      _dy = (ny - 0.5) * 0.9;
    });
  }

  void _onPointerEnd() {
    if (!widget.interactive) return;
    if (_dx == 0.0 && _dy == 0.0) return;
    _restFromDx = _dx;
    _restFromDy = _dy;
    _rest.forward(from: 0.0);
  }

  /// The current sheen offset, with the settle applied if one is running.
  ///
  /// `kHouseSpring` overshoots by ~22%, so the sheen passes *through* centre and
  /// settles back — which is exactly how a light source behaves when the thing
  /// casting it comes to rest.
  (double, double) _sheenOffset() {
    if (!_rest.isAnimating) return (_dx, _dy);
    final t = _rest.value;
    final eased = kHouseSpring.transform(t);
    return (
      _restFromDx * (1.0 - eased),
      _restFromDy * (1.0 - eased),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = !AzMotion.of(context).travel;
    final radius = BorderRadius.circular(widget.borderRadius);
    final intensity = widget.intensity.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final (offsetDx, offsetDy) = _sheenOffset();
        final dx = AzMotion.scale(context, offsetDx);
        final dy = AzMotion.scale(context, offsetDy);

        final surface = ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              // ── LAYER 1: the material ──────────────────────────────────────
              // A vertical base gradient so the top edge is lit and the bottom
              // falls away, agreeing with the app's single top-left light source.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color.lerp(widget.base, Colors.white, isDark ? 0.06 : 0.10)!,
                        widget.base,
                        Color.lerp(widget.base, Colors.black, isDark ? 0.10 : 0.03)!,
                      ],
                      stops: const <double>[0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // ── LAYER 2: the iridescence (FIXED — never animates) ──────────
              // An anisotropic gradient in the accent's hue family. This is the
              // material's own colour shift and it must not move: if it did, the
              // surface would read as a cheap animated gradient.
              if (intensity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            widget.tint.withValues(alpha: 0.00 * intensity),
                            widget.tint.withValues(alpha: 0.10 * intensity),
                            Colors.white.withValues(alpha: 0.05 * intensity),
                            widget.tint.withValues(alpha: 0.14 * intensity),
                            widget.tint.withValues(alpha: 0.02 * intensity),
                          ],
                          stops: const <double>[0.0, 0.28, 0.50, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── LAYER 3: the specular band (THE ONLY MOVING PART) ──────────
              // Drawn before the content so it can never wash out text.
              if (intensity > 0 && widget.sheenPeak > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(
                              alpha: widget.sheenPeak * intensity,
                            ),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.30, 0.50, 0.70],
                          transform: _SheenTransform(dx, dy),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── LAYER 4: rim + thickness ──────────────────────────────────
              // Directional rim: top/left catches the light, bottom/right falls
              // away. Plus a 1px inset hairline along the bottom so the surface
              // reads as THICK rather than as a flat fill.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    // No borderRadius here: BoxDecoration forbids a radius with
                    // a non-uniform-color Border, and this rim is deliberately
                    // two-tone (top/left lit, bottom/right shaded). The outer
                    // ClipRRect already clips these hairlines to the rounded
                    // corners, so the painted result is identical.
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: AzElevation.rimHighlight(isDark),
                          width: 0.75,
                        ),
                        left: BorderSide(
                          color: AzElevation.rimHighlight(isDark),
                          width: 0.75,
                        ),
                        bottom: BorderSide(
                          color: AzElevation.rimShade(isDark),
                          width: 0.75,
                        ),
                        right: BorderSide(
                          color: AzElevation.rimShade(isDark),
                          width: 0.75,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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

              // ── LAYER 5: content ──────────────────────────────────────────
              if (widget.padding != null)
                Padding(padding: widget.padding!, child: widget.child)
              else
                widget.child,
            ],
          ),
        );

        // The Listener wraps the surface so it can observe pointer movement
        // without competing for the gesture. `translucent` lets the event
        // continue to the parent scroll view.
        final interactiveSurface = widget.interactive && !reduceMotion
            ? Listener(
                behavior: HitTestBehavior.translucent,
                onPointerMove: (e) => _onPointerMove(e, size),
                onPointerUp: (_) => _onPointerEnd(),
                onPointerCancel: (_) => _onPointerEnd(),
                child: surface,
              )
            : surface;

        return Container(
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: widget.enableShadow
                ? AzElevation.level3(isDark, color: widget.shadowColor)
                : null,
          ),
          child: interactiveSurface,
        );
      },
    );
  }
}

/// Translates the gradient's coordinate space by (dx, dy) of the surface's size.
///
/// This is the mechanism that moves the specular band WITHOUT touching layout —
/// the band is painted at a different place, but the widget tree is unchanged.
class _SheenTransform extends GradientTransform {
  const _SheenTransform(this.dx, this.dy);

  final double dx;
  final double dy;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * dx,
      bounds.height * dy,
      0.0,
    );
  }
}
