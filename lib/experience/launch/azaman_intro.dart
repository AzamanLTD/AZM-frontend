// =============================================================================
// AZAMAN — LAUNCH INTRO
//
// The first frame a user ever sees. Rebuilt from the approved reference
// motion as VECTOR artwork, not video: the chevron mark and the wordmark are
// SVG paths, so the entrance is resolution-independent (no upscaling on a
// 1440p tablet), theme-aware (separate chrome ramps for light and dark) and
// costs no decoder warm-up on a cold start.
//
// The reference the owner approved is 656 x 848 at 30fps, 3.73s:
//   icon in 0-500ms -> breathe to 950ms -> shrink to 37% by 1370ms ->
//   flash 1370-1600ms -> lockup reveal 1470-2320ms (9% overshoot) -> hold.
// Every constant below is measured from that reference, so the feel matches
// it while the pixels never do.
//
// The lockup is the brand lockup: the chevron mark stands in as the "A" of
// AZAMAN (owner decision, 2026-10-28), followed by "zaman".
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Chrome/glass palette for the intro. This is artwork, not a theme token:
/// the same brand object rendered in two materials.
@immutable
class _IntroChrome {
  const _IntroChrome({
    required this.background,
    required this.grid,
    required this.tileTop,
    required this.tileBottom,
    required this.rimStart,
    required this.rimMid,
    required this.rimEnd,
    required this.edge,
    required this.specular,
  });

  final Color background;
  final Color grid;
  final Color tileTop;
  final Color tileBottom;
  final Color rimStart;
  final Color rimMid;
  final Color rimEnd;

  /// The light that lives ON the square's edge (never a halo behind it).
  final Color edge;
  final Color specular;

  static const dark = _IntroChrome(
    background: Color(0xFF000000),
    grid: Color(0xFF8A9BA8),
    tileTop: Color(0xFF15161B),
    tileBottom: Color(0xFF040406),
    rimStart: Color(0xFF8FA3B0),
    rimMid: Color(0xFF1D2228),
    rimEnd: Color(0xFFC6D7E1),
    edge: Color(0xFFA9D4EC),
    specular: Color(0xFF115AEE),
  );

  static const light = _IntroChrome(
    background: Color(0xFFF4F5F6),
    grid: Color(0xFF5C6A70),
    tileTop: Color(0xFFFFFFFF),
    tileBottom: Color(0xFFE7EAEC),
    rimStart: Color(0xFFFFFFFF),
    rimMid: Color(0xFFD3D9DC),
    rimEnd: Color(0xFFB7C2C8),
    edge: Color(0xFFFFFFFF),
    specular: Color(0xFF8FA3B0),
  );
}

/// The launch entrance: glass tile, chrome mark, then the lockup.
///
/// Pass [animate] false (reduced motion) to render the settled lockup straight
/// away, and [onRevealed] to learn when the lockup has finished settling so a
/// caller can hand off to the app without a fixed wait.
class AzamanIntro extends StatefulWidget {
  const AzamanIntro({super.key, this.onRevealed, this.animate = true});

  final VoidCallback? onRevealed;
  final bool animate;

  /// Milliseconds from mount to the settled lockup.
  ///
  /// The reference settles at 2320ms, but the app's branding floor is 2s and
  /// the startup contract (router tests + perceived cold start) is built
  /// around it. The entrance therefore PLAYS THE SAME CHOREOGRAPHY 14%
  /// FASTER rather than stretching every cold start by 320ms — the pacing
  /// is invisible, the startup contract is untouched.
  static const int revealMs = 2000;

  /// Reference length scaled by the same pace factor.
  static const int totalMs = 3218;

  /// Reference choreography (measured) -> paced: the melt window below is
  /// expressed in these units and divided by the pace.
  static const double _pace = revealMs / 2320;

  @override
  State<AzamanIntro> createState() => _AzamanIntroState();
}

