import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// LIQUID DROPDOWN MENU — "anchored dropdown" (liquid-taffy interaction #1)
//
// Distinct from LiquidMenuButton (liquid-taffy's "speed dial" — satellites
// fanning out in a radial arc). This one "stays put and pours a dropdown out
// of itself, hanging above" — a single rounded panel that grows straight out
// of the trigger on a pop spring, rows condensing bottom-up (the row nearest
// the button settles first).
//
// liquid-taffy's reference centers the panel over the trigger, assuming the
// button sits mid-screen. Our "+" button lives near the LEFT edge of the
// chat input, so the panel is anchored so it grows UP AND TO THE RIGHT of
// the button instead of symmetrically — otherwise half the panel would be
// clipped off the left edge of the screen. The growth is a true point-scale
// from the trigger's center (not a fixed small resting scale hidden inside
// the circle), so at t=0 the panel is a literal point at the button and at
// t=1 it's resting in its final on-screen rect.
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

/// House spring: ζ=0.434, ω=22.46 — trigger scale-back + icon rotation.
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

/// Pop spring: ζ=0.479, ω=18.09 — the panel's leap out of the button.
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

const double _gooBlurActive = 5.0;
const double _gooBlurRest = 1.0;
const double _gooThresholdOuter = -11.6925;

const double _rowHeight = 46.0;
const double _panelWidth = 190.0;
const double _panelPad = 8.0;
const double _panelGap = 14.0;
const double _panelRadius = 18.0;

class LiquidDropdownMenu extends StatefulWidget {
  final List<LiquidDropdownItem> items;
  final AzamanColors colors;
  final double size;

