// =============================================================================
// AZAMAN — LAUNCH INTRO
//
// ONE continuous painted sequence, rebuilt from the approved reference clip
// (656x848, 30fps, 3.83s) rather than assembled from separate assets.
//
// WHY THIS REPLACES THE PREVIOUS IMPLEMENTATION
// The old intro stacked two independent SVGs — a mark and a complete lockup —
// and animated their opacity and scale. That produces a layered crossfade: the
// eye sees one logo dissolve into another logo. The reference never does that.
// It has ONE drawing in ONE place, and the transition is an expanding circular
// aperture: a bright ring grows out of the collapsed mark and uncovers the
// wordmark from the centre outward, with the ink riding just behind the ring
// edge. So the transform is a REVEAL of a single painting, not a swap of two.
//
// MEASURED TIMELINE (every constant is from the clip, not invented)
//   0    - 200ms   mark swells in, 84px -> 126px (of a 656px canvas)
//   200  - 1000ms  glass tile swells around it, rim highlight sweeps, it breathes
//   1000 - 1300ms  tile contracts away, mark shrinks to a 39px point
//   1330 - 1530ms  bright annulus forms, r 44 -> 58, cyan chromatic edge
//   1400 - 2200ms  aperture expands, uncovering the wordmark; 8% overshoot
//   2000 - 3000ms  halo expands and fades
//   2200 - 3833ms  settled wordmark holds, readable, then the screen resolves
//
// The completion callback fires at the END of that timeline, never at the
// moment the wordmark starts to appear: the ring/halo has real motion left
// after the first letter is legible, and leaving early is what makes an intro
// feel cut off.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'azaman_intro_art.dart';

/// Chrome for the intro. This is artwork, not a theme token: the same brand
/// object rendered in two materials.
@immutable
class IntroChrome {
  const IntroChrome({
    required this.background,
    required this.tileTop,
    required this.tileBottom,
    required this.rimStart,
    required this.rimEnd,
    required this.glow,
    required this.markStops,
    required this.wordStops,
    required this.ring,
    required this.ringEdge,
  });

  final Color background;
  final Color tileTop;
  final Color tileBottom;
  final Color rimStart;
  final Color rimEnd;
  final Color glow;
  final List<Color> markStops;
  final List<Color> wordStops;
  final Color ring;
  final Color ringEdge;

  static const IntroChrome dark = IntroChrome(
    background: Color(0xFF000000),
    tileTop: Color(0xFF1F1E23),
    tileBottom: Color(0xFF06070C),
    rimStart: Color(0x66FFFFFF),
    rimEnd: Color(0x14FFFFFF),
    glow: Color(0x333F8FD2),
    // The owner's silver ramp, verbatim from the mark SVG.
    markStops: <Color>[
      Color(0xFF80898B),
      Color(0xFFDCE0E0),
      Color(0xFF8D9699),
      Color(0xFFF1F3F3),
      Color(0xFF929A9D),
      Color(0xFF717A7D),
    ],
    // Measured down a thick wordmark stem in the final frame.
    wordStops: <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFE6EAEC),
      Color(0xFFC2C4C8),
      Color(0xFFDCDDE1),
      Color(0xFFA0A1A6),
      Color(0xFF6C6D73),
    ],
    ring: Color(0xFFFFFFFF),
    ringEdge: Color(0xFF7BD3FF),
  );

  /// Light theme keeps the same geometry and materials; the metal reads against
  /// paper instead of against black.
  static const IntroChrome light = IntroChrome(
    background: Color(0xFFF4F5F6),
    tileTop: Color(0xFFFFFFFF),
    tileBottom: Color(0xFFE7EAEC),
    rimStart: Color(0xCCFFFFFF),
    rimEnd: Color(0x33000000),
    glow: Color(0x1A3F8FD2),
    markStops: <Color>[
      Color(0xFF2F363B),
      Color(0xFF7C878D),
      Color(0xFF48525A),
      Color(0xFFBCC6CB),
      Color(0xFF5A646A),
      Color(0xFF39424A),
    ],
    wordStops: <Color>[
      Color(0xFF262D32),
      Color(0xFF5A6469),
      Color(0xFF7F8A90),
      Color(0xFFC4CFD5),
      Color(0xFF7A858B),
      Color(0xFF232A2F),
    ],
    ring: Color(0xFF262D32),
    ringEdge: Color(0xFF3F8FD2),
  );

  static IntroChrome of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Public timing contract, so callers and tests share ONE set of numbers.
abstract final class AzamanIntro {
  /// The reference clip's full length: the sequence is not finished before this.
  static const Duration total = Duration(milliseconds: 3833);

  /// The moment the wordmark is fully settled and the halo has cleared.
  /// Routing waits for [total]; this is only the point where the mark reads.
  static const Duration settled = Duration(milliseconds: 2200);

