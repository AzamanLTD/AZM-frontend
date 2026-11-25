// =============================================================================
// AZAMAN — LAUNCH INTRO
//
// The production splash plays the theme-matched MP4 renders from the Rive
// source project in rive/azaman-liquid and rive/azaman-liquid-light. A native
// video surface keeps startup independent of a Rive runtime export watermark;
// the editable Rive source and its Luau script remain alongside the app asset.
//
// The 3-second sequence is mark-only: liquid refraction brings the silver mark
// in, the distortion settles for a centered hold, then a returning fluid swell
// carries the mark away. The completion callback fires only after the full
// sequence, while startup work runs concurrently behind the splash.
// =============================================================================

import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'azaman_intro_art.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';

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
    background: Color(0xFF010103),
    tileTop: Color(0xFF141820),
    tileBottom: Color(0xFF05070B),
    rimStart: Color(0xB3EEF3FF),
    rimEnd: Color(0x3305070B),
    glow: Color(0x224D6F98),
    // The dark-theme ink is the supplied cool white, with restrained metallic
    // reflections so the three-arc master still reads as polished silver.
    markStops: <Color>[
      Color(0xFFF2F5FA),
      Color(0xFFC7CED8),
      Color(0xFFF2F5FA),
      Color(0xFFAEB7C4),
      Color(0xFFEEF3FF),
      Color(0xFFF2F5FA),
    ],
    wordStops: <Color>[
      Color(0xFFF2F5FA),
      Color(0xFFC7CED8),
      Color(0xFFF2F5FA),
      Color(0xFFAEB7C4),
      Color(0xFFEEF3FF),
      Color(0xFFF2F5FA),
    ],
    ring: Color(0xFFF2F5FA),
    ringEdge: Color(0xFFAEBFD1),
  );

  /// Light theme keeps the same geometry and materials; the metal reads against
  /// paper instead of against black.
  static const IntroChrome light = IntroChrome(
    background: Color(0xFFF4F4F7),
    tileTop: Color(0xFFFFFFFF),
    tileBottom: Color(0xFFE4E7EF),
    rimStart: Color(0xCCFFFFFF),
    rimEnd: Color(0x33000000),
    glow: Color(0x14343F52),
    markStops: <Color>[
      Color(0xFF0B0C11),
      Color(0xFF3A4148),
      Color(0xFF101116),
      Color(0xFF59616A),
      Color(0xFF1C1F24),
      Color(0xFF0B0C11),
    ],
    wordStops: <Color>[
      Color(0xFF0B0C11),
      Color(0xFF3A4148),
      Color(0xFF101116),
      Color(0xFF59616A),
      Color(0xFF1C1F24),
      Color(0xFF0B0C11),
    ],
    ring: Color(0xFF0B0C11),
    ringEdge: Color(0xFF58616C),
  );

  static IntroChrome of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Public timing contract, so callers and tests share ONE set of numbers.
abstract final class AzamanIntro {
  /// The full Rive-rendered launch sequence played by the Flutter splash.
  static const Duration total = Duration(milliseconds: 3000);

  /// The calm, centered mark hold in the middle of the liquid sequence.
  static const Duration settled = Duration(milliseconds: 1500);

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

/// Reduced motion and decoder-failure fallback: show the centered mark, then on.
class AzamanIntroStatic extends StatelessWidget {
  const AzamanIntroStatic({super.key, this.chrome});

  final IntroChrome? chrome;

  @override
  Widget build(BuildContext context) {
    final c = chrome ?? IntroChrome.of(context);
    return ColoredBox(
      color: c.background,
      child: SizedBox.expand(child: CustomPaint(painter: _MarkHoldPainter(c))),
    );
  }
}

/// Vector-authored alternative to the supplied clips. Kept available for
/// iterating on motion in Flutter; the splash currently uses
/// [AzamanIntroPlayer] to preserve the richer reference effect faithfully.
class AzamanIntroMotion extends StatefulWidget {
  const AzamanIntroMotion({super.key, required this.onCompleted, this.chrome});

  final VoidCallback onCompleted;
  final IntroChrome? chrome;

