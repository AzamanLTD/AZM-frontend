// lib/widgets/money_stage/az_ambient_backdrop.dart
// =============================================================================
// The sky behind every money stage.
//
// Each launcher action (Send, Receive, Add money, Withdraw, Request, Pay,
// Convert, Bills) gets its own hue family, so the stages read as one family
// with different identities. A sky is a base wash plus four soft "clouds":
// one SHADOW cloud darker than the wash, one GLOW brighter than it, and two
// tints. The contrast between shadow and glow is what turns a gradient into a
// sky. Clouds drift slowly on independent Lissajous paths, never compete with
// the amount, and stand still under reduced motion. Purely decorative: the
// sky never carries information.
// =============================================================================

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:azaman/theme/az_motion.dart';

/// Which money action a stage belongs to. Drives the sky's hue family.
enum AzMoneyMood { send, receive, addMoney, withdraw, request, pay, convert, bills }

/// One sky: a base wash and four soft clouds, plus the ink that reads on it.
@immutable
class AzSkyPalette {
  const AzSkyPalette({
    required this.top,
    required this.bottom,
    required this.lights,
    required this.ink,
    required this.inkMuted,
    required this.glass,
  });

  /// Base wash, top to bottom.
  final Color top;
  final Color bottom;

  /// [shadow, glow, tint, tint].
  final List<Color> lights;

  /// Foreground for text and keypad digits on this sky.
  final Color ink;
  final Color inkMuted;

  /// Fill for round chrome buttons and pills that sit on the sky.
  final Color glass;

  static AzSkyPalette of(AzMoneyMood mood, Brightness brightness) =>
      brightness == Brightness.dark ? _dark[mood]! : _light[mood]!;

  static const _lightInk = Color(0xFF15121A);
  static const _lightInkMuted = Color(0x9915121A);
  static const _lightGlass = Color(0x59FFFFFF);
  static const _darkInk = Color(0xFFF7F4FA);
  static const _darkInkMuted = Color(0x99F7F4FA);
  static const _darkGlass = Color(0x1FFFFFFF);

