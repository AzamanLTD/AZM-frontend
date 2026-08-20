import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/scale_tap.dart';

// =============================================================================
// CATEGORY SPEED DIAL — pill-chip category picker with liquid goo animation
//
// Shows ONLY the current category as a single pill chip ("Category" label
// above it). When tapped, other categories expand outward in a horizontal
// flow using the same goo metaball effect — but each satellite is a PILL
// (rounded rect with icon + label), matching the trigger chip's shape.
//
// The goo melts the trigger into the first satellite, then each satellite
// peels away and settles as a crisp pill. Tap-away or selecting a category
// closes the dial and returns to the selected chip.
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

// ---- Spring curves (same family as LiquidMenuButton) ----

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

// ---- Goo constants ----
const double _gooBlurActive = 7.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;

// ---- Pill dimensions ----
const double _pillHeight = 32.0;
const double _pillHPad = 10.0;
const double _pillGap = 6.0;
const double _pillRadius = 16.0;
const double _pillIconSize = 14.0;
const double _pillLabelFS = 11.0;
const double _restScale = 0.14;

/// Estimate pill width from label text.
double _pillWidth(String label) {
  return _pillIconSize + 6 + label.length * _pillLabelFS * 0.52 + _pillHPad * 2;
}

class _SatGeom {
  final CategoryDialItem item;
  final double dx;
  final double dy;
  final double width;

  const _SatGeom({
    required this.item,
    required this.dx,
    required this.dy,
    required this.width,
  });
}