  @override
  State<AzamanIntroMotion> createState() => _AzamanIntroMotionState();
}

class _AzamanIntroMotionState extends State<AzamanIntroMotion>
    with SingleTickerProviderStateMixin {
  static bool _playedInProcess = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AzamanIntro.total,
  );

  @override
  void initState() {
    super.initState();
    if (_playedInProcess) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted();
      });
      return;
    }
    _playedInProcess = true;
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onCompleted();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome ?? IntroChrome.of(context);
    return ColoredBox(
      color: chrome.background,
      child: Center(
        child: AspectRatio(
          aspectRatio: kLaunchAspectRatio,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _AzamanIntroPainter(_controller.value, chrome),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AzamanIntroPainter extends CustomPainter {
  _AzamanIntroPainter(this.progress, this.chrome);

  final double progress;
  final IntroChrome chrome;

  static const Size _designSize = Size(656, 848);
  static const Offset _center = Offset(328, 424);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    ensureIntroArtPrepared();
    canvas.save();
    canvas.scale(
      size.width / _designSize.width,
      size.height / _designSize.height,
    );

    final time = progress.clamp(0.0, 1.0) * AzamanIntro.total.inMilliseconds;
    _paintGlassTile(canvas, time);
    _paintMark(canvas, time);
    _paintWordReveal(canvas, time);
    _paintLensAndRings(canvas, time);

    canvas.restore();
  }

  void _paintGlassTile(Canvas canvas, double time) {
    final appear = _ease(time, 180, 430);
    final collapse = _ease(
      time,
      AzamanIntro.collapseStart.toDouble(),
      AzamanIntro.collapseEnd.toDouble(),
    );
    final opacity = appear * (1 - collapse);
    if (opacity <= 0.001) return;

    final breathe = 1 + 0.012 * math.sin((time - 260) / 260);
    final edge = AzamanIntro.tileWidth * _designSize.width;
    final side =
        edge * (0.72 + 0.28 * appear) * (1 - 0.94 * collapse) * breathe;
    final rect = Rect.fromCenter(center: _center, width: side, height: side);
    final radius = Radius.circular(side * 0.225);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    canvas.drawRRect(
      rrect.shift(const Offset(0, 8)),
      Paint()
        ..color = _alpha(chrome.glow, opacity * 0.62)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, <Color>[
          _alpha(chrome.tileTop, opacity * 0.58),
          _alpha(chrome.tileBottom, opacity * 0.78),
        ]),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, <Color>[
          _alpha(chrome.rimStart, opacity),
          _alpha(chrome.rimEnd, opacity),
        ]),
    );

    final sweep = _ease(time, 370, 910);
    if (sweep > 0 && sweep < 1) {
      canvas.save();
      canvas.clipRRect(rrect);
      final x = rect.left - side * 0.25 + side * 1.5 * sweep;
      canvas.drawLine(
        Offset(x - side * 0.08, rect.top),
        Offset(x + side * 0.08, rect.bottom),
        Paint()
          ..color = _alpha(Colors.white, opacity * 0.20)
          ..strokeWidth = side * 0.11
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      canvas.restore();
    }

    final bubblePhase = _ease(time, 660, 980);
    if (bubblePhase > 0 && collapse < 0.1) {
      final bubblePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _alpha(chrome.rimStart, (1 - bubblePhase) * 0.5);
      canvas.drawCircle(
        Offset(
          _center.dx + side * 0.27,
          _center.dy - side * 0.36 * bubblePhase,
        ),
        4.5,
        bubblePaint,
      );
      canvas.drawCircle(
        Offset(
          _center.dx - side * 0.31,
          _center.dy - side * 0.18 * bubblePhase,
        ),
        2.6,
        bubblePaint,
      );
    }
  }

  void _paintMark(Canvas canvas, double time) {
    final visibility = 1 - _ease(time, 1330, 1550);
    if (visibility <= 0.001) return;
    final swell = _ease(time, 0, AzamanIntro.markIn.toDouble());
    final collapse = _ease(
      time,
      AzamanIntro.collapseStart.toDouble(),
      AzamanIntro.collapseEnd.toDouble(),
    );
    final width =
        ui.lerpDouble(
              AzamanIntro.markStartWidth * _designSize.width,
              AzamanIntro.markPeakWidth * _designSize.width,
              swell,
            )! *
            (1 - collapse) +
        AzamanIntro.markCollapsedWidth * _designSize.width * collapse;
    final scale = width / kMarkBox;
    final rect = Rect.fromCenter(center: _center, width: width, height: width);
    final mark = _markCache!;

    if (time < AzamanIntro.collapseEnd + 200) {
      canvas.drawPath(
        _transformed(mark, scale, rect.topLeft),
        Paint()
          ..color = _alpha(chrome.glow, 0.46 * visibility)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawPath(
      _transformed(mark, scale, rect.topLeft),
      Paint()
        ..color = _alpha(Colors.white, visibility)
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          chrome.markStops,
          const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
        ),
    );

    // A narrow travelling highlight gives the metal one deliberate light pass.
    final glint = _ease(time, 520, 940);
    if (glint > 0 && glint < 1 && collapse < 0.1) {
      final x = rect.left - width * 0.2 + width * 1.4 * glint;
      canvas.save();
      canvas.clipPath(_transformed(mark, scale, rect.topLeft));
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x + width * 0.12, rect.bottom),
        Paint()
          ..color = _alpha(Colors.white, 0.62)
          ..strokeWidth = math.max(1.0, width * 0.035)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.restore();
    }
  }

  void _paintWordReveal(Canvas canvas, double time) {
    if (time < AzamanIntro.ringStart) return;
    final wordWidth = AzamanIntro.wordWidth * _designSize.width;
    final wordHeight = wordWidth * kWordmarkHeight / kWordmarkWidth;
    final wordRect = Rect.fromCenter(
      center: _center,
      width: wordWidth,
      height: wordHeight,
    );
    final reveal = _ease(time, 1400, AzamanIntro.revealEnd.toDouble());
    final aperture = 176 * reveal;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: _center, radius: aperture)),
    );
    canvas.drawPath(
      _transformed(_wordCache!, wordWidth / kWordmarkWidth, wordRect.topLeft),
      Paint()
        ..shader = ui.Gradient.linear(
          wordRect.topLeft,
          wordRect.bottomRight,
          chrome.wordStops,
          const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
        ),
    );

    final streak = _ease(time, 1810, 2170);
    if (streak > 0 && streak < 1) {
      final x = wordRect.left - wordWidth * 0.22 + wordWidth * 1.44 * streak;
      canvas.drawLine(
        Offset(x, wordRect.top - 2),
        Offset(x + wordWidth * 0.075, wordRect.bottom + 2),
        Paint()
          ..color = _alpha(
            Colors.white,
            0.50 * (1 - (streak - 0.5).abs() * 1.5),
          )
          ..strokeWidth = math.max(1.2, wordWidth * 0.012)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.restore();
  }

  void _paintLensAndRings(Canvas canvas, double time) {
    if (time < AzamanIntro.ringStart) return;
    final inProgress = _ease(time, 1330, 1530);
    final fade =
        1 -
        _ease(
          time,
          AzamanIntro.ringFadeStart.toDouble(),
          AzamanIntro.ringGone.toDouble(),
        );
    final radius = 44 + 28 * inProgress + 104 * _ease(time, 1530, 1960);
    final opacity = (inProgress * fade).clamp(0.0, 1.0);
    if (opacity <= 0.001) return;

    canvas.drawCircle(
      _center,
      radius * 1.7,
      Paint()
        ..shader = ui.Gradient.radial(_center, radius * 1.7, <Color>[
          _alpha(chrome.glow, opacity * 0.8),
          _alpha(chrome.glow, 0),
        ]),
    );
    canvas.drawCircle(
      _center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..color = _alpha(chrome.ringEdge, opacity * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      _center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _alpha(chrome.ring, opacity),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: _center + const Offset(0, 5),
        width: radius * 2.0,
        height: radius * 0.50,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _alpha(chrome.ringEdge, opacity * 0.42),
    );
  }

  static Path _transformed(Path source, double scale, Offset translation) {
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, translation.dx)
      ..setEntry(1, 3, translation.dy);
    return Path.from(source)..transform(matrix.storage);
  }

  static double _ease(double time, double start, double end) {
    if (end <= start) return time >= end ? 1 : 0;
    final t = ((time - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(t);
  }

  static Color _alpha(Color color, double opacity) =>
      color.withAlpha((color.a * 255 * opacity.clamp(0.0, 1.0)).round());

  @override
  bool shouldRepaint(_AzamanIntroPainter old) =>
      old.progress != progress || old.chrome != chrome;
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

// ---------------------------------------------------------------------------
// LEGACY VIDEO PLAYBACK TEST SEAM
// ---------------------------------------------------------------------------

/// Video playback for the supplied light and dark launch compositions.
const String kLaunchVideoDarkAsset =
    'assets/experience/launch/azaman_launch_dark.mp4';
const String kLaunchVideoLightAsset =
    'assets/experience/launch/azaman_launch_light.mp4';
const String kLaunchVideoAsset = kLaunchVideoDarkAsset;

/// The supplied light and dark clips are 932 x 1460. Keep this exact ratio
/// during decoder startup so the frame-zero hold has the same vertical
/// composition and position as the first decoded frame.
const double kLaunchAspectRatio = 932 / 1460;

/// Seam over the platform player.
///
/// The launch has to be exercisable without the plugin: the assertions that
/// matter are about the SEQUENCE (plays once, never reports early, holds the
/// settled state on failure), and none of those need real time or a decoder.
abstract class LaunchVideo {
  Future<void> initialize();
  Future<void> setVolume(double value);
  Future<void> play();
  Future<void> seekTo(Duration position);
  Future<void> dispose();
  bool get isInitialized;
  bool get isPlaying;
  bool get hasError;
  Duration get position;
  Duration get duration;
  double get aspectRatio;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  Widget buildSurface();
}

/// Asset-backed player for the theme-specific launch composition.
class AssetLaunchVideo implements LaunchVideo {
  AssetLaunchVideo({String asset = kLaunchVideoAsset})
    : _controller = VideoPlayerController.asset(asset);

  final VideoPlayerController _controller;

  @override
  Future<void> initialize() => _controller.initialize();
  @override
  Future<void> setVolume(double value) => _controller.setVolume(value);
  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);
  @override
  Future<void> dispose() => _controller.dispose();
  @override
  bool get isInitialized => _controller.value.isInitialized;
  @override
  bool get isPlaying => _controller.value.isPlaying;
  @override
  bool get hasError => _controller.value.hasError;
  @override
  Duration get position => _controller.value.position;
  @override
  Duration get duration => _controller.value.duration;
  @override
  double get aspectRatio => _controller.value.isInitialized
      ? _controller.value.aspectRatio
      : kLaunchAspectRatio;
  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);
  @override
  Widget buildSurface() => VideoPlayer(_controller);
}

/// Test hook: the "already played" guard is per process, which is what stops a
/// rebuild or an internal navigation replaying the entrance. Tests need to
/// clear it between cases.
@visibleForTesting
void resetLaunchPlayGuard() {
  _AzamanIntroPlayerState._playedInProcess = false;
  _AzamanIntroMotionState._playedInProcess = false;
}

/// Player for the theme-specific composition used by the production splash.
///
/// [onFailed] is for a genuine playback failure (no decoder, corrupt asset,
/// stalled player). The caller swaps in [AzamanIntroStatic]; this widget also
/// renders it, so a failure never leaves an empty canvas.
class AzamanIntroPlayer extends StatefulWidget {
  const AzamanIntroPlayer({
    super.key,
    required this.onCompleted,
    this.onFailed,
    this.chrome,
    this.video,
    this.asset,
  });

  /// Fires when the clip has reached its end — the full sequence, not an
  /// approximation of it. [AzamanIntro.total] is the floor, enforced by the
  /// watchdog, so a silently dead player cannot strand the splash.
  final VoidCallback onCompleted;

  /// Fires on a real failure. Never fires together with [onCompleted] for the
  /// same playback, so the caller can hold the settled state and move on
  /// without pretending the video played.
  final VoidCallback? onFailed;
  final IntroChrome? chrome;

  /// Test seam. Production passes nothing and gets [AssetLaunchVideo].
  final LaunchVideo? video;

  /// Theme-specific reference composition for production playback.
  final String? asset;

  @override
  State<AzamanIntroPlayer> createState() => _AzamanIntroPlayerState();
}

class _AzamanIntroPlayerState extends State<AzamanIntroPlayer> {
  /// One entrance per app process. A widget rebuild, a theme change or an
  /// internal navigation cannot replay it: the second instance reports
  /// completion immediately and paints the settled frame instead.
  static bool _playedInProcess = false;

  late final LaunchVideo _video =
      widget.video ??
      AssetLaunchVideo(asset: widget.asset ?? kLaunchVideoAsset);
  late final bool _ownsVideo = widget.video == null;

  bool _ready = false;
  bool _done = false;
  bool _failed = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    if (_playedInProcess) {
      _done = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted();
      });
      return;
    }
    _playedInProcess = true;
    _start();
  }

  Future<void> _start() async {
    try {
      // The packaged asset has no audio track at all; muting is a second belt
      // so a future replacement clip cannot start making noise in a lift.
      await _video.setVolume(0);
      await _video.initialize();
      if (!mounted) return;
      if (_video.hasError) return _fail();

      // Start from the top: a reused platform player could otherwise resume.
      await _video.seekTo(Duration.zero);
      _video.addListener(_onTick);
      await _video.play();
      if (!mounted) return;
      setState(() => _ready = true);

      _watchdog = Timer(
        AzamanIntro.total + const Duration(milliseconds: 1500),
        () {
          if (!_done) _fail();
        },
      );
    } catch (_) {
      _fail();
    }
  }

  void _onTick() {
    if (_done || !mounted) return;
    if (_video.hasError) return _fail();
    final total = _video.duration;
    if (total <= Duration.zero) return;
    if (_video.position >= total - const Duration(milliseconds: 120)) {
      _complete();
    }
  }

  void _complete() {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    widget.onCompleted();
  }

  void _fail() {
    if (_done || _failed) return;
    _failed = true;
    _watchdog?.cancel();
    if (mounted) setState(() {});
    widget.onFailed?.call();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    if (!_playedInProcess || _ownsVideo) {
      _video.removeListener(_onTick);
      if (_ownsVideo) _video.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome ?? IntroChrome.dark;
    if (_failed) return AzamanIntroStatic(chrome: chrome);
    return ColoredBox(
      color: chrome.background,
      child: Center(
        child: AspectRatio(
          aspectRatio: _ready ? _video.aspectRatio : kLaunchAspectRatio,
          // Until the decoder has produced a frame, hold the clip's OWN first
          // composition (the mark alone on black), which is also what the
          // native splash shows. Nothing else is drawn, so there is no second
          // logo and no blank frame between the system splash and playback.
          child: _ready
              ? _video.buildSurface()
              : _LaunchFrameZeroHold(
                  key: const ValueKey('launch-frame-zero'),
                  chrome: chrome,
                ),
        ),
      ),
    );
  }
}

