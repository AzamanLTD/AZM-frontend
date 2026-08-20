import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// LIQUID DROPDOWN MENU — individual pill speed-dial
//
// Each menu item is its own pill that emerges individually from the
// trigger button with a goo/metaball effect. Pills stack vertically
// above the trigger, left-aligned, all the same width and pill shape.
//
// Technique: each pill is drawn as a blurred filled shape on a
// saveLayer with a threshold color matrix. The blur+threshold creates
// the gooey metaball merge between the trigger and the first pill,
// and between consecutive pills. Crisp pills paint on top once settled.
// =============================================================================

/// One row in the anchored dropdown.
class LiquidDropdownItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const LiquidDropdownItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

// ---- Pill dimensions ----
const double _pillHeight = 42.0;
const double _pillWidth = 170.0;
const double _pillHPad = 14.0;
const double _pillGap = 6.0;
const double _pillRadius = 14.0;
const double _pillIconSize = 18.0;
const double _pillLabelFS = 13.0;
const double _triggerGap = 8.0;

// ---- Goo constants ----
const double _gooBlurActive = 7.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;
const double _restScale = 0.14;

// ---- Spring curves ----
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

class LiquidDropdownMenu extends StatefulWidget {
  final List<LiquidDropdownItem> items;
  final AzamanColors colors;
  final double size;

  const LiquidDropdownMenu({
    super.key,
    required this.items,
    required this.colors,
    this.size = 36,
  });

  @override
  State<LiquidDropdownMenu> createState() => _LiquidDropdownMenuState();
}

