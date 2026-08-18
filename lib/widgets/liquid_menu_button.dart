import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// LIQUID MENU BUTTON — gooey speed-dial attachment menu
//
// Inspired by arknow91/liquid-taffy (React + GSAP + SVG goo filter).
// Flutter port: CustomPainter with MaskFilter.blur + ColorFilter.matrix
// alpha-threshold creates the metaball "goo" effect. Spring curves with
// overshoot replicate the GSAP CustomEase springs. Two-phase open: ooze
// (slow bulge) then launch (pop spring past full size). Satellite items
// swing upright from a resting tilt. Plus icon rotates 135° → ×.
// =============================================================================

// ---- Spring curves (replicate GSAP CustomEase from liquid-taffy springs.ts) ----

/// House spring: ζ=0.434, ω=22.46 — 22% overshoot, ring, settle.
/// Used for the trigger button scale-back and icon rotation.
class _HouseSpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    // Damped sinusoidal approximation matching the sampled points
    final w = 22.46;
    final z = 0.434;
    final d = z * w;
    final envelope = 1.0 - math.exp(-d * t);
    final oscillation = math.cos(w * math.sqrt(1 - z * z) * t);
    return 1.0 - envelope * oscillation;
  }
}

/// Pop spring: ζ=0.479, ω=18.09 — 18% overshoot, carries each drop's leap.
/// Used for satellite scale and rotation.
class _PopSpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    final w = 18.09;
    final z = 0.479;
    final d = z * w;
    final envelope = 1.0 - math.exp(-d * t);
    final oscillation = math.cos(w * math.sqrt(1 - z * z) * t);
    return 1.0 - envelope * oscillation;
  }
}

/// Anticipate curve: wind up ~10% the wrong way before collapsing.
class _AnticipateCurve extends Curve {
  @override
  double transformInternal(double t) {
    // Anticipatory ease: slight overshoot in the negative direction
    // then strong settle. Matches cubic-bezier(0.36, 0, 0.66, -0.56) approx.
    if (t < 0.3) return -0.1 * (1 - (t / 0.3) * (t / 0.3));
    final t2 = (t - 0.3) / 0.7;
    return -0.1 + 1.1 * (t2 * t2 * (3 - 2 * t2));
  }
}

// ---- Goo filter constants ----

/// Blur sigma when the goo is active (during open/close flight).
const double _gooBlurActive = 7.0;

/// Blur sigma at rest (small, for soft antialiasing edges).
const double _gooBlurRest = 1.0;

/// Alpha threshold offset — values from liquid-taffy goo.ts (σ=7).
/// Matrix: 0 0 0 30 offset  →  alpha = clamp(alpha * 30 + offset, 0, 1)
/// Outer rim threshold.
const double _gooThresholdOuter = -11.6925;
/// Inner threshold (for the inner edge).
const double _gooThresholdInner = -13.245;

// ---- Satellite layout ----

class _SatelliteConfig {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double dx; // offset from trigger center
  final double dy; // offset from trigger center (negative = up)
  final double restRotation; // degrees, leans toward flight direction

  const _SatelliteConfig({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.dx,
    required this.dy,
    required this.restRotation,
  });
}

const double _buttonSize = 40.0;
const double _satelliteSize = 42.0;
const double _restScale = 0.14; // shrunk satellites hide inside the trigger

// =============================================================================
// Widget
// =============================================================================

class LiquidMenuButton extends StatefulWidget {
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onStickerTap;
  final VoidCallback? onTransferTap;
  final VoidCallback? onEscrowTap;

  const LiquidMenuButton({
    super.key,
    this.onImageTap,
    this.onDocumentTap,
    this.onStickerTap,
    this.onTransferTap,
    this.onEscrowTap,
  });

  @override
  State<LiquidMenuButton> createState() => _LiquidMenuButtonState();
}