/// Lays out satellite pills in a single horizontal row extending to the
/// right of the trigger chip. Wraps to a second row if overflow.
List<_SatGeom> _layoutSatellites(
  List<CategoryDialItem> items, {
  required double anchorRightEdge,
  required double screenWidth,
}) {
  final n = items.length;
  if (n == 0) return const [];

  final geoms = <_SatGeom>[];
  const margin = 16.0;
  final maxRight = screenWidth - margin;

  // Start pills close to the right edge of the trigger button
  double currentX = anchorRightEdge + _pillGap;
  double currentY = 0.0;
  final rowHeight = _pillHeight + 4.0;

  for (int i = 0; i < n; i++) {
    final w = _pillWidth(items[i].label);
    if (currentX + w > maxRight && i > 0) {
      // Wrap to next row, aligned with trigger left edge
      currentX = anchorRightEdge - w - _pillGap;
      currentY += rowHeight;
    }
    geoms.add(_SatGeom(
      item: items[i],
      dx: currentX + w / 2,
      dy: currentY,
      width: w,
    ));
    currentX += w + _pillGap;
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
      duration: const Duration(milliseconds: 720),
      reverseDuration: const Duration(milliseconds: 480),
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
        satellites: _layoutSatellites(
          satellites,
          anchorRightEdge: anchorPos.dx + anchorSize.width,
          screenWidth: screenSize.width,
        ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        ScaleTap(
          key: _anchorKey,
          onTap: _toggle,
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
                  turns: _isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Overlay
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
        // Dim scrim — tap to close
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
              child: Container(color: Colors.black.withValues(alpha: 0.15)),
            ),
          ),
        ),
        // Goo canvas
        Positioned.fill(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = controller.value;
              final settleFade = (1.0 - ((t - 0.82) / 0.18).clamp(0.0, 1.0));
              if (settleFade <= 0.001) return const SizedBox.shrink();
              return IgnorePointer(
                child: Opacity(
                  opacity: settleFade,
                  child: CustomPaint(
                    painter: _GooPainter(
                      progress: t,
                      satellites: satellites,
                      triggerCenter: triggerCenter,
                      triggerSize: anchorSize.width,
                      triggerHeight: anchorSize.height,
                      surfaceColor: colors.card,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Satellite pills
        ...satellites.asMap().entries.map((entry) {
          final i = entry.key;
          final sat = entry.value;
          return _SatellitePill(
            controller: controller,
            index: i,
            total: satellites.length,
            satellite: sat,
            triggerCenter: triggerCenter,
            colors: colors,
            onTap: () => onTap(sat.item.wire),
          );
        }),
        // Trigger pill (crisp copy during animation)
        Positioned(
          left: anchorPos.dx,
          top: anchorPos.dy,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = controller.value;
              final triggerOpacity = t < 0.85 ? 1.0 : (1.0 - (t - 0.85) / 0.15).clamp(0.0, 1.0);
              final triggerScale = t < 0.22
                  ? 1.0 + 0.12 * (t / 0.22)
                  : _HouseSpringCurve().transform(((t - 0.22) / 0.78).clamp(0.0, 1.0));

              return Opacity(
                opacity: triggerOpacity,
                child: Transform.scale(
                  scale: triggerScale,
                  child: _TriggerPill(
                    colors: colors,
                    size: anchorSize,
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
// Goo Painter
// =============================================================================

class _GooPainter extends CustomPainter {
  final double progress;
  final List<_SatGeom> satellites;
  final Offset triggerCenter;
  final double triggerSize;
  final double triggerHeight;
  final Color surfaceColor;

  _GooPainter({
    required this.progress,
    required this.satellites,
    required this.triggerCenter,
    required this.triggerSize,
    required this.triggerHeight,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final t = progress;
    if (t <= 0.001) return;

    final activeAmount = math.min(t * 4, 1.0);
    final blurSigma = _gooBlurActive * activeAmount + _gooBlurRest * (1 - activeAmount);
    final threshold = _gooThresholdOuter * activeAmount;

    final thresholdMatrix = <double>[
      1.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 30.0, threshold,
    ];

    double minX = triggerCenter.dx - triggerSize;
    double maxX = triggerCenter.dx + triggerSize;
    double minY = triggerCenter.dy - triggerHeight;
    double maxY = triggerCenter.dy + triggerHeight;
    for (final s in satellites) {
      final cx = triggerCenter.dx + s.dx;
      final cy = triggerCenter.dy + s.dy;
      minX = math.min(minX, cx - s.width);
      maxX = math.max(maxX, cx + s.width);
      minY = math.min(minY, cy - _pillHeight);
      maxY = math.max(maxY, cy + _pillHeight);
    }
    final bounds = Rect.fromLTRB(minX - 40, minY - 40, maxX + 40, maxY + 40);

    canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(thresholdMatrix));

    final fillPaint = Paint()
      ..color = surfaceColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..isAntiAlias = true;

    // Trigger pill
    final triggerScale = t < 0.25
        ? 1.0 + 0.12 * (t / 0.25)
        : _HouseSpringCurve().transform(((t - 0.25) / 0.75).clamp(0.0, 1.0));
    final trW = triggerSize * triggerScale;
    final trH = triggerHeight * triggerScale;
    final triggerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: triggerCenter, width: trW, height: trH),
      Radius.circular(trH / 2),
    );
    canvas.drawRRect(triggerRect, fillPaint);

    // Satellite pills
    for (int i = 0; i < satellites.length; i++) {
      final sat = satellites[i];
      final at = 0.03 + i * 0.045;
      final localT = ((t - at) / 0.5).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      double scale;
      if (localT < 0.32) {
        scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
      } else {
        scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
      }

      final cx = triggerCenter.dx + sat.dx;
      final cy = triggerCenter.dy + sat.dy;
      final pw = sat.width * scale;
      final ph = _pillHeight * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph),
          Radius.circular(ph / 2),
        ),
        fillPaint,
      );
    }

    canvas.restore();

    // Border strokes
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    canvas.drawRRect(triggerRect, borderPaint);

    for (int i = 0; i < satellites.length; i++) {
      final sat = satellites[i];
      final at = 0.03 + i * 0.045;
      final localT = ((t - at) / 0.5).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      double scale;
      if (localT < 0.32) {
        scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
      } else {
        scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
      }

      if (scale < 0.15) continue;
      final cx = triggerCenter.dx + sat.dx;
      final cy = triggerCenter.dy + sat.dy;
      final pw = sat.width * scale;
      final ph = _pillHeight * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph),
          Radius.circular(ph / 2),
        ),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GooPainter old) => old.progress != progress;
}

// =============================================================================
// Trigger pill (overlay copy)
// =============================================================================

class _TriggerPill extends StatelessWidget {
  final AzamanColors colors;
  final Size size;

  const _TriggerPill({required this.colors, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Satellite pill
// =============================================================================

class _SatellitePill extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final int total;
  final _SatGeom satellite;
  final Offset triggerCenter;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SatellitePill({
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
    const animDuration = 0.5;
    final start = at;
    final end = at + animDuration;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final localT = ((t - start) / (end - start)).clamp(0.0, 1.0);
        if (localT <= 0.0) return const SizedBox.shrink();

        double scale;
        if (localT < 0.32) {
          scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
        } else {
          scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
        }

        final iconOpacity = localT < 0.36 ? 0.0 : ((localT - 0.36) / 0.15).clamp(0.0, 1.0);

        final cx = triggerCenter.dx + satellite.dx;
        final cy = triggerCenter.dy + satellite.dy;

        return Positioned(
          left: cx - satellite.width / 2,
          top: cy - _pillHeight / 2,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: iconOpacity,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: _pillHeight,
                  padding: const EdgeInsets.symmetric(horizontal: _pillHPad),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(_pillRadius),
                    border: Border.all(color: colors.divider, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(satellite.item.icon, size: _pillIconSize, color: colors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        satellite.item.label,
                        style: TextStyle(
                          fontSize: _pillLabelFS,
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