/// Static hold of the clip's frame 0: the silver mark, centred, at its exact
/// size relative to the frame. Used only before the first decoded frame and by
/// the failure path — never animated, so it cannot read as its own entrance.
class _LaunchFrameZeroHold extends StatelessWidget {
  const _LaunchFrameZeroHold({super.key, required this.chrome});
  final IntroChrome chrome;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: chrome.background,
    child: SizedBox.expand(
      child: CustomPaint(painter: _MarkHoldPainter(chrome, widthFraction: 0.2)),
    ),
  );
}

class _MarkHoldPainter extends CustomPainter {
  const _MarkHoldPainter(this.chrome, {this.widthFraction = 0.4});

  final IntroChrome chrome;
  final double widthFraction;

  static List<Path>? _paths;

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _paths ??= kMarkPaths
        .map(parseIntroPath)
        .toList(growable: false);
    // Match the rendered mark's ~40% of the artboard, with the three arcs
    // themselves occupying the central ~56% of the source SVG's square box.
    final width = size.width * widthFraction;
    if (width <= 0) return;
    final scale = width / kMarkBox;
    canvas.save();
    canvas.translate((size.width - width) / 2, (size.height - width) / 2);
    canvas.scale(scale);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, kMarkBox),
        chrome.markStops,
        const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
      );
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkHoldPainter oldDelegate) =>
      oldDelegate.chrome != chrome ||
      oldDelegate.widthFraction != widthFraction;
}
