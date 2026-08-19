import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/scale_tap.dart';

// =============================================================================
// CATEGORY SPEED DIAL — compact category picker using liquid-taffy speed-dial
//
// Shows ONLY the current category as a single chip with "Category" label
// above it. When tapped, other categories fan out in a radial arc using
// the same goo metaball effect as the chat liquid menu. The arc opens
// UPWARD so it doesn't cover the results below.
//
// Designed to be a drop-in replacement for the old horizontal _categoryStrip()
// in marketplace_home_screen — same callback contract, same category model.
// =============================================================================

/// One category entry for the speed dial.
class CategoryDialItem {
  final String? wire;
  final IconData icon;
  final String label;

  const CategoryDialItem({
    this.wire,
    required this.icon,
    required this.label,
  });
}

// ---- Spring curves (same as LiquidMenuButton) ----

class _HouseSpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    const w = 22.46;
    const z = 0.434;
    final d = z * w;
    final envelope = 1.0 - math.exp(-d * t);
    final oscillation = math.cos(w * math.sqrt(1 - z * z) * t);
    return 1.0 - envelope * oscillation;
  }
}

class _PopSpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    const w = 18.09;
    const z = 0.479;
    final d = z * w;
    final envelope = 1.0 - math.exp(-d * t);
    final oscillation = math.cos(w * math.sqrt(1 - z * z) * t);
    return 1.0 - envelope * oscillation;
  }
}

// ---- Goo constants ----
const double _gooBlurActive = 7.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;

// ---- Layout ----
const double _satelliteSize = 48.0;
const double _restScale = 0.14;

class _SatGeom {
  final CategoryDialItem item;
  final double dx;
  final double dy;
  final double restRotation;

  const _SatGeom({
    required this.item,
    required this.dx,
    required this.dy,
    required this.restRotation,
  });
}

/// Lays out satellites in a fan arc ABOVE the trigger button.
/// The fan spans 120° centered at -90° (straight up).
List<_SatGeom> _layoutSatellites(List<CategoryDialItem> items) {
  final n = items.length;
  if (n == 0) return const [];
  const double fanSpanDeg = 120.0;
  const double radius = 80.0;
  final geoms = <_SatGeom>[];
  for (int i = 0; i < n; i++) {
    final t = n == 1 ? 0.5 : i / (n - 1);
    final angleDeg = -90.0 + (-fanSpanDeg / 2 + fanSpanDeg * t);
    final rad = angleDeg * math.pi / 180.0;
    final dx = radius * math.cos(rad);
    final dy = radius * math.sin(rad);
    final restRotation = (t - 0.5) * 24.0;
    geoms.add(_SatGeom(item: items[i], dx: dx, dy: dy, restRotation: restRotation));
  }
  return geoms;
}

// =============================================================================
// Widget
// =============================================================================

class CategorySpeedDial extends StatefulWidget {
  final List<CategoryDialItem> categories;
  final String? selectedWire;
  final AzamanColors colors;
  final ValueChanged<String?> onSelected;

  const CategorySpeedDial({
    super.key,
    required this.categories,
    required this.selectedWire,
    required this.colors,
    required this.onSelected,
  });

  @override
  State<CategorySpeedDial> createState() => _CategorySpeedDialState();
}

class _CategorySpeedDialState extends State<CategorySpeedDial>
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

  CategoryDialItem get _current {
    if (widget.selectedWire == null) {
      // "All" is always first
      return widget.categories.first;
    }
    return widget.categories.firstWhere(
      (c) => c.wire == widget.selectedWire,
      orElse: () => widget.categories.first,
    );
  }

  void _open() {
    final satellites = widget.categories.where((c) => c.wire != widget.selectedWire).toList();

    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPos = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;

    _overlayEntry = OverlayEntry(
      builder: (context) => _CategoryDialOverlay(
        controller: _controller,
        satellites: _layoutSatellites(satellites),
        colors: widget.colors,
        anchorPos: anchorPos,
        anchorSize: anchorSize,
        screenSize: screenSize,
        safeTop: safeTop,
        onClose: _close,
        onTap: (wire) {
          _close();
          widget.onSelected(wire);
        },
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
    final current = _current;
    final isActive = widget.selectedWire != null;

    return GestureDetector(
      key: _anchorKey,
      onTap: _toggle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Category" label above the chip
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Category',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Current category chip
          ScaleTap(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? colors.accentSurface : colors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive ? colors.accent : colors.divider,
                  width: isActive ? 1.2 : 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? colors.accent.withValues(alpha: 0.18)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: isActive ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(current.icon, size: 18, color: isActive ? colors.accent : colors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    current.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isActive ? colors.accent : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _isOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Overlay — goo canvas + satellite chips + re-rendered trigger
// =============================================================================

class _CategoryDialOverlay extends StatelessWidget {
  final AnimationController controller;
  final List<_SatGeom> satellites;
  final AzamanColors colors;
  final Offset anchorPos;
  final Size anchorSize;
  final Size screenSize;
  final double safeTop;
  final VoidCallback onClose;
  final ValueChanged<String?> onTap;

  const _CategoryDialOverlay({
    required this.controller,
    required this.satellites,
    required this.colors,
    required this.anchorPos,
    required this.anchorSize,
    required this.screenSize,
    required this.safeTop,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final triggerCenter = Offset(
      anchorPos.dx + anchorSize.width / 2,
      anchorPos.dy + anchorSize.height / 2,
    );

    return Stack(
      children: [
        // Scrim
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
              child: Container(color: Colors.black.withValues(alpha: 0.12)),
            ),
          ),
        ),
        // Goo canvas
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
        // Satellite chips
        ...satellites.asMap().entries.map((entry) {
          final i = entry.key;
          final sat = entry.value;
          return _SatelliteChip(
            controller: controller,
            index: i,
            total: satellites.length,
            satellite: sat,
            triggerCenter: triggerCenter,
            colors: colors,
            onTap: () => onTap(sat.item.wire),
          );
        }),
      ],
    );
  }
}

// =============================================================================
// Goo Painter — same metaball effect as LiquidMenuButton
// =============================================================================

class _GooPainter extends CustomPainter {
  final double progress;
  final List<_SatGeom> satellites;
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
// Satellite chip — icon + label, positioned in the fan arc
// =============================================================================

class _SatelliteChip extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final int total;
  final _SatGeom satellite;
  final Offset triggerCenter;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SatelliteChip({
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

        return Positioned(
          left: satCenter.dx - _satelliteSize / 2,
          top: satCenter.dy - _satelliteSize / 2,
          child: Transform.scale(
            scaleX: scaleX,
            scaleY: scaleY,
            child: Opacity(
              opacity: iconOpacity,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(satellite.item.icon, size: 16, color: colors.textPrimary),
                      const SizedBox(height: 1),
                      Text(
                        satellite.item.label,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
}