  static const Map<AzMoneyMood, AzSkyPalette> _light = {
    // Dusk: lilac over peach.
    AzMoneyMood.send: AzSkyPalette(
      top: Color(0xFFC6A2D6), bottom: Color(0xFFF1D6C6),
      lights: [Color(0xFF8C6AA6), Color(0xFFFFE6CC), Color(0xFFE9AFC9), Color(0xFFF4BFA0)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Lagoon: money arriving.
    AzMoneyMood.receive: AzSkyPalette(
      top: Color(0xFF9FD3DD), bottom: Color(0xFFE1F1EC),
      lights: [Color(0xFF4F98AA), Color(0xFFF2FBF6), Color(0xFFA9DCF0), Color(0xFFB5E6CC)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Dawn: mint into gold — topping up.
    AzMoneyMood.addMoney: AzSkyPalette(
      top: Color(0xFFB4DEC8), bottom: Color(0xFFF5E6B6),
      lights: [Color(0xFF5FA585), Color(0xFFFFF3CF), Color(0xFFF0CF6E), Color(0xFFC3E2F0)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Harmattan: sand and apricot — cashing out.
    AzMoneyMood.withdraw: AzSkyPalette(
      top: Color(0xFFEDC79A), bottom: Color(0xFFF7E8D8),
      lights: [Color(0xFFB9784F), Color(0xFFFFF1DF), Color(0xFFF4AE7E), Color(0xFFF2D2A2)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Blush: asking someone.
    AzMoneyMood.request: AzSkyPalette(
      top: Color(0xFFEDB3C6), bottom: Color(0xFFF5DEE5),
      lights: [Color(0xFFA9607F), Color(0xFFFFEEF2), Color(0xFFD7C2F0), Color(0xFFF6BFCF)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Periwinkle: paying a place.
    AzMoneyMood.pay: AzSkyPalette(
      top: Color(0xFFB2BDEE), bottom: Color(0xFFE3E8F9),
      lights: [Color(0xFF6672C2), Color(0xFFF4F6FF), Color(0xFFC9B6EE), Color(0xFFBCD3F7)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Citrus over teal: exchange.
    AzMoneyMood.convert: AzSkyPalette(
      top: Color(0xFFADDCD2), bottom: Color(0xFFF6ECC2),
      lights: [Color(0xFF5DA899), Color(0xFFFFF8DF), Color(0xFFF0D46E), Color(0xFFC2E5DD)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
    // Slate and mist: bills, calm and administrative.
    AzMoneyMood.bills: AzSkyPalette(
      top: Color(0xFFBEC9D6), bottom: Color(0xFFECEFF3),
      lights: [Color(0xFF75859B), Color(0xFFF8F9FB), Color(0xFFD6D0E8), Color(0xFFC9D6E4)],
      ink: _lightInk, inkMuted: _lightInkMuted, glass: _lightGlass),
  };

  // Night skies keep each hue but sink the wash to near-black: the shadow
  // cloud becomes the deepest tone and the glow a saturated ember, so a
  // dark-mode stage still knows which action it is without glaring.
  static const Map<AzMoneyMood, AzSkyPalette> _dark = {
    AzMoneyMood.send: AzSkyPalette(
      top: Color(0xFF1A1024), bottom: Color(0xFF09070B),
      lights: [Color(0xFF050307), Color(0xFF6A3E8C), Color(0xFF8C4A64), Color(0xFF9A6046)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.receive: AzSkyPalette(
      top: Color(0xFF0A1C22), bottom: Color(0xFF06090A),
      lights: [Color(0xFF020506), Color(0xFF14707E), Color(0xFF235E8C), Color(0xFF1C7457)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.addMoney: AzSkyPalette(
      top: Color(0xFF0B1C14), bottom: Color(0xFF07090A),
      lights: [Color(0xFF020504), Color(0xFF1E7A52), Color(0xFF8A7322), Color(0xFF1C5A70)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.withdraw: AzSkyPalette(
      top: Color(0xFF21140B), bottom: Color(0xFF0A0706),
      lights: [Color(0xFF060302), Color(0xFF94541F), Color(0xFF7A3A2A), Color(0xFF8C6A2A)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.request: AzSkyPalette(
      top: Color(0xFF210D18), bottom: Color(0xFF0A0609),
      lights: [Color(0xFF060205), Color(0xFF8C2F5C), Color(0xFF55357A), Color(0xFF9A4A5E)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.pay: AzSkyPalette(
      top: Color(0xFF10132B), bottom: Color(0xFF06060C),
      lights: [Color(0xFF030308), Color(0xFF3A4AA6), Color(0xFF5E3A9A), Color(0xFF2A5A8C)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.convert: AzSkyPalette(
      top: Color(0xFF0B1B19), bottom: Color(0xFF070909),
      lights: [Color(0xFF020505), Color(0xFF187467), Color(0xFF8A7322), Color(0xFF3F7A3A)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
    AzMoneyMood.bills: AzSkyPalette(
      top: Color(0xFF12161D), bottom: Color(0xFF08090A),
      lights: [Color(0xFF030405), Color(0xFF3B4A60), Color(0xFF473F66), Color(0xFF34505E)],
      ink: _darkInk, inkMuted: _darkInkMuted, glass: _darkGlass),
  };
}

/// Full-bleed drifting sky. Put content on top in a [Stack].
class AzAmbientBackdrop extends StatefulWidget {
  const AzAmbientBackdrop({
    super.key,
    required this.mood,
    this.brightness,
    this.period = const Duration(seconds: 22),
    this.phase = 0,
  });

  final AzMoneyMood mood;

  /// Defaults to the ambient [Theme] brightness.
  final Brightness? brightness;

  /// One full drift cycle. Long on purpose: the sky should be noticed only
  /// when the user looks for it.
  final Duration period;

  /// Fixed starting phase in [0, 1). Captures and tests pin it.
  final double phase;

  /// Global drift switch. Off under `flutter test` so `pumpAndSettle` on a
  /// money stage settles (the drift is endless by design); a test can turn
  /// it on to exercise the drift itself.
  static bool driftEnabled = !_underFlutterTest;
  static bool get _underFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<AzAmbientBackdrop> createState() => _AzAmbientBackdropState();
}

class _AzAmbientBackdropState extends State<AzAmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: widget.period, value: widget.phase);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final travel = AzMotion.of(context).travel && AzAmbientBackdrop.driftEnabled;
    if (travel && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!travel && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AzSkyPalette.of(
      widget.mood,
      widget.brightness ?? Theme.of(context).brightness,
    );
    // Clipped: the clouds are large soft circles that would otherwise paint
    // past the backdrop's box (visible when a sky is a band, not a page).
    return RepaintBoundary(
      child: ClipRect(
        child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: CustomPaint(
          key: ValueKey(palette),
          painter: _SkyPainter(palette: palette, t: _drift),
          size: Size.infinite,
        ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.palette, required this.t}) : super(repaint: t);

  final AzSkyPalette palette;
  final Animation<double> t;

  // 0 = shadow cloud: right, mid-height, behind the amount's tail.
  // 1 = glow: lower left, where the keypad sits, lifting it.
  // 2, 3 = tints along the top.
  static const _clouds = <_Cloud>[
    _Cloud(x: 0.86, y: 0.50, drift: 0.06, radius: 0.42, stretch: 1.7, tilt: -0.35, strength: 0.85, fx: 1, fy: 2, offset: 0.0),
    _Cloud(x: 0.18, y: 0.80, drift: 0.07, radius: 0.50, stretch: 1.5, tilt: 0.25, strength: 0.95, fx: 2, fy: 1, offset: 0.25),
    _Cloud(x: 0.20, y: 0.12, drift: 0.08, radius: 0.40, stretch: 1.9, tilt: 0.10, strength: 0.70, fx: 1, fy: 3, offset: 0.5),
    _Cloud(x: 0.80, y: 0.06, drift: 0.07, radius: 0.34, stretch: 1.6, tilt: -0.15, strength: 0.60, fx: 3, fy: 2, offset: 0.75),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter, rect.bottomCenter, [palette.top, palette.bottom]),
    );
    final longest = math.max(size.width, size.height);
    final phase = t.value * 2 * math.pi;
    for (var i = 0; i < _clouds.length; i++) {
      final c = _clouds[i];
      final a = phase * c.fx + c.offset * 2 * math.pi;
      final b = phase * c.fy + c.offset * 2 * math.pi;
      final centre = Offset(
        (c.x + c.drift * math.sin(a)) * size.width,
        (c.y + c.drift * 0.6 * math.cos(b)) * size.height,
      );
      final radius = c.radius * longest * (1 + 0.06 * math.sin(a + b));
      final colour = palette.lights[i % palette.lights.length];
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(c.tilt);
      canvas.scale(c.stretch, 1);
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, radius, [
            colour.withValues(alpha: c.strength),
            colour.withValues(alpha: c.strength * 0.45),
            colour.withValues(alpha: 0.0),
          ], const [0.0, 0.45, 1.0]),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.palette != palette || old.t != t;
}

class _Cloud {
  const _Cloud({
    required this.x,
    required this.y,
    required this.drift,
    required this.radius,
    required this.stretch,
    required this.tilt,
    required this.strength,
    required this.fx,
    required this.fy,
    required this.offset,
  });
  final double x, y, drift, radius, stretch, tilt, strength;
  final int fx, fy;
  final double offset;
}