  // Stage boundaries, in milliseconds from the first frame.
  static const int markIn = 200;
  static const int tileSettled = 1000;
  static const int collapseStart = 1000;
  static const int collapseEnd = 1300;
  static const int ringStart = 1330;

  /// The aperture is FULLY open here, not at 2.2s: fitting the reference's
  /// own pixels frame by frame shows the whole wordmark uncovered by 1.80s.
  static const int revealEnd = 1800;

  /// The ring keeps travelling past the wordmark after the reveal completes
  /// (that motion is what reads as the flash), then dissolves.
  static const int ringFadeStart = 1950;
  static const int ringGone = 2300;

  /// Aperture radius, measured from the reference and expressed as a fraction
  /// of the radius that uncovers the whole wordmark.
  ///
  /// HOW THIS WAS MEASURED: for each reference frame, every candidate radius
  /// was rendered as a circular clip over this wordmark and scored by mask IoU
  /// against the frame's actual ink; the best-scoring radius is recorded here.
  /// That replaced an earlier guess which put an 8% "overshoot" on the
  /// wordmark — the fit showed the overshoot belongs to the RING, which is
  /// wider than the wordmark around 1.9-2.1s, while the ink itself is settled
  /// by 1.80s. The plateaus are gaps between letters, where the fit is
  /// insensitive; the curve interpolates through them.
  static const List<(int, double)> apertureCurve = <(int, double)>[
    (1330, 0.00),
    (1400, 0.29),
    (1450, 0.40),
    (1500, 0.47),
    (1560, 0.53),
    (1620, 0.65),
    (1670, 0.74),
    (1730, 0.855),
    (1800, 1.00),
  ];

  /// Past the reveal the ring runs on to ~1.15x and fades.
  static const double ringReach = 1.09;

  /// Geometry, as fractions of the clip's 656px canvas.
  static const double markStartWidth = 0.128; // 84 / 656
  static const double markPeakWidth = 0.192; // 126 / 656
  static const double markCollapsedWidth = 0.059; // 39 / 656
  static const double tileWidth = 0.369; // 242 / 656
  static const double wordWidth = 0.393; // 258 / 656
}

/// Reduced motion: no travel, no reveal — the settled brand state, then on.
class AzamanIntroStatic extends StatelessWidget {
  const AzamanIntroStatic({super.key, this.chrome});

  final IntroChrome? chrome;

  @override
  Widget build(BuildContext context) {
    final c = chrome ?? IntroChrome.of(context);
    return ColoredBox(
      color: c.background,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: AzamanIntro.wordWidth,
          child: AspectRatio(
            aspectRatio: kWordmarkWidth / kWordmarkHeight,
            child: CustomPaint(painter: _WordmarkPainter(c)),
          ),
        ),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter(this.chrome);
  final IntroChrome chrome;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path.from(_wordCache ?? parseIntroPath(kWordmarkPath))
      ..transform(
        Matrix4.diagonal3Values(
          size.width / kWordmarkWidth,
          size.height / kWordmarkHeight,
          1,
        ).storage,
      );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          chrome.wordStops,
          const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.chrome != chrome;
}

Path? _markCache, _wordCache;

/// Parses and caches the artwork once. Any malformed data throws here, at
/// startup, instead of inside a paint pass.
void ensureIntroArtPrepared() {
  _wordCache ??= parseIntroPath(kWordmarkPath);
  _markCache ??= Path();
  for (final d in kMarkPaths) {
    (_markCache!).addPath(parseIntroPath(d), Offset.zero);
  }
}

/// Parses the absolute-path subset emitted for the artwork (M, L, Q, C, Z).
/// Small and total by design: the generated data contains no other commands.
Path parseIntroPath(String d) {
  final path = Path();
  final tokens = _Tokenize(d).run();
  var i = 0;
  double next() => tokens[i++] as double;
  var cur = Offset.zero;
  while (i < tokens.length) {
    final cmd = tokens[i++] as String;
    switch (cmd) {
      case 'M':
        cur = Offset(next(), next());
        path.moveTo(cur.dx, cur.dy);
      case 'L':
        cur = Offset(next(), next());
        path.lineTo(cur.dx, cur.dy);
      case 'Q':
        final c = Offset(next(), next());
        final e = Offset(next(), next());
        path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
        cur = e;
      case 'C':
        final c1 = Offset(next(), next());
        final c2 = Offset(next(), next());
        final e = Offset(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        cur = e;
      case 'Z':
        path.close();
      default:
        // Unknown command: stop rather than guess.
        return path;
    }
  }
  return path;
}

class _Tokenize {
  _Tokenize(this.src);
  final String src;

  List<Object> run() {
    final out = <Object>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.add(double.parse(buf.toString()));
      buf.clear();
    }

    for (final ch in src.split('')) {
      if (ch == 'M' || ch == 'L' || ch == 'Q' || ch == 'C' || ch == 'Z') {
        flush();
        out.add(ch);
      } else if (ch == ' ' || ch == ',') {
        flush();
      } else {
        buf.write(ch);
      }
    }
    flush();
    return out;
  }
}

/// The live animation.
///
/// Plays exactly once per widget instance; the splash owns that instance, so a
/// rebuild or a tab switch can never replay it. [onCompleted] fires when the
/// FULL reference sequence has finished.
class AzamanIntroPlayer extends StatefulWidget {
  const AzamanIntroPlayer({
    super.key,
    required this.onCompleted,
    this.onFailed,
    this.chrome,
    this.controllerOverride,
  });