  const LiquidDropdownMenu({
    super.key,
    required this.items,
    required this.colors,
    this.size = 40,
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
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 420),
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
    final triggerCenter = Offset(
      anchorPos.dx + anchorSize.width / 2,
      anchorPos.dy + anchorSize.height / 2,
    );

    final panelHeight = _panelPad * 2 + items.length * _rowHeight;

    // Grow to the RIGHT of the button (align panel's left edge with the
    // button's own left edge) instead of centering — our trigger sits near
    // the screen's left edge, so a centered panel would clip off-screen.
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
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;

            // Exactly one visual layer at a time: goo while in-motion, crisp
            // bordered panel once settled open, crisp trigger once settled
            // closed — matches liquid-taffy's "one picture at a time" rule
            // and avoids a doubled-border flash mid-morph.
            final triggerCrisp = (1.0 - (t / 0.04).clamp(0.0, 1.0)).clamp(0.0, 1.0);
            final panelCrisp = (((t - 0.97) / 0.03).clamp(0.0, 1.0));
            final gooOpacity = (1.0 - triggerCrisp - panelCrisp).clamp(0.0, 1.0);

            final triggerScale = t < 0.22
                ? 1.0 + 0.18 * (t / 0.22)
                : _HouseSpringCurve().transform(((t - 0.22) / 0.78).clamp(0.0, 1.0));

            final panelT = ((t - 0.14) / 0.86).clamp(0.0, 1.0);
            double panelScale;
            if (panelT < 0.34) {
              panelScale = (panelT / 0.34) * 0.42;
            } else {
              final launchT = (panelT - 0.34) / 0.66;
              panelScale = 0.42 + 0.58 * _PopSpringCurve().transform(launchT);
            }

            final iconRotation = _HouseSpringCurve().transform(t.clamp(0.0, 1.0)) * 135.0;

            // Point-scale every corner of the panel's resting rect toward
            // the trigger's own center — at scale 0 the rect IS that point.
            final curLeft = triggerCenter.dx + (panelLeft - triggerCenter.dx) * panelScale;
            final curTop = triggerCenter.dy + (panelTop - triggerCenter.dy) * panelScale;
            final curWidth = _panelWidth * panelScale;
            final curHeight = panelHeight * panelScale;

            return Stack(
              children: [
                if (gooOpacity > 0.001)
                  Opacity(
                    opacity: gooOpacity,
                    child: CustomPaint(
                      size: screenSize,
                      painter: _DropdownGooPainter(
                        triggerCenter: triggerCenter,
                        triggerRadius: (anchorSize.width / 2) * triggerScale,
                        panelRect: Rect.fromLTWH(curLeft, curTop, curWidth, curHeight),
                        panelRadius: _panelRadius * panelScale,
                        surfaceColor: colors.card,
                        progress: t,
                      ),
                    ),
                  ),
                if (panelCrisp > 0.001)
                  Positioned(
                    left: panelLeft,
                    top: panelTop,
                    child: Opacity(
                      opacity: panelCrisp,
                      child: _DropdownPanel(colors: colors, items: items, onClose: onClose),
                    ),
                  ),
                // Icon glyphs ride above the goo the whole time it's forming,
                // fading + settling with a bottom-up stagger (the row nearest
                // the button appears first, like it's pouring out of it).
                if (gooOpacity > 0.05 || panelCrisp > 0.001)
                  ...List.generate(items.length, (i) {
                    final reverseIndex = items.length - 1 - i;
                    final start = 0.42 + reverseIndex * 0.06;
                    final end = start + 0.30;
                    final localT = ((t - start) / (end - start)).clamp(0.0, 1.0);
                    if (localT <= 0.0) return const SizedBox.shrink();
                    final eased = Curves.easeOutCubic.transform(localT);
                    return Positioned(
                      left: panelLeft,
                      top: panelTop + _panelPad + i * _rowHeight + (1 - eased) * 10,
                      child: Opacity(
                        opacity: panelCrisp > 0.5 ? 0.0 : eased,
                        child: _DropdownRow(
                          item: items[i],
                          colors: colors,
                          width: _panelWidth,
                          isLast: i == items.length - 1,
                          onTap: () {
                            onClose();
                            items[i].onTap();
                          },
                        ),
                      ),
                    );
                  }),
                Positioned(
                  left: anchorPos.dx,
                  top: anchorPos.dy,
                  child: Opacity(
                    opacity: triggerCrisp,
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
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// =============================================================================
// Goo painter — trigger circle + growing panel rounded-rect, blended
// =============================================================================

class _DropdownGooPainter extends CustomPainter {
  final Offset triggerCenter;
  final double triggerRadius;
  final Rect panelRect;
  final double panelRadius;
  final Color surfaceColor;
  final double progress;

  _DropdownGooPainter({
    required this.triggerCenter,
    required this.triggerRadius,
    required this.panelRect,
    required this.panelRadius,
    required this.surfaceColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;

    final activeAmount = math.min(progress * 4, 1.0);
    final blurSigma = _gooBlurActive * activeAmount + _gooBlurRest * (1 - activeAmount);
    final threshold = _gooThresholdOuter * activeAmount;

    final thresholdMatrix = <double>[
      1.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 30.0, threshold,
    ];

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.saveLayer(bounds, Paint()..colorFilter = ColorFilter.matrix(thresholdMatrix));

    final fillPaint = Paint()
      ..color = surfaceColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
      ..isAntiAlias = true;

    if (triggerRadius > 0.5) {
      canvas.drawCircle(triggerCenter, triggerRadius, fillPaint);
    }
    if (panelRect.width > 1 && panelRect.height > 1) {
      final rrect = RRect.fromRectAndRadius(panelRect, Radius.circular(panelRadius.clamp(0, 100)));
      canvas.drawRRect(rrect, fillPaint);
    }

    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;
    if (triggerRadius > 2.0) canvas.drawCircle(triggerCenter, triggerRadius, borderPaint);
    if (panelRect.width > 4 && panelRect.height > 4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(panelRect, Radius.circular(panelRadius.clamp(0, 100))),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DropdownGooPainter old) => old.progress != progress;
}

// =============================================================================
// Crisp settled panel (fully open, fully closed states)
// =============================================================================

class _DropdownPanel extends StatelessWidget {
  final AzamanColors colors;
  final List<LiquidDropdownItem> items;
  final VoidCallback onClose;

  const _DropdownPanel({required this.colors, required this.items, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _panelWidth,
      padding: const EdgeInsets.symmetric(vertical: _panelPad),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(_panelRadius),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++)
            _DropdownRow(
              item: items[i],
              colors: colors,
              width: _panelWidth,
              isLast: i == items.length - 1,
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

class _DropdownRow extends StatelessWidget {
  final LiquidDropdownItem item;
  final AzamanColors colors;
  final double width;
  final bool isLast;
  final VoidCallback onTap;

  const _DropdownRow({
    required this.item,
    required this.colors,
    required this.width,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: null,
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 19, color: colors.textPrimary),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(color: colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
