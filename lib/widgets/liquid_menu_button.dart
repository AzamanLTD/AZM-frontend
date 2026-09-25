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
//
// Generic item list — any chat surface can pass 1-5 LiquidMenuItems and
// get the same trigger + fan + goo behavior. All colors (trigger, satellites,
// labels) use NEUTRAL dark/card/text colors — never the gold brand accent.
// =============================================================================

/// One entry in the liquid speed-dial fan.
class LiquidMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const LiquidMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

// ---- Spring curves (replicate GSAP CustomEase from liquid-taffy springs.ts) ----

/// House spring: ζ=0.434, ω=22.46 — 22% overshoot, ring, settle.
/// Used for the trigger button scale-back and icon rotation.
class _HouseSpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    const w = 22.46;
    const z = 0.434;
    const d = z * w;
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
    const w = 18.09;
    const z = 0.479;
    const d = z * w;
    final envelope = 1.0 - math.exp(-d * t);
    final oscillation = math.cos(w * math.sqrt(1 - z * z) * t);
    return 1.0 - envelope * oscillation;
  }
}

// ---- Goo filter constants ----

const double _gooBlurActive = 7.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;

// ---- Layout ----

const double _buttonSize = 40.0;
const double _satelliteSize = 44.0;
const double _restScale = 0.14;

class _SatelliteGeom {
  final LiquidMenuItem item;
  final double dx;
  final double dy;
  final double restRotation;

  const _SatelliteGeom({
    required this.item,
    required this.dx,
    required this.dy,
    required this.restRotation,
  });
}

List<_SatelliteGeom> _layoutSatellites(List<LiquidMenuItem> items) {
  final n = items.length;
  if (n == 0) return const [];
  const double fanSpanDeg = 120.0;
  const double radius = 70.0;
  final geoms = <_SatelliteGeom>[];
  for (int i = 0; i < n; i++) {
    final t = n == 1 ? 0.5 : i / (n - 1);
    final angleDeg = -90.0 + (-fanSpanDeg / 2 + fanSpanDeg * t);
    final rad = angleDeg * math.pi / 180.0;
    final dx = radius * math.cos(rad);
    final dy = radius * math.sin(rad);
    final restRotation = (t - 0.5) * 28.0;
    geoms.add(_SatelliteGeom(item: items[i], dx: dx, dy: dy, restRotation: restRotation));
  }
  return geoms;
}

// =============================================================================
// Widget
// =============================================================================

class LiquidMenuButton extends StatefulWidget {
  final List<LiquidMenuItem> items;
  final AzamanColors colors;
  final double size;