class _LiquidDropdownMenuState extends State<LiquidDropdownMenu>
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
      reverseDuration: const Duration(milliseconds: 350),
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

    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPos = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;

    _overlayEntry = OverlayEntry(
      builder: (context) => _LiquidDropdownOverlay(
        controller: _controller,
        items: widget.items,
        colors: widget.colors,
        anchorPos: anchorPos,
        anchorSize: anchorSize,
        screenSize: screenSize,
        safeTop: safeTop,
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isOpen
            ? Container(
                key: const ValueKey('open'),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.close, color: colors.textPrimary, size: 18),
              )
            : Container(
                key: const ValueKey('closed'),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  border: Border.all(color: colors.textPrimary, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
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
// Overlay
// =============================================================================

class _PillGeom {
  final LiquidDropdownItem item;
  final Offset center; // center relative to screen
  final int index;

  const _PillGeom({
    required this.item,
    required this.center,
    required this.index,
  });
}

class _LiquidDropdownOverlay extends StatelessWidget {
  final AnimationController controller;
  final List<LiquidDropdownItem> items;
  final AzamanColors colors;
  final Offset anchorPos;
  final Size anchorSize;
  final Size screenSize;
  final double safeTop;
  final VoidCallback onClose;

  const _LiquidDropdownOverlay({
    required this.controller,
    required this.items,
    required this.colors,
    required this.anchorPos,
    required this.anchorSize,
    required this.screenSize,
    required this.safeTop,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final triggerCenter = Offset(
      anchorPos.dx + anchorSize.width / 2,
      anchorPos.dy + anchorSize.height / 2,
    );

    // Pills stack vertically above the trigger, left-aligned with trigger
    // Pill 0 (bottom-most, closest to trigger) is the first item
    // Pill n-1 (top-most) is the last item
    // Bottom pill center Y = anchorPos.dy - _triggerGap - _pillHeight/2
    // Each pill above is shifted by _pillHeight + _pillGap

    final pillLeft = anchorPos.dx;
    final bottomPillCenterY = anchorPos.dy - _triggerGap - _pillHeight / 2;

    final geoms = <_PillGeom>[];
    for (int i = 0; i < items.length; i++) {
      final cy = bottomPillCenterY - i * (_pillHeight + _pillGap);
      final cx = pillLeft + _pillWidth / 2;
      geoms.add(_PillGeom(
        item: items[i],
        center: Offset(cx, cy),
        index: i,
      ));
    }

    // Clamp: if pills go above safe area, shift everything down
    final topPillTop = geoms.last.center.dy - _pillHeight / 2;
    final minTop = safeTop + 12;
    if (topPillTop < minTop) {
      final shift = minTop - topPillTop;
      for (int i = 0; i < geoms.length; i++) {
        geoms[i] = _PillGeom(
          item: geoms[i].item,
          center: Offset(geoms[i].center.dx, geoms[i].center.dy + shift),
          index: geoms[i].index,
        );
      }
    }

    return Stack(
      children: [
        // Dim scrim
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
        // Goo canvas — metaball merge between trigger and pills
        Positioned.fill(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = controller.value;
              final gooFade = (1.0 - ((t - 0.75) / 0.25).clamp(0.0, 1.0));
              if (gooFade <= 0.001) return const SizedBox.shrink();
              return IgnorePointer(
                child: Opacity(
                  opacity: gooFade,
                  child: CustomPaint(
                    painter: _GooPillPainter(
                      progress: t,
                      triggerCenter: triggerCenter,
                      triggerSize: anchorSize.width,
                      pills: geoms,
                      pillWidth: _pillWidth,
                      pillHeight: _pillHeight,
                      pillRadius: _pillRadius,
                      surfaceColor: colors.card,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Crisp pills (fade in as goo settles)
        ...geoms.map((geom) => _CrispPill(
              controller: controller,
              geom: geom,
              colors: colors,
              onClose: onClose,
            )),
        // Trigger copy (crisp during animation)
        Positioned(
          left: anchorPos.dx,
          top: anchorPos.dy,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = controller.value;
              final triggerOpacity = t < 0.5
                  ? 1.0
                  : (1.0 - (t - 0.5) / 0.3).clamp(0.0, 1.0);
              final triggerScale = t < 0.15
                  ? 1.0 + 0.15 * (t / 0.15)
                  : 1.0 + 0.15 * (1.0 - ((t - 0.15) / 0.25).clamp(0.0, 1.0));

              return Opacity(
                opacity: triggerOpacity,
                child: Transform.scale(
                  scale: triggerScale,
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
                          blurRadius: 6,
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
// Goo Pill Painter — metaball merge between trigger and stacked pills
// =============================================================================

class _GooPillPainter extends CustomPainter {
  final double progress;
  final Offset triggerCenter;
  final double triggerSize;
  final List<_PillGeom> pills;
  final double pillWidth;
  final double pillHeight;
  final double pillRadius;
  final Color surfaceColor;

  _GooPillPainter({
    required this.progress,
    required this.triggerCenter,
    required this.triggerSize,
    required this.pills,
    required this.pillWidth,
    required this.pillHeight,
    required this.pillRadius,
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

    // Calculate bounds
    double minX = triggerCenter.dx - triggerSize;
    double maxX = triggerCenter.dx + triggerSize;
    double minY = triggerCenter.dy - triggerSize;
    double maxY = triggerCenter.dy + triggerSize;
    for (final p in pills) {
      minX = math.min(minX, p.center.dx - pillWidth / 2);
      maxX = math.max(maxX, p.center.dx + pillWidth / 2);
      minY = math.min(minY, p.center.dy - pillHeight / 2);
      maxY = math.max(maxY, p.center.dy + pillHeight / 2);
    }
    final bounds = Rect.fromLTRB(minX - 40, minY - 40, maxX + 40, maxY + 40);

    canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(thresholdMatrix));

    final fillPaint = Paint()
      ..color = surfaceColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..isAntiAlias = true;

    // Trigger circle with pulse
    final triggerPulse = t < 0.15
        ? 1.0 + 0.15 * (t / 0.15)
        : 1.0 + 0.15 * (1.0 - ((t - 0.15) / 0.25).clamp(0.0, 1.0));
    final triggerR = triggerSize / 2 * triggerPulse;
    canvas.drawCircle(triggerCenter, triggerR, fillPaint);

    // Pills — each emerges with staggered spring timing
    for (int i = 0; i < pills.length; i++) {
      // Bottom pill (i=0) starts first, top pill starts last
      final at = 0.03 + i * 0.05;
      final localT = ((t - at) / 0.55).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      double scale;
      if (localT < 0.32) {
        scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
      } else {
        scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
      }

      final pw = pillWidth * scale;
      final ph = pillHeight * scale;
      final pill = pills[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pill.center, width: pw, height: ph),
          Radius.circular(pillRadius * scale),
        ),
        fillPaint,
      );

      // Connecting goo blob between consecutive pills
      if (i > 0 && t > 0.05 && t < 0.7) {
        final prevPill = pills[i - 1];
        final connectionFade = (1.0 - (t * 1.4 - 0.1).clamp(0.0, 1.0));
        if (connectionFade > 0.01) {
          final connPaint = Paint()
            ..color = surfaceColor.withValues(alpha: connectionFade)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma * 1.2)
            ..isAntiAlias = true;
          final midY = (prevPill.center.dy + pill.center.dy) / 2;
          final blobR = (pillHeight * 0.3) * (1.0 - scale * 0.5) * connectionFade;
          if (blobR > 1) {
            canvas.drawCircle(Offset(pill.center.dx, midY), blobR, connPaint);
          }
        }
      }
    }

    canvas.restore();

    // Borders on pills once settled
    for (int i = 0; i < pills.length; i++) {
      final at = 0.03 + i * 0.05;
      final localT = ((t - at) / 0.55).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      double scale;
      if (localT < 0.32) {
        scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
      } else {
        scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
      }

      if (scale < 0.15) continue;

      final borderOpacity = ((scale - 0.5) / 0.5).clamp(0.0, 1.0);
      if (borderOpacity <= 0) continue;

      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.05 * borderOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true;

      final pw = pillWidth * scale;
      final ph = pillHeight * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pills[i].center, width: pw, height: ph),
          Radius.circular(pillRadius * scale),
        ),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GooPillPainter old) => old.progress != progress;
}

// =============================================================================
// Crisp settled pill
// =============================================================================

class _CrispPill extends StatelessWidget {
  final AnimationController controller;
  final _PillGeom geom;
  final AzamanColors colors;
  final VoidCallback onClose;

  const _CrispPill({
    required this.controller,
    required this.geom,
    required this.colors,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final left = geom.center.dx - _pillWidth / 2;
    final top = geom.center.dy - _pillHeight / 2;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          // Stagger: bottom pills (i=0) appear first
          final at = 0.03 + geom.index * 0.05;
          final localT = ((t - at) / 0.55).clamp(0.0, 1.0);
          if (localT <= 0) return const SizedBox.shrink();

          // Crisp pill fades in as goo settles
          final crispOpacity = ((localT - 0.3) / 0.7).clamp(0.0, 1.0);
          if (crispOpacity <= 0.001) return const SizedBox.shrink();

          double scale;
          if (localT < 0.32) {
            scale = _restScale + (0.42 - _restScale) * (localT / 0.32);
          } else {
            scale = 0.42 + (1.0 - 0.42) * _PopSpringCurve().transform((localT - 0.32) / 0.68);
          }

          return GestureDetector(
            onTap: () {
              onClose();
              geom.item.onTap();
            },
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: crispOpacity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: Container(
                  width: _pillWidth,
                  height: _pillHeight,
                  padding: const EdgeInsets.symmetric(horizontal: _pillHPad),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(_pillRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(geom.item.icon, size: _pillIconSize, color: colors.textPrimary),
                      const SizedBox(width: 10),
                      Text(
                        geom.item.label,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: _pillLabelFS,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