class _LiquidMenuButtonState extends State<LiquidMenuButton>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  final GlobalKey _anchorKey = GlobalKey();

  // Satellite animation values (0..1 for each satellite)
  // We drive everything from one AnimationController + Intervals.

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      reverseDuration: const Duration(milliseconds: 550),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  List<_SatelliteConfig> _buildSatellites() {
    final items = <_SatelliteConfig>[];
    // Fan layout: one straight up, two flanking at ~45°.
    // For 5 items: spread them in a fan from left to right.
    final configs = [
      (Icons.image_outlined, 'Image', widget.onImageTap, -64.0, -24.0, -14.0),
      (Icons.folder_outlined, 'Document', widget.onDocumentTap, -36.0, -56.0, -5.0),
      (Icons.emoji_emotions_outlined, 'Sticker', widget.onStickerTap, 0.0, -68.0, 0.0),
      (Icons.compare_arrows_rounded, 'Transfer', widget.onTransferTap, 36.0, -56.0, 5.0),
      (Icons.receipt_long_rounded, 'Ticket', widget.onEscrowTap, 64.0, -24.0, 14.0),
    ];
    for (final c in configs) {
      if (c.$3 != null) {
        items.add(_SatelliteConfig(
          icon: c.$1,
          label: c.$2,
          onTap: c.$3!,
          dx: c.$4,
          dy: c.$5,
          restRotation: c.$6,
        ));
      }
    }
    return items;
  }

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final satellites = _buildSatellites();
    if (satellites.isEmpty) return;

    final colors = Theme.of(context).extension<AzamanColors>()!;
    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPos = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (context) => _LiquidOverlay(
        controller: _controller,
        satellites: satellites,
        colors: colors,
        anchorPos: anchorPos,
        anchorSize: anchorSize,
        screenHeight: screenHeight,
        screenWidth: screenWidth,
        onClose: _close,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _controller.forward(from: 0);
  }

  void _close() {
    if (!_isOpen) return;
    _controller.reverse().whenComplete(_removeOverlay);
    setState(() => _isOpen = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AzamanColors>()!;
    return GestureDetector(
      key: _anchorKey,
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Plus rotates 135° to become ×, on the house spring
          // Trigger swells to 1.16 then settles to 1.0
          final triggerScale = _controller.value < 0.25
              ? 1.0 + 0.16 * (_controller.value / 0.25)
              : _HouseSpringCurve().transform((_controller.value - 0.25) / 0.75);

          return Transform.scale(
            scale: triggerScale,
            child: Transform.rotate(
              angle: _isOpen ? 135.0 * math.pi / 180.0 : 0.0,
              child: Container(
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  border: Border.all(color: colors.accent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6.25,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add,
                  color: colors.accent,
                  size: 20,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Overlay — the goo canvas + satellite buttons
// =============================================================================

class _LiquidOverlay extends StatelessWidget {
  final AnimationController controller;
  final List<_SatelliteConfig> satellites;
  final AzamanColors colors;
  final Offset anchorPos;
  final Size anchorSize;
  final double screenHeight;
  final double screenWidth;
  final VoidCallback onClose;

  const _LiquidOverlay({
    required this.controller,
    required this.satellites,
    required this.colors,
    required this.anchorPos,
    required this.anchorSize,
    required this.screenHeight,
    required this.screenWidth,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final triggerCenter = Offset(
      anchorPos.dx + anchorSize.width / 2,
      anchorPos.dy + anchorSize.height / 2,
    );

    return Stack(
      children: [
        // Full-screen scrim
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: FadeTransition(
              opacity: Tween(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: controller,
                  curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
                ),
              ),
              child: Container(color: Colors.black.withValues(alpha: 0.16)),
            ),
          ),
        ),

        // Goo canvas layer — the metaball effect
        Positioned.fill(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _GooPainter(
                  controller: controller,
                  satellites: satellites,
                  triggerCenter: triggerCenter,
                  surfaceColor: colors.surface,
                  accentColor: colors.accent,
                ),
              );
            },
          ),
        ),

        // Satellite hit areas + icons (above the goo)
        ...satellites.asMap().entries.map((entry) {
          final i = entry.key;
          final sat = entry.value;
          return _SatelliteWidget(
            controller: controller,
            index: i,
            total: satellites.length,
            satellite: sat,
            triggerCenter: triggerCenter,
            colors: colors,
            onTap: () {
              onClose();
              sat.onTap();
            },
          );
        }),

        // Re-render the trigger button on top of the goo
        Positioned(
          left: anchorPos.dx,
          top: anchorPos.dy,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final triggerScale = controller.value < 0.25
                  ? 1.0 + 0.16 * (controller.value / 0.25)
                  : _HouseSpringCurve()
                      .transform((controller.value - 0.25) / 0.75);
              final iconRotation = _isOpen(controller)
                  ? _HouseSpringCurve().transform(controller.value) * 135.0
                  : 0.0;
              return Transform.scale(
                scale: triggerScale,
                child: Transform.rotate(
                  angle: iconRotation * math.pi / 180.0,
                  child: Container(
                    width: anchorSize.width,
                    height: anchorSize.height,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface,
                      border: Border.all(color: colors.accent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6.25,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(Icons.close, color: colors.accent, size: 20),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isOpen(Animation<double> anim) => anim.value > 0.01;
}

// =============================================================================
// Goo Painter — the metaball liquid effect
// =============================================================================

class _GooPainter extends CustomPainter {
  final AnimationController controller;
  final List<_SatelliteConfig> satellites;
  final Offset triggerCenter;
  final Color surfaceColor;
  final Color accentColor;

  _GooPainter({
    required this.controller,
    required this.satellites,
    required this.triggerCenter,
    required this.surfaceColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final t = controller.value;
    if (t < 0.001 && t > -0.001) return; // nothing to draw at rest

    // Compute current satellite positions and scales
    final circles = <_Circle>[];

    // Trigger circle
    final triggerScale = t < 0.25
        ? 1.0 + 0.16 * (t / 0.25)
        : _HouseSpringCurve().transform((t - 0.25) / 0.75);
    circles.add(_Circle(
      center: triggerCenter,
      radius: (_buttonSize / 2) * triggerScale,
    ));

    // Satellite circles
    for (int i = 0; i < satellites.length; i++) {
      final sat = satellites[i];
      final at = 0.03 + i * 0.045;
      final localT = ((t - at) / 0.5).clamp(0.0, 1.0);

      // Two-phase: ooze (0..0.16) then launch (0.16..0.5)
      double scale;
      double rotation;

      if (localT < 0.32) {
        // Ooze phase — slow bulge to 0.42
        final oozeT = localT / 0.32;
        scale = _restScale + (0.42 - _restScale) * oozeT;
        rotation = sat.restRotation * (1 - oozeT * 0.5);
      } else {
        // Launch phase — pop spring past full size
        final launchT = (localT - 0.32) / 0.68;
        final pop = _PopSpringCurve().transform(launchT);
        scale = 0.42 + (1.0 - 0.42) * pop;
        rotation = sat.restRotation * 0.5 * (1 - pop);
      }

      final rad = rotation * math.pi / 180.0;
      final dx = sat.dx * math.cos(rad) - sat.dy * math.sin(rad);
      final dy = sat.dx * math.sin(rad) + sat.dy * math.cos(rad);

      circles.add(_Circle(
        center: Offset(
          triggerCenter.dx + dx,
          triggerCenter.dy + dy,
        ),
        radius: (_satelliteSize / 2) * scale,
      ));
    }

    // Draw with goo effect: blur + alpha threshold
    final blurSigma = _gooBlurActive * math.min(t * 4, 1.0) +
        _gooBlurRest * (1 - math.min(t * 4, 1.0));

    // Save layer with alpha threshold color filter
    final threshold = _gooThresholdOuter * math.min(t * 4, 1.0) + 0 * (1 - math.min(t * 4, 1.0));
    final thresholdMatrix = [
      1.0, 0.0, 0.0, 0.0, 0.0, // R identity
      0.0, 1.0, 0.0, 0.0, 0.0, // G identity
      0.0, 0.0, 1.0, 0.0, 0.0, // B identity
      0.0, 0.0, 0.0, 30.0, threshold, // alpha threshold
    ];

    final bounds = Rect.fromCenter(
      center: triggerCenter,
      width: 400,
      height: 400,
    );

    canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(thresholdMatrix));

    // Draw all circles with blur
    final circlePaint = Paint()
      ..color = surfaceColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..isAntiAlias = true;

    for (final c in circles) {
      if (c.radius > 0.5) {
        canvas.drawCircle(c.center, c.radius, circlePaint);
      }
    }

    canvas.restore();

    // Draw borders on top (crisp circles)
    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    for (final c in circles) {
      if (c.radius > 2.0) {
        canvas.drawCircle(c.center, c.radius, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GooPainter old) {
    return old.controller.value != controller.value ||
        old.satellites != satellites;
  }
}

class _Circle {
  final Offset center;
  final double radius;
  _Circle({required this.center, required this.radius});
}

// =============================================================================
// Satellite widget — icon + label chip above the goo
// =============================================================================

class _SatelliteWidget extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final int total;
  final _SatelliteConfig satellite;
  final Offset triggerCenter;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SatelliteWidget({
    required this.controller,
    required this.index,
    required this.total,
    required this.satellite,
    required this.triggerCenter,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Each satellite fires at: at = 0.03 + index * 0.045
    // Ooze: 0..0.16 of local, Launch: 0.16..0.5
    final at = 0.03 + index * 0.045;
    final totalDuration = 0.5;
    final start = at;
    final end = at + totalDuration;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final localT = ((t - start) / (end - start)).clamp(0.0, 1.0);

        if (localT <= 0.0) return const SizedBox.shrink();

        // Compute scale and rotation (mirror the goo painter)
        double scale;
        double rotation;

        if (localT < 0.32) {
          final oozeT = localT / 0.32;
          scale = _restScale + (0.42 - _restScale) * oozeT;
          rotation = satellite.restRotation * (1 - oozeT * 0.5);
        } else {
          final launchT = (localT - 0.32) / 0.68;
          final pop = _PopSpringCurve().transform(launchT);
          scale = 0.42 + (1.0 - 0.42) * pop;
          rotation = satellite.restRotation * 0.5 * (1 - pop);
        }

        // Fade in icons during the launch
        final iconOpacity = localT < 0.36
            ? 0.0
            : ((localT - 0.36) / 0.15).clamp(0.0, 1.0);

        // Position
        final rad = rotation * math.pi / 180.0;
        final dx = satellite.dx * math.cos(rad) - satellite.dy * math.sin(rad);
        final dy = satellite.dx * math.sin(rad) + satellite.dy * math.cos(rad);

        final satCenter = Offset(
          triggerCenter.dx + dx,
          triggerCenter.dy + dy,
        );

        // Squash and stretch: height leads, width lags during launch
        double scaleX = scale;
        double scaleY = scale;
        if (localT >= 0.32) {
          final launchT = (localT - 0.32) / 0.68;
          final pop = _PopSpringCurve().transform(launchT);
          // Width lags height by ~40ms (≈0.06 in normalized time)
          final popLagged = _PopSpringCurve()
              .transform((launchT - 0.06).clamp(0.0, 1.0));
          scaleY = 0.42 + (1.0 - 0.42) * pop;
          scaleX = 0.42 + (1.0 - 0.42) * popLagged;
        }

        // Label position: left sats → label on left, right sats → label on right
        final isLeft = satellite.dx < -10;
        final isCenter = satellite.dx.abs() <= 10;

        return Positioned(
          left: satCenter.dx - (isLeft ? 90 : _satelliteSize / 2),
          top: satCenter.dy - _satelliteSize / 2,
          child: SizedBox(
            width: isCenter ? 200.0 : 110.0,
            height: _satelliteSize,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: Opacity(
                opacity: iconOpacity,
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: isLeft
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (isLeft) _labelChip(satellite.label, colors),
                      if (isLeft) const SizedBox(width: 8),
                      Container(
                        width: _satelliteSize,
                        height: _satelliteSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surface.withValues(alpha: 0.95),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(satellite.icon, color: colors.accent, size: 19),
                      ),
                      if (!isLeft) const SizedBox(width: 8),
                      if (!isLeft) _labelChip(satellite.label, colors),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _labelChip(String label, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }

}