class _AzamanIntroState extends State<AzamanIntro>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fireRevealed());
      return;
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AzamanIntro.totalMs),
    )..addListener(_onTick);
    _controller!.forward();
  }

  void _onTick() {
    final ms = _elapsed;
    if (!_revealed && ms >= AzamanIntro.revealMs) _fireRevealed();
  }

  void _fireRevealed() {
    if (_revealed) return;
    _revealed = true;
    widget.onRevealed?.call();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Elapsed time in REFERENCE milliseconds (the constants below are the
  /// measured ones, so the choreography reads exactly as it was measured).
  int get _elapsed => _controller == null
      ? AzamanIntro.totalMs
      : (AzamanIntro.totalMs / AzamanIntro._pace * _controller!.value).round();

  static double _seg(int t, int from, int to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0).toDouble();

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final chrome = Theme.of(context).brightness == Brightness.dark
        ? _IntroChrome.dark
        : _IntroChrome.light;
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';

    return ColoredBox(
      color: chrome.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // The reference tile is 36.6% of the frame width (240 of 656).
          // The floor is deliberately small: clamping up would break the
          // composition on a phone, which is where most of these run.
          final tileSize = (width * 0.366).clamp(120.0, 320.0).toDouble();
          final markWidth = tileSize * 0.479;
          final lockupWidth = (width * 0.584).clamp(180.0, 520.0).toDouble();
          final lockupHeight = lockupWidth * 192 / 819;

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DotGridPainter(
                  color: chrome.grid,
                  step: width / 22.6,
                  dotRadius: width / 596,
                ),
              ),
              if (widget.animate)
                AnimatedBuilder(
                  animation: _controller!,
                  builder: (context, _) => _buildStage(
                    chrome,
                    suffix,
                    tileSize,
                    markWidth,
                    lockupWidth,
                    lockupHeight,
                    height,
                  ),
                )
              else
                _buildSettledLockup(chrome, suffix, lockupWidth, lockupHeight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettledLockup(
    _IntroChrome chrome,
    String suffix,
    double w,
    double h,
  ) {
    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: SvgPicture.asset(
          'assets/experience/azaman_intro/lockup_$suffix.svg',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildStage(
    _IntroChrome chrome,
    String suffix,
    double tileSize,
    double markWidth,
    double lockupWidth,
    double lockupHeight,
    double viewportHeight,
  ) {
    final t = _elapsed;

    // --- icon phase -----------------------------------------------------
    final enter = Curves.easeOutQuint.transform(_seg(t, 0, 500));
    final breathe =
        1 + 0.016 * math.sin((math.max(0, t - 500) / 700) * math.pi * 2);
    final enterScale = _lerp(1.15, 1.0, enter) * breathe;

    double markScale;
    double tileOpacity;
    if (t < 950) {
      markScale = enterScale;
      tileOpacity = 1;
    } else if (t < 1370) {
      final shrink = Curves.easeInOut.transform(_seg(t, 950, 1370));
      markScale = _lerp(enterScale, 0.374, shrink);
      tileOpacity = 1 - shrink;
    } else {
      final flashIn = Curves.easeOutQuint.transform(_seg(t, 1370, 1600));
      markScale = _lerp(0.374, 1.06, flashIn);
      tileOpacity = 0;
    }
    final tileScale =
        _lerp(0.94, 1.0, _seg(t, 0, 420)) *
        _lerp(1.0, 1.05, Curves.easeInOut.transform(_seg(t, 950, 1370)));

    // Liquid melt: 0 outside the window, 1 at its peak (f42 = 1380ms).
    final meltIn = Curves.easeInCubic.transform(_seg(t, 1240, 1380));
    final meltOut = Curves.easeOutCubic.transform(_seg(t, 1380, 1620));
    final melt = (meltIn * (1 - meltOut)).clamp(0.0, 1.0).toDouble();

    final markOpacity = t < 1470 ? 1.0 : 1 - _seg(t, 1470, 1620);
    final flashCurve = Curves.easeOutQuint.transform(_seg(t, 1370, 1600));
    final markGlow =
        (0.30 * _seg(t, 80, 420) + 0.9 * flashCurve * (1 - _seg(t, 1620, 1900)))
            .clamp(0.0, 1.0)
            .toDouble();

    // --- lockup reveal --------------------------------------------------
    final grow = Curves.easeOutQuint.transform(_seg(t, 1470, 2000));
    final settle = Curves.easeInOut.transform(_seg(t, 2000, 2320));
    final lockScale = _lerp(0.45, 1.09, grow) + (1.0 - 1.09) * settle;
    final lockOpacity = Curves.easeOutCubic.transform(_seg(t, 1470, 1800));

    // --- specular sweep -------------------------------------------------
    final isPaper = Theme.of(context).brightness == Brightness.light;
    // Dark rides a white blade; paper rides bright steel so the sweep reads as
    // a sheen instead of a white-out.
    final sweepPaper = isPaper ? 0.82 : 0.0;
    final sweepStrength = isPaper ? 0.55 : 1.0;
    final sweepT = _seg(t, 1520, 2050);
    final sweepX = _lerp(-1.6, 1.6, Curves.easeInOut.transform(sweepT));

    return Stack(
      fit: StackFit.expand,
      children: [
        // Glass tile with the light ON its edge.
        Center(
          child: Opacity(
            opacity: tileOpacity,
            child: Transform.scale(
              scale: tileScale,
              child: _GlassTile(size: tileSize, chrome: chrome),
            ),
          ),
        ),

        // Chrome mark. The liquid melt lives HERE: a gooey blur + alpha
        // threshold closes the tier gaps so the mark behaves like one blob
        // for the beat before it resolves, with a slight squash to sell the
        // surface tension.
        Center(
          child: Opacity(
            opacity: markOpacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(
              scale: markScale,
              child: Transform.scale(
                scaleX: 1 + 0.07 * melt,
                scaleY: 1 - 0.06 * melt,
                child: _goo(
                  melt: melt,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (markGlow > 0.01)
                        Opacity(
                          opacity: markGlow * 0.55,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                chrome.edge,
                                BlendMode.srcIn,
                              ),
                              child: SvgPicture.asset(
                                'assets/experience/azaman_intro/mark_$suffix.svg',
                                width: markWidth,
                                height: markWidth * 549 / 564,
                              ),
                            ),
                          ),
                        ),
                      SvgPicture.asset(
                        'assets/experience/azaman_intro/mark_$suffix.svg',
                        width: markWidth,
                        height: markWidth * 549 / 564,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Brand lockup: the mark stands in as the "A".
        Center(
          child: Opacity(
            opacity: lockOpacity,
            child: Transform.scale(
              scale: lockScale,
              child: ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (Rect bounds) => LinearGradient(
                  begin: Alignment(sweepX - 0.45, -1),
                  end: Alignment(sweepX + 0.45, 1),
                  colors: [
                    chrome.specular.withValues(alpha: 0.0),
                    chrome.specular.withValues(alpha: sweepStrength * 0.55),
                    // The blade: white on dark glass, bright steel on paper.
                    Color.lerp(
                      Colors.white,
                      chrome.specular,
                      sweepPaper,
                    )!.withValues(alpha: sweepStrength * 0.9),
                    chrome.specular.withValues(alpha: sweepStrength * 0.45),
                    chrome.specular.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
                ).createShader(bounds),
                child: SizedBox(
                  width: lockupWidth,
                  height: lockupHeight,
                  child: SvgPicture.asset(
                    'assets/experience/azaman_intro/lockup_$suffix.svg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gooey melt: blur the silhouette, then push alpha through a steep ramp so
/// the blurred edges snap to solid/transparent. Gaps narrower than the blur
/// radius fuse; the silhouette stays crisp because the ramp is sharp.
///
/// `melt` is 0 outside the melt window, so this costs nothing for most of the
/// entrance (the child is returned untouched below the threshold).
class _Goo extends StatelessWidget {
  const _Goo({required this.melt, required this.child});

  final double melt;
  final Widget child;

  static const ColorFilter _ramp = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 20, -8, // alpha: 0.40 becomes the fusing edge
  ]);

  @override
  Widget build(BuildContext context) {
    if (melt < 0.02) return child;
    final sigma = 0.5 + 5.5 * melt;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: ColorFiltered(colorFilter: _ramp, child: child),
    );
  }
}

Widget _goo({required double melt, required Widget child}) =>
    _Goo(melt: melt, child: child);

/// The dark glass square. No halo behind it: the light sits on the rim, as a
/// gradient border plus a tight inner highlight, so the tile reads as lit
/// glass rather than as a glow source.
class _GlassTile extends StatelessWidget {
  const _GlassTile({required this.size, required this.chrome});

  final double size;
  final _IntroChrome chrome;

  @override
  Widget build(BuildContext context) {
    final radius = size * (52 / 240);
    final border = size * (1.3 / 240);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [chrome.rimStart, chrome.rimMid, chrome.rimEnd],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(border),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius - border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [chrome.tileTop, chrome.tileBottom],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - border),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference carries a very faint dot grid behind the artwork. At ~2%
/// alpha it adds depth without ever reading as a pattern.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({
    required this.color,
    required this.step,
    required this.dotRadius,
  });

  final Color color;
  final double step;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.055);
    for (double y = dotRadius; y < size.height; y += step) {
      for (double x = dotRadius; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.step != step ||
      oldDelegate.dotRadius != dotRadius;
}
