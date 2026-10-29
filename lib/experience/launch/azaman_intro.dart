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

import 'dart:ui' as ui;

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

// ---------------------------------------------------------------------------
// THE CLIP IS THE ANIMATION
// ---------------------------------------------------------------------------

/// The owner's motion reference, packaged as an asset and played as-is.
///
/// Everything above is brand material: the chrome, the settled wordmark lockup
/// and the path parses that draw it. Everything below plays the actual motion.
///
/// An earlier revision re-drew the sequence with a painter. It matched the
/// measured frames closely and still read as separate artwork being swapped,
/// because every transition between mark, tile, ring and wordmark was
/// reconstructed from stills rather than played. Tests on that painter passed
/// while the owner was reporting the defect: they asserted the reconstruction,
/// not the motion. This file no longer competes with the reference.
const String kLaunchVideoAsset = 'assets/experience/launch/azaman_launch.mp4';

/// The clip's own frame geometry (656 x 848). The launch is letterboxed on
/// black rather than cropped, so no part of the composition is lost on a
/// taller phone and the clip's black ground blends into the viewport.
const double kLaunchAspectRatio = 656 / 848;

/// Silver gradient of the owner's mark, in the 1024-unit design box.
const List<Color> kMarkSilver = <Color>[
  Color(0xFF80898B),
  Color(0xFFDCE0E0),
  Color(0xFF8D9699),
  Color(0xFFF1F3F3),
  Color(0xFF929A9D),
  Color(0xFF717A7D),
];

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

/// Production player. Asset-backed, silent, played exactly once.
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
void resetLaunchPlayGuard() => _AzamanIntroPlayerState._playedInProcess = false;

/// Plays the reference clip once, reports only when it has finished, and keeps
/// the final wordmark on screen afterwards instead of cutting to black.
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

  @override
  State<AzamanIntroPlayer> createState() => _AzamanIntroPlayerState();
}

class _AzamanIntroPlayerState extends State<AzamanIntroPlayer> {
  /// One entrance per app process. A widget rebuild, a theme change or an
  /// internal navigation cannot replay it: the second instance reports
  /// completion immediately and paints the settled frame instead.
  static bool _playedInProcess = false;

  late final LaunchVideo _video = widget.video ?? AssetLaunchVideo();
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
    child: const SizedBox.expand(
      child: CustomPaint(painter: _MarkHoldPainter()),
    ),
  );
}

class _MarkHoldPainter extends CustomPainter {
  const _MarkHoldPainter();

  static List<Path>? _paths;

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _paths ??= kMarkPaths
        .map(parseIntroPath)
        .toList(growable: false);
    final width = size.width * AzamanIntro.markStartWidth;
    if (width <= 0) return;
    final scale = width / kMarkBox;
    canvas.save();
    canvas.translate((size.width - width) / 2, (size.height - width) / 2);
    canvas.scale(scale);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, kMarkBox),
        kMarkSilver,
        const <double>[0, 0.18, 0.42, 0.62, 0.80, 1],
      );
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkHoldPainter oldDelegate) => false;
}