  const LiquidMenuButton({
    super.key,
    required this.items,
    required this.colors,
    this.size = _buttonSize,
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

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (widget.items.isEmpty) return;

    final colors = widget.colors;
    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPos = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (context) => _LiquidOverlay(
        controller: _controller,
        satellites: _layoutSatellites(widget.items),
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
    final colors = widget.colors;
    return GestureDetector(
      key: _anchorKey,
      onTap: _toggle,
      child: Opacity(
        opacity: _isOpen ? 0.0 : 1.0,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface,
            border: Border.all(color: colors.textPrimary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6.25,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(Icons.add, color: colors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

// =============================================================================
// Overlay — the goo canvas + satellite buttons + re-rendered trigger
// =============================================================================

class _LiquidOverlay extends StatelessWidget {
  final AnimationController controller;
  final List<_SatelliteGeom> satellites;
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
              child: Container(color: Colors.black.withValues(alpha: 0.18)),
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _GooPainter(
                  progress: controller.value,
                  satellites: satellites,
                  triggerCenter: triggerCenter,
                  triggerSize: anchorSize.width,
                  surfaceColor: colors.card,
                ),
              );
            },
          ),
        ),
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
              sat.item.onTap();
            },
          );
        }),
        Positioned(
          left: anchorPos.dx,
          top: anchorPos.dy,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = controller.value;
              final triggerScale = t < 0.25
                  ? 1.0 + 0.16 * (t / 0.25)
                  : _HouseSpringCurve().transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
              final iconRotation = _HouseSpringCurve().transform(t.clamp(0.0, 1.0)) * 135.0;
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
                      border: Border.all(color: colors.textPrimary, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6.25,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(Icons.add, color: colors.textPrimary, size: 20),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Goo Painter — the metaball liquid effect
// =============================================================================

class _GooPainter extends CustomPainter {
  final double progress;
  final List<_SatelliteGeom> satellites;
  final Offset triggerCenter;
  final double triggerSize;
  final Color surfaceColor;

  _GooPainter({
    required this.progress,
    required this.satellites,
    required this.triggerCenter,
    required this.triggerSize,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final t = progress;
    if (t <= 0.001) return;

    final circles = <_Circle>[];

    final triggerScale = t < 0.25
        ? 1.0 + 0.16 * (t / 0.25)
        : _HouseSpringCurve().transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
    circles.add(_Circle(center: triggerCenter, radius: (triggerSize / 2) * triggerScale));

    for (int i = 0; i < satellites.length; i++) {
      final sat = satellites[i];
      final at = 0.03 + i * 0.045;
      final localT = ((t - at) / 0.5).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      double scale;
      if (localT < 0.32) {
        final oozeT = localT / 0.32;
        scale = _restScale + (0.42 - _restScale) * oozeT;
      } else {
        final launchT = (localT - 0.32) / 0.68;
        final pop = _PopSpringCurve().transform(launchT);
        scale = 0.42 + (1.0 - 0.42) * pop;
      }

      circles.add(_Circle(
        center: Offset(triggerCenter.dx + sat.dx, triggerCenter.dy + sat.dy),
        radius: (_satelliteSize / 2) * scale,
      ));
    }

    final activeAmount = math.min(t * 4, 1.0);
    final blurSigma = _gooBlurActive * activeAmount + _gooBlurRest * (1 - activeAmount);
    final threshold = _gooThresholdOuter * activeAmount;

    final thresholdMatrix = <double>[
      1.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 30.0, threshold,
    ];

    final bounds = Rect.fromCenter(center: triggerCenter, width: 420, height: 420);

    canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(thresholdMatrix));

    final circlePaint = Paint()
      ..color = surfaceColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..isAntiAlias = true;

    for (final c in circles) {
      if (c.radius > 0.5) canvas.drawCircle(c.center, c.radius, circlePaint);
    }

    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    for (final c in circles) {
      if (c.radius > 2.0) canvas.drawCircle(c.center, c.radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GooPainter old) => old.progress != progress;
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
  final _SatelliteGeom satellite;
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
    final at = 0.03 + index * 0.045;
    const totalDuration = 0.5;
    final start = at;
    final end = at + totalDuration;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final localT = ((t - start) / (end - start)).clamp(0.0, 1.0);
        if (localT <= 0.0) return const SizedBox.shrink();

        double scaleX;
        double scaleY;
        if (localT < 0.32) {
          final oozeT = localT / 0.32;
          final s = _restScale + (0.42 - _restScale) * oozeT;
          scaleX = s;
          scaleY = s;
        } else {
          final launchT = (localT - 0.32) / 0.68;
          final pop = _PopSpringCurve().transform(launchT);
          final popLagged = _PopSpringCurve().transform((launchT - 0.06).clamp(0.0, 1.0));
          scaleY = 0.42 + (1.0 - 0.42) * pop;
          scaleX = 0.42 + (1.0 - 0.42) * popLagged;
        }

        final iconOpacity = localT < 0.36 ? 0.0 : ((localT - 0.36) / 0.15).clamp(0.0, 1.0);

        final satCenter = Offset(
          triggerCenter.dx + satellite.dx,
          triggerCenter.dy + satellite.dy,
        );

        final isLeft = satellite.dx < -8;
        final isRight = satellite.dx > 8;

        return Positioned(
          left: satCenter.dx - (isLeft ? 96 : (isRight ? _satelliteSize / 2 : 55)),
          top: satCenter.dy - _satelliteSize / 2,
          child: SizedBox(
            width: isLeft || isRight ? 118 : 110,
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
                    mainAxisAlignment:
                        isLeft ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (isLeft) ...[
                        _labelChip(satellite.item.label, colors),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        width: _satelliteSize,
                        height: _satelliteSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.card,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(satellite.item.icon, color: colors.textPrimary, size: 20),
                      ),
                      if (!isLeft) ...[
                        const SizedBox(width: 8),
                        _labelChip(satellite.item.label, colors),
                      ],
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
        color: colors.surface.withValues(alpha: 0.95),
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