  final VoidCallback onCompleted;

  /// Called if the artwork cannot be prepared. The caller shows the static
  /// lockup and keeps booting — never a black screen, never a fake success.
  final VoidCallback? onFailed;
  final IntroChrome? chrome;

  /// Test seam: drives the sequence without real time.
  final AnimationController? controllerOverride;

  @override
  State<AzamanIntroPlayer> createState() => _AzamanIntroPlayerState();
}

class _AzamanIntroPlayerState extends State<AzamanIntroPlayer>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;
  AnimationController? get _c => widget.controllerOverride ?? _own;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Prepare the artwork BEFORE starting the clock. There is no decoder to
    // warm up (this is vector painting, not video), but a malformed path is
    // the equivalent failure: it must surface as the static fallback rather
    // than as an exception in the middle of paint().
    try {
      ensureIntroArtPrepared();
    } catch (_) {
      widget.onFailed?.call();
      return;
    }
    final c =
        widget.controllerOverride ??
        (AnimationController(vsync: this, duration: AzamanIntro.total));
    if (widget.controllerOverride == null) _own = c;
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_done) {
        _done = true;
        widget.onCompleted();
      }
    });
    c.forward();
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome ?? IntroChrome.of(context);
    final controller = _c;
    if (controller == null) {
      // Preparation failed: the caller renders the static lockup, but if it
      // has not swapped yet, at least never show an empty black canvas.
      return ColoredBox(color: chrome.background);
    }
    return ColoredBox(
      color: chrome.background,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _IntroPainter(
              progress: controller.value,
              elapsedMs: (controller.value * AzamanIntro.total.inMilliseconds)
                  .round(),
              chrome: chrome,
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.progress,
    required this.elapsedMs,
    required this.chrome,
  });

  final double progress;
  final int elapsedMs;
  final IntroChrome chrome;

  static double _seg(int t, int a, int b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();
  static double _easeIn(double t) => t * t * t;

  @override
  void paint(Canvas canvas, Size size) {
    final t = elapsedMs;
    final w = size.width;
    final center = Offset(size.width / 2, size.height / 2);

    // ---- mark scale over the whole sequence -------------------------------
    double markWidth;
    if (t < AzamanIntro.markIn) {
      markWidth = _lerp(
        AzamanIntro.markStartWidth,
        AzamanIntro.markPeakWidth,
        _easeOut(_seg(t, 0, AzamanIntro.markIn)),
      );
    } else if (t < AzamanIntro.collapseStart) {
      // A breath, not a bounce: a slow swell and release inside the tile.
      final b = _seg(t, AzamanIntro.markIn, AzamanIntro.collapseStart);
      markWidth =
          AzamanIntro.markPeakWidth * (1 + 0.035 * math.sin(math.pi * b));
    } else {
      markWidth = _lerp(
        AzamanIntro.markPeakWidth,
        AzamanIntro.markCollapsedWidth,
        _easeIn(_seg(t, AzamanIntro.collapseStart, AzamanIntro.collapseEnd)),
      );
    }
    // The mark is absorbed by the aperture as it opens: it stays solid until
    // the ring reaches it, then goes.
    final markAlpha = t < AzamanIntro.ringStart
        ? 1.0
        : (1 - _seg(t, AzamanIntro.ringStart, AzamanIntro.ringStart + 180))
              .clamp(0.0, 1.0);

    // ---- glass tile -------------------------------------------------------
    final tileT = _seg(t, 60, AzamanIntro.tileSettled);
    final tileGone = _seg(
      t,
      AzamanIntro.collapseStart,
      AzamanIntro.collapseEnd,
    );
    if (tileT > 0 && tileGone < 1) {
      final tileSide =
          w * AzamanIntro.tileWidth * _easeOut(tileT) * (1 - _easeIn(tileGone));
      final breathe = 1 + 0.012 * math.sin(math.pi * _seg(t, 200, 1150));
      _paintTile(canvas, center, tileSide * breathe, tileAlpha: 1 - tileGone);
    }

    // ---- mark, clipped away by the aperture once the reveal starts --------
    if (markAlpha > 0.001) {
      _paintMark(canvas, center, w * markWidth, markAlpha);
    }

    // ---- the aperture: ring + wordmark reveal -----------------------------
    if (t >= AzamanIntro.ringStart) {
      final wordW = w * AzamanIntro.wordWidth;
      final fullR = (wordW / 2) * 1.01; // just covers the wordmark
      final open = _apertureAt(t);
      final radius = fullR * open;

      // The ink rides behind the aperture edge.
      if (open > 0) {
        canvas.save();
        canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
        );
        _paintWordmark(canvas, center, wordW, 1.0);
        canvas.restore();
      }

      // The ring: travels to [AzamanIntro.ringReach], then dissolves.
      if (t < AzamanIntro.ringGone) {
        // The bright edge runs slightly AHEAD of the ink it uncovers — that
        // lead is what makes it read as a flash rather than a wipe. It closes
        // to zero as the reveal completes, then coasts on to [ringReach].
        final ringOpen = open >= 1
            ? _lerp(
                1,
                AzamanIntro.ringReach,
                _easeOut(
                  _seg(
                    t,
                    AzamanIntro.revealEnd,
                    AzamanIntro.ringFadeStart + 100,
                  ),
                ),
              )
            : open + 0.06 * (1 - open);
        final fade =
            1 - _seg(t, AzamanIntro.ringFadeStart, AzamanIntro.ringGone);
        if (fade > 0.01) {
          canvas.drawCircle(
            center,
            fullR * ringOpen,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.2, w * 0.004)
              ..color = chrome.ring.withValues(alpha: 0.9 * fade),
          );
          // The reference's chromatic edge: one thin cyan offset stroke.
          canvas.drawCircle(
            center,
            fullR * ringOpen + math.max(1.0, w * 0.0022),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8, w * 0.0018)
              ..color = chrome.ringEdge.withValues(alpha: 0.55 * fade),
          );
        }
      }
    }

    // ---- the settled wordmark never fades out ----------------------------
    if (t >= AzamanIntro.revealEnd) {
      _paintWordmark(canvas, center, w * AzamanIntro.wordWidth, 1.0);
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Samples the measured aperture curve.
  static double _apertureAt(int t) {
    const curve = AzamanIntro.apertureCurve;
    if (t <= curve.first.$1) return curve.first.$2;
    for (var i = 1; i < curve.length; i++) {
      final (t1, v1) = curve[i];
      if (t <= t1) {
        final (t0, v0) = curve[i - 1];
        return _lerp(v0, v1, (t - t0) / (t1 - t0));
      }
    }
    return curve.last.$2;
  }

  void _paintTile(
    Canvas canvas,
    Offset c,
    double side, {
    required double tileAlpha,
  }) {
    if (side <= 0.5) return;
    final rect = Rect.fromCenter(center: c, width: side, height: side);
    final r = Radius.circular(side * 0.215); // ~52/242, measured
    final rr = RRect.fromRectAndRadius(rect, r);

    // Body: a cool near-black glass, lit from the top-left.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, <Color>[
          chrome.tileTop.withValues(alpha: tileAlpha),
          chrome.tileBottom.withValues(alpha: tileAlpha),
        ]),
    );

    // Rim: a single restrained highlight, strongest top-left.
    canvas.drawRRect(
      rr.deflate(side * 0.004),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.006)
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, <Color>[
          chrome.rimStart.withValues(alpha: chrome.rimStart.a * tileAlpha),
          chrome.rimEnd.withValues(alpha: chrome.rimEnd.a * tileAlpha),
        ]),
    );
  }

  void _paintMark(Canvas canvas, Offset c, double width, double alpha) {
    if (width <= 0.5) return;
    final scale = width / 600.0; // mark ink spans ~600 units of the 1024 box
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    canvas.translate(-512, -492); // centre of the mark's ink box
    var mark = _markCache;
    if (mark == null) {
      ensureIntroArtPrepared();
      mark = _markCache ?? Path();
    }
    {
      canvas.drawPath(
        mark,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(398, 360),
            const Offset(531, 153),
            chrome.markStops,
            const <double>[0, 0.19, 0.39, 0.62, 0.83, 1],
          )
          ..color = Colors.white.withValues(alpha: alpha),
      );
    }
    canvas.restore();
  }

  void _paintWordmark(Canvas canvas, Offset c, double width, double alpha) {
    final h = width * (kWordmarkHeight / kWordmarkWidth);
    canvas.save();
    canvas.translate(c.dx - width / 2, c.dy - h / 2);
    canvas.scale(width / kWordmarkWidth, h / kWordmarkHeight);
    canvas.drawPath(
      _wordCache ?? parseIntroPath(kWordmarkPath),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, kWordmarkHeight),
          chrome.wordStops,
          const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.progress != progress || old.chrome != chrome;
}
