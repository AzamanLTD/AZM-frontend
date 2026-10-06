// lib/widgets/holographic_surface.dart
// =============================================================================
// HOLOGRAPHIC SURFACE — the hero substrate
//
// A surface that reads as a physical, iridescent material catching a light.
// It is the substrate for the ONE most important object on a screen: the balance
// card, a membership tier, a boarding pass, a "PAID" seal.
//
// ── THE PHYSICS (why it reads as real) ───────────────────────────────────────
// The material is fixed; the touch response is opt-in per surface:
//
//   1. THE MATERIAL — an anisotropic gradient in the accent's hue family. This
//      is the surface's own iridescence. It is FIXED: real anodised/holographic
//      material does not change colour when you look at it from a different
//      angle, only the light on it does.
//
//   2. THE SPECULAR SHEEN — a soft band whose position follows the user's
//      pointer, and which springs back to rest when the finger lifts. The
//      default touch response (`showSheen: true`).
//
//   3. THE REACTIVE PARTICLE FIELD — an OPT-IN accent (`showReactiveParticles:
//      false` by default): a tiny, deterministic field of soft coloured points
//      that breathes while the card rests and DEFORMS around the finger when
//      it touches — nearest points lean away, the mid-band leans toward, and
//      everything settles through the same rest spring as the sheen. The
//      balance card adopts it as its sole touch response (`showSheen: false`).
//
// Keeping the material still and moving only opt-in responses is what separates
// this from "an animated gradient". An animated gradient reads as decoration;
// a moving highlight on a fixed material reads as a real object.
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
    this.showSheen = true,
    this.showReactiveParticles = false,
    this.particleColors,
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

  /// Whether the touch-driven specular band renders. The balance card turns
  /// this OFF and speaks through the reactive particle field instead — the
  /// two responses are never run simultaneously on the same surface.
  final bool showSheen;

  /// Opt-in reactive particle field (default false): a small deterministic
  /// set of soft coloured points behind the content that breathes at rest
  /// and deforms around the pointer. No other consumer is affected.
  final bool showReactiveParticles;

  /// The particle family. Defaults to a single hue derived from [tint]; the
  /// balance card passes the app's accent family. Keep to 2–3 restrained
  /// colours — this is an accent, never a rainbow.
  final List<Color>? particleColors;

  final bool enableShadow;
  final Color? shadowColor;

  @override
  State<HolographicSurface> createState() => _HolographicSurfaceState();
}

