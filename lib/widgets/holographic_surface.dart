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
    // EXPERIENCE PASS §2 — the light-mode gate. Light mode is not an inverted
    // dark card: the iridescence and the specular band are damped so the accent
    // reads as a restrained sheen on premium paper rather than a full-strength
    // holographic wash. Dark mode — the primary target — stays at 1.0.
    final tintGate = isDark ? 1.0 : 0.55;

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
              // EXPERIENCE PASS §2. The base is a three-facet vertical gradient
              // agreeing with the app's single top-left light source. Dark mode
              // (the primary target) gets a genuinely deeper fall-away — the
              // bottom facet now drops 22% toward black so the surface reads
              // as a slab with thickness, not a flat fill. Light mode is NOT an
              // inverted dark card: it keeps a lit top facet and a soft but
              // visible base-facet shade, because on near-white material depth
              // comes from the shadow side, not from darkening everything.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color.lerp(widget.base, Colors.white,
                            isDark ? 0.08 : 0.14)!,
                        widget.base,
                        Color.lerp(widget.base, Colors.black,
                            isDark ? 0.22 : 0.06)!,
                      ],
                      stops: const <double>[0.0, 0.52, 1.0],
                    ),
                  ),
                ),
              ),

              // ── LAYER 1b: the ceiling light (FIXED — never animates) ─────
              // A radial catch-light anchored at the top-left corner. This is
              // the room's light hitting the material's edge — it stays put; only
              // the specular band (layer 3) follows the finger. In dark mode it
              // gives the rim area something to read against; in light mode it
              // keeps the top edge from reading washed-out.
              if (intensity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.72, -0.85),
                          radius: 1.15,
                          colors: <Color>[
                            Colors.white.withValues(
                                alpha: (isDark ? 0.10 : 0.35) * intensity),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.0, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── LAYER 1c: the figure plate (dark only, FIXED) ────────────
              // EXPERIENCE PASS §2: contrast behind the balance figure. A soft
              // vignette that darkens the plate where the principal figure
              // sits, so the light material never competes with the number. In
              // light mode the figure already reads on near-white; a dark
              // vignette there would read as a stain, so it is omitted.
              if (isDark && intensity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.0, 0.35),
                          radius: 0.95,
                          colors: <Color>[
                            Colors.black.withValues(alpha: 0.14 * intensity),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.0, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── LAYER 2: the iridescence (FIXED — never animates) ──────────
              // EXPERIENCE PASS §2: an anisotropic brush in the accent's hue
              // family — the material's own colour shift. Two refinements:
              // (a) the white mid-band that made the surface read muddy is
              //     gone; the shift now stays inside ONE hue family, which is
              //     what makes it read as iridescence rather than as noise;
              // (b) light mode damps it to 55% — on near-white material a
              //     full-strength accent wash reads as a sticker, and the
              //     spec's light-mode brief is 'restrained accent treatment'.
              if (intensity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            widget.tint.withValues(
                                alpha: 0.00 * intensity * tintGate),
                            widget.tint.withValues(
                                alpha: 0.09 * intensity * tintGate),
                            widget.tint.withValues(
                                alpha: 0.04 * intensity * tintGate),
                            widget.tint.withValues(
                                alpha: 0.13 * intensity * tintGate),
                            widget.tint.withValues(
                                alpha: 0.02 * intensity * tintGate),
                          ],
                          stops: const <double>[0.0, 0.26, 0.50, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── LAYER 3: the specular band (THE ONLY MOVING PART) ──────────
              // EXPERIENCE PASS §2: the band is narrower (0.34→0.66) so it
              // reads as a single bar of light sweeping the material rather
              // than as a broad brightening, and its peak respects the light-
              // mode gate. Still drawn before the content so it can never wash
              // out text, and still the ONLY moving part.
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
                              alpha: widget.sheenPeak * intensity * tintGate,
                            ),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const <double>[0.34, 0.50, 0.66],
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
              // ── LAYER 4: rim + thickness ──────────────────────────────────
              // EXPERIENCE PASS §2. The rim is the card's edge separation and it
              // is now mode-aware:
              //   DARK  — a slightly stronger 1.0px lit top/left edge (the light
              //           catching the rim of a dark object) against a deeper
              //           base facet, so the silhouette survives even on
              //           near-black screens.
              //   LIGHT — a crisp 1.0px neutral stroke all round. The old
              //           white-on-white rim is why the light card melted into
              //           the page: a white rim highlight is invisible on a
              //           near-white card. Definition now comes from the
              //           stroke; the white highlight survives as a thin inner
              //           catch-light inset on the top edge only.
              // No borderRadius here: BoxDecoration forbids a radius with a
              // non-uniform-color Border. The outer ClipRRect already clips
              // these hairlines to the rounded corners.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? const Color(0x33FFFFFF)
                              : const Color(0x14000000),
                          width: 1.0,
                        ),
                        left: BorderSide(
                          color: isDark
                              ? const Color(0x2EFFFFFF)
                              : const Color(0x10000000),
                          width: 1.0,
                        ),
                        bottom: BorderSide(
                          color: isDark
                              ? const Color(0x0AFFFFFF)
                              : const Color(0x16000000),
                          width: 1.0,
                        ),
                        right: BorderSide(
                          color: isDark
                              ? const Color(0x0AFFFFFF)
                              : const Color(0x12000000),
                          width: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The inset hairline along the bottom edge that makes the surface
              // read as THICK rather than as a flat fill. In dark mode it is
              // joined by a top inner catch-light — the last sliver of the
              // ceiling light — which is what keeps the dark card's top edge
              // reading as material rather than as a cut-out.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    color: isDark
                        ? const Color(0x24000000)
                        : const Color(0x0D000000),
                  ),
                ),
              ),
              if (isDark)
                Positioned(
                  left: 1,
                  right: 1,
                  top: 1,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.10),
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

        // EXPERIENCE PASS §2 — light mode needs the card to survive against a
        // near-white page. The standard level-3 recipe is kept, and light mode
        // gains one tight contact shadow directly under the card — the shadow a
        // real object resting on paper casts — which is what stops the hero
        // from reading as "blank white boxes floating on white". Dark mode
        // already separates by luminance and keeps the unmodified recipe.
        final shadows = <BoxShadow>[
          if (widget.enableShadow) ...AzElevation.level3(isDark, color: widget.shadowColor),
          if (widget.enableShadow && !isDark)
            BoxShadow(
              color: (widget.shadowColor ?? const Color(0xFF000000))
                  .withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
        ];

        return Container(
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: shadows.isEmpty ? null : shadows,
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
