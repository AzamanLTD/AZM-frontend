import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// LIQUID DROPDOWN MENU — goo/metaball anchored dropdown
//
// A liquid dropdown that grows out of the trigger button using a real
// goo/metaball effect. The trigger circle melts upward into a blob that
// resolves into the panel. Each row emerges from the goo mass and settles
// as a crisp row with staggered spring timing.
//
// Technique: draw the trigger + a growing panel blob as blurred filled
// shapes on a saveLayer with a threshold color matrix. The blur+threshold
// creates the gooey metaball merge. Crisp rows paint on top once the
// panel has settled.
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

const double _rowHeight = 44.0;
const double _panelWidth = 180.0;
const double _panelPad = 6.0;
const double _panelGap = 10.0;
const double _panelRadius = 16.0;

// ---- Goo constants ----
const double _gooBlurActive = 7.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;

// ---- Spring curve (critically damped, slight overshoot) ----
class _SpringCurve extends Curve {
  @override
  double transformInternal(double t) {
    const w = 16.0;
    const z = 0.42;
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
      duration: const Duration(milliseconds: 650),
      reverseDuration: const Duration(milliseconds: 300),
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
    final panelHeight = _panelPad * 2 + items.length * _rowHeight;

    double panelLeft = anchorPos.dx;
    const margin = 12.0;
    if (panelLeft + _panelWidth > screenSize.width - margin) {
      panelLeft = screenSize.width - margin - _panelWidth;
    }
    if (panelLeft < margin) panelLeft = margin;

    double panelBottom = anchorPos.dy - _panelGap;
    double panelTop = panelBottom - panelHeight;
    final minTop = safeTop + margin;
    if (panelTop < minTop) {
      panelTop = minTop;
      panelBottom = panelTop + panelHeight;
    }

    final triggerCenter = Offset(
      anchorPos.dx + anchorSize.width / 2,
      anchorPos.dy + anchorSize.height / 2,
    );

    final panelCenter = Offset(
      panelLeft + _panelWidth / 2,
      panelTop + panelHeight / 2,
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
        // Goo canvas — metaball merge between trigger and panel
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
                    painter: _GooPanelPainter(
                      progress: t,
                      triggerCenter: triggerCenter,
                      triggerSize: anchorSize.width,
                      panelCenter: panelCenter,
                      panelWidth: _panelWidth,
                      panelHeight: panelHeight,
                      panelRadius: _panelRadius,
                      surfaceColor: colors.card,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Crisp panel with rows (fades in as goo settles)
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            final panelOpacity = ((t - 0.35) / 0.4).clamp(0.0, 1.0);
            if (panelOpacity <= 0.001) return const SizedBox.shrink();

            final springT = _SpringCurve().transform(t.clamp(0.0, 1.0));
            final scale = 0.88 + 0.12 * springT;

            return Stack(
              children: [
                Positioned(
                  left: panelLeft,
                  top: panelTop,
                  child: Opacity(
                    opacity: panelOpacity,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomCenter,
                      child: _DropdownPanel(
                        colors: colors,
                        items: items,
                        onClose: onClose,
                        progress: t,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        // Trigger button copy (crisp during animation)
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
// Goo Panel Painter — metaball merge between trigger circle and panel rect
// =============================================================================

class _GooPanelPainter extends CustomPainter {
  final double progress;
  final Offset triggerCenter;
  final double triggerSize;
  final Offset panelCenter;
  final double panelWidth;
  final double panelHeight;
  final double panelRadius;
  final Color surfaceColor;

  _GooPanelPainter({
    required this.progress,
    required this.triggerCenter,
    required this.triggerSize,
    required this.panelCenter,
    required this.panelWidth,
    required this.panelHeight,
    required this.panelRadius,
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

    final minX = math.min(triggerCenter.dx - triggerSize, panelCenter.dx - panelWidth / 2) - 40;
    final maxX = math.max(triggerCenter.dx + triggerSize, panelCenter.dx + panelWidth / 2) + 40;
    final minY = math.min(triggerCenter.dy - triggerSize, panelCenter.dy - panelHeight / 2) - 40;
    final maxY = math.max(triggerCenter.dy + triggerSize, panelCenter.dy + panelHeight / 2) + 40;
    final bounds = Rect.fromLTRB(minX, minY, maxX, maxY);

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

    // Panel grows from trigger position to final position
    final panelGrowEase = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

    final currentW = triggerSize + (panelWidth - triggerSize) * panelGrowEase;
    final currentH = triggerSize + (panelHeight - triggerSize) * panelGrowEase;

    final currentCenter = Offset(
      triggerCenter.dx + (panelCenter.dx - triggerCenter.dx) * panelGrowEase,
      triggerCenter.dy + (panelCenter.dy - triggerCenter.dy) * panelGrowEase,
    );

    final panelGrow = _SpringCurve().transform(t.clamp(0.0, 1.0));
    final currentRadius = t < 0.3
        ? currentW / 2
        : _panelRadius * panelGrow;

    final panelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: currentCenter, width: currentW, height: currentH),
      Radius.circular(currentRadius),
    );
    canvas.drawRRect(panelRect, fillPaint);

    // Connecting goo blobs between trigger and panel for the melt effect
    if (t > 0.05 && t < 0.7) {
      final connectionT = (t - 0.05) / 0.65;
      final connectionFade = (1.0 - (connectionT * 1.4).clamp(0.0, 1.0));

      if (connectionFade > 0.01) {
        final connPaint = Paint()
          ..color = surfaceColor.withValues(alpha: connectionFade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma * 1.2)
          ..isAntiAlias = true;

        for (int i = 1; i <= 3; i++) {
          final f = i / 4.0;
          final cx = triggerCenter.dx + (currentCenter.dx - triggerCenter.dx) * f;
          final cy = triggerCenter.dy + (currentCenter.dy - triggerCenter.dy) * f;
          final blobR = (triggerSize * 0.4) * (1.0 - panelGrowEase * 0.7) * connectionFade;
          if (blobR > 1) {
            canvas.drawCircle(Offset(cx, cy), blobR, connPaint);
          }
        }
      }
    }

    canvas.restore();

    // Border on the panel once mostly formed
    if (panelGrow > 0.3) {
      final borderOpacity = ((panelGrow - 0.3) / 0.7).clamp(0.0, 1.0);
      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.05 * borderOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true;

      canvas.drawRRect(panelRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GooPanelPainter old) => old.progress != progress;
}

// =============================================================================
// Crisp settled panel with staggered row fade-in
// =============================================================================

class _DropdownPanel extends StatelessWidget {
  final AzamanColors colors;
  final List<LiquidDropdownItem> items;
  final VoidCallback onClose;
  final double progress;

  const _DropdownPanel({
    required this.colors,
    required this.items,
    required this.onClose,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _panelWidth,
      padding: const EdgeInsets.symmetric(vertical: _panelPad),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(_panelRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++)
            _AnimatedDropdownRow(
              item: items[i],
              colors: colors,
              width: _panelWidth,
              progress: progress,
              index: i,
              totalItems: items.length,
              onTap: () {
                onClose();
                items[i].onTap();
              },
            ),
        ],
      ),
    );
  }
}

/// A dropdown row that emerges from the goo with a spring and settles crisp.
class _AnimatedDropdownRow extends StatelessWidget {
  final LiquidDropdownItem item;
  final AzamanColors colors;
  final double width;
  final double progress;
  final int index;
  final int totalItems;
  final VoidCallback onTap;

  const _AnimatedDropdownRow({
    required this.item,
    required this.colors,
    required this.width,
    required this.progress,
    required this.index,
    required this.totalItems,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reverseIndex = totalItems - 1 - index;
    final start = 0.25 + reverseIndex * 0.07;
    final end = start + 0.4;
    final localT = ((progress - start) / (end - start)).clamp(0.0, 1.0);
    final springT = _SpringCurve().transform(localT);
    final eased = Curves.easeOutCubic.transform(localT);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(0, (1 - springT) * 12),
          child: Container(
            width: width,
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: colors.textPrimary),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
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
  }
}