class _HolographicSurfaceState extends State<HolographicSurface>
    with TickerProviderStateMixin {
  /// Normalised sheen offset, −0.45 … +0.45 in each axis. 0,0 is centred/rest.
  double _dx = 0.0;
  double _dy = 0.0;

  /// The offset the settle animation starts from.
  double _restFromDx = 0.0;
  double _restFromDy = 0.0;

  late final AnimationController _rest;

  /// ONE shared ambient clock for every particle on this surface (~9s loop).
  /// Created only when the surface opted into the particle field so default
  /// consumers never pay for a second ticker. Stopped and zeroed under
  /// reduced motion (see didChangeDependencies).
  late final AnimationController? _ambient;

  @override
  void initState() {
    super.initState();
    if (widget.showReactiveParticles) {
      _ambient = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 9),
      )..repeat();
    } else {
      _ambient = null;
    }
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
    final travel = AzMotion.of(context).travel;
    if (!travel) {
      _rest.stop();
      _dx = _dy = _restFromDx = _restFromDy = 0;
      // Reduced motion is authoritative for the ambient field too: the
      // controller stops and the particles freeze at their resting phase.
      final ambient = _ambient;
      if (ambient != null && ambient.isAnimating) {
        ambient.stop();
        ambient.value = 0.0;
      }
    } else {
      final ambient = _ambient;
      if (ambient != null && !ambient.isAnimating && ambient.value == 0.0) {
        ambient.repeat();
      }
    }
  }

  @override
  void dispose() {
    _ambient?.dispose();
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

              // ── LAYER 1d: the reactive particle field (OPT-IN) ───────────
              // An Antigravity-inspired accent: a tiny deterministic field of
              // soft coloured points that breathes at rest and deforms around
              // the pointer — the balance card's sole touch response. It sits
              // behind the iridescence and far behind the content, is gated by
              // AzMotion (scaled dx/dy + a stopped ambient clock under reduced
              // motion), and is isolated in a RepaintBoundary so the ambient
              // repaint never invalidates the card content or the Home screen.
              if (intensity > 0 && widget.showReactiveParticles)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ReactiveParticlePainter(
                        phase: _ambient ?? const AlwaysStoppedAnimation(0.0),
                        dx: dx,
                        dy: dy,
                        colors: widget.particleColors ??
                            <Color>[widget.tint.withValues(alpha: 0.8)],
                        intensity: intensity,
                        isDark: isDark,
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

              // ── LAYER 3: the specular band (opt-in touch response) ─────────
              // EXPERIENCE PASS §2: the band is narrower (0.34→0.66) so it
              // reads as a single bar of light sweeping the material rather
              // than as a broad brightening, and its peak respects the light-
              // mode gate. Still drawn before the content so it can never wash
              // out text. The balance card disables it in favour of the
              // particle field — the two responses never run together.
              if (intensity > 0 && widget.showSheen && widget.sheenPeak > 0)
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

/// One particle of the reactive field — a FIXED row of the deterministic spec
/// table (see [ReactiveParticlePainter.particleSpecs]). `x`/`y` are normalised
/// 0–1 positions inside the surface; nothing is randomised per frame.
class ReactiveParticleSpec {
  const ReactiveParticleSpec(
    this.x,
    this.y,
    this.radius,
    this.phase,
    this.speed,
    this.colorIndex,
  );

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
  final int colorIndex;
}

/// The reactive particle field (Antigravity-inspired, Azaman-native).
///
/// A single painter, a single shared ambient clock, a bounded deterministic
/// particle count — no BackdropFilter, no blur filter, no physics engine, no
/// per-particle controllers. The radial gradients themselves supply the soft
/// edges, so each point reads as a tiny luminous glow rather than a solid dot.
///
/// The field DEFORMS around the pointer instead of following it (see
/// [particleLean]): particles nearest the finger are displaced aside as if the
/// material itself is pressed, the mid-band leans toward the touch, distant
/// points barely move — and everything settles through the surface's EXISTING
/// rest spring because the painter consumes the same scaled `_dx`/`_dy`.
class ReactiveParticlePainter extends CustomPainter {
  ReactiveParticlePainter({
    required this.phase,
    required this.dx,
    required this.dy,
    required this.colors,
    required this.intensity,
    required this.isDark,
  }) : super(repaint: phase);

  /// The surface's ONE shared ambient clock (≈9s loop). Reduced motion stops
  /// it and pins it at 0, freezing the field at its resting arrangement.
  final Animation<double> phase;

  /// The surface's normalised sheen offset (−0.45…+0.45 per axis), already
  /// settle-animated and already reduced-motion-scaled by the surface.
  final double dx;
  final double dy;

  /// The restrained particle family (2–3 colours from the app's accents).
  final List<Color> colors;

  final double intensity;
  final bool isDark;

  /// The fixed particle table — deterministic, bounded (18–28 points), tuned
  /// so the card feels naturally populated rather than patterned.
  static const List<ReactiveParticleSpec> particleSpecs = [
    ReactiveParticleSpec(0.08, 0.20, 1.6, 0.00, 0.82, 0),
    ReactiveParticleSpec(0.16, 0.62, 1.2, 0.14, 0.63, 1),
    ReactiveParticleSpec(0.22, 0.36, 1.9, 0.27, 0.71, 2),
    ReactiveParticleSpec(0.29, 0.79, 1.1, 0.38, 0.55, 0),
    ReactiveParticleSpec(0.34, 0.12, 1.4, 0.09, 0.88, 1),
    ReactiveParticleSpec(0.41, 0.48, 1.7, 0.52, 0.60, 2),
    ReactiveParticleSpec(0.47, 0.28, 1.3, 0.33, 0.74, 0),
    ReactiveParticleSpec(0.52, 0.66, 2.1, 0.61, 0.49, 1),
    ReactiveParticleSpec(0.58, 0.17, 1.0, 0.21, 0.91, 2),
    ReactiveParticleSpec(0.63, 0.42, 1.8, 0.44, 0.66, 0),
    ReactiveParticleSpec(0.69, 0.71, 1.2, 0.72, 0.58, 1),
    ReactiveParticleSpec(0.74, 0.23, 1.5, 0.06, 0.79, 2),
    ReactiveParticleSpec(0.79, 0.55, 1.3, 0.55, 0.68, 0),
    ReactiveParticleSpec(0.85, 0.33, 1.7, 0.29, 0.62, 1),
    ReactiveParticleSpec(0.90, 0.68, 1.1, 0.83, 0.53, 2),
    ReactiveParticleSpec(0.95, 0.15, 1.4, 0.18, 0.86, 0),
    ReactiveParticleSpec(0.11, 0.44, 1.0, 0.66, 0.57, 1),
    ReactiveParticleSpec(0.26, 0.20, 1.6, 0.47, 0.70, 2),
    ReactiveParticleSpec(0.37, 0.86, 1.3, 0.77, 0.51, 0),
    ReactiveParticleSpec(0.56, 0.84, 1.0, 0.12, 0.84, 1),
    ReactiveParticleSpec(0.72, 0.87, 1.5, 0.36, 0.64, 2),
    ReactiveParticleSpec(0.88, 0.47, 1.2, 0.58, 0.76, 0),
  ];

  /// The deterministic deformation of one particle around the pointer.
  ///
  /// `rest` is the particle's resting (ambient-drifted) centre, `pointer` the
  /// touch position in the same coordinate space, `interactionRadius` the
  /// reach of a touch. Nearest points lean AWAY from the finger (material
  /// pressed aside), the mid-band leans TOWARD it (attraction), and points
  /// beyond the radius do not move at all — a smooth signed blend so the
  /// field bends around the finger instead of uniformly following it.
  static Offset particleLean(
    Offset rest,
    Offset pointer,
    double interactionRadius,
  ) {
    final away = rest - pointer;
    final d = away.distance;
    if (d <= 0 || d >= interactionRadius || interactionRadius <= 0) {
      return rest;
    }
    final influence = 1.0 - d / interactionRadius;
    final eased = influence * influence;
    final dir = away / d;
    final awayAmt = ((influence - 0.62) / 0.38).clamp(0.0, 1.0);
    final towardAmt = ((0.62 - influence) / 0.62).clamp(0.0, 1.0) * 0.6;
    final signed = (awayAmt - towardAmt) * eased;
    return rest + dir * signed * interactionRadius * 0.22;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0 || colors.isEmpty || intensity <= 0) return;

    // Reconstruct the normalised pointer from the surface's existing offset:
    // the surface stores _dx = (nx − 0.5) × 0.9, so this is exact.
    final pointer = Offset(
      (0.5 + dx / 0.9) * w,
      (0.5 + dy / 0.9) * h,
    );
    final interactionRadius = math.max(60.0, math.min(w, h) * 0.5);

    // Interaction "heat" — how alive the touch is right now. dx/dy fold the
    // settle animation, so the halo blooms under the finger and fades out
    // naturally while the field settles; at rest it is exactly 0.
    final heat =
        math.sqrt(dx * dx + dy * dy) / 0.32;

    // The ambient breathing phase (0…1 over the ~9s loop, pinned at 0 under
    // reduced motion, so the resting arrangement itself is deterministic).
    final t = phase.value * 2 * math.pi;

    // Light mode stays restrained so the near-white card never reads stained;
    // dark mode may carry slightly more luminosity — the same physical
    // material under a stronger light.
    final baseAlpha = (isDark ? 0.26 : 0.15) * intensity;

    for (final spec in particleSpecs) {
      // Microscopic deterministic drift — ≤ ~1.2% of the card dimension.
      final angle = t * spec.speed + spec.phase * 2 * math.pi;
      final driftX = math.sin(angle) * w * 0.011;
      final driftY = math.cos(angle * 1.13 + spec.phase * 3.1) * h * 0.011;
      final rest = Offset(spec.x * w + driftX, spec.y * h + driftY);

      // Deform around the finger, and let the nearest points glow a touch
      // brighter — the field explains the touch without shouting.
      final pos = particleLean(rest, pointer, interactionRadius);
      final d = (rest - pointer).distance;
      final influence = d >= interactionRadius
          ? 0.0
          : (1.0 - d / interactionRadius);
      final eased = influence * influence;

      final color = colors[spec.colorIndex % colors.length];
      final alpha = (baseAlpha * (1.0 + eased * 1.6)).clamp(0.0, 0.5);
      final r = spec.radius * 3.4;

      final paint = Paint()
        ..shader = ui.Gradient.radial(
          pos,
          r,
          [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.45),
            color.withValues(alpha: 0.0),
          ],
          [0.0, 0.35, 1.0],
        );
      canvas.drawCircle(pos, r, paint);
    }

    // The soft local halo that explains WHY the particles are responding —
    // only while the interaction is active or settling, never at rest.
    if (heat > 0.02) {
      final haloAlpha = (isDark ? 0.07 : 0.045) * math.min(heat, 1.0);
      final haloR = interactionRadius * 0.55;
      final accent = colors.first;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(
            pointer,
            haloR,
            [
              accent.withValues(alpha: haloAlpha),
              accent.withValues(alpha: 0.0),
            ],
            [0.0, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReactiveParticlePainter oldDelegate) {
    return oldDelegate.dx != dx ||
        oldDelegate.dy != dy ||
        oldDelegate.intensity != intensity ||
        oldDelegate.isDark != isDark ||
        !listEquals(oldDelegate.colors, colors);
  }
}
