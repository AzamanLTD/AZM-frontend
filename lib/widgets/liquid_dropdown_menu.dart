import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// LIQUID DROPDOWN MENU — smooth anchored dropdown
//
// A clean, smooth dropdown that grows out of the trigger button with a
// gentle spring scale + fade. No heavy goo/metaball rendering — just
// a crisp panel that animates in fluidly. Rows fade in with a subtle
// stagger (bottom-up), each row settling with an ease-out curve.
//
// The panel is anchored so it grows UP from the trigger button,
// aligned to the button's left edge (since the + button sits near
// the left edge of the chat input).
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
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
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

    // Anchor panel to the left edge of the trigger button
    double panelLeft = anchorPos.dx;
    const margin = 12.0;
    if (panelLeft + _panelWidth > screenSize.width - margin) {
      panelLeft = screenSize.width - margin - _panelWidth;
    }
    if (panelLeft < margin) panelLeft = margin;

    // Panel sits above the trigger with a small gap
    double panelBottom = anchorPos.dy - _panelGap;
    double panelTop = panelBottom - panelHeight;
    final minTop = safeTop + margin;
    if (panelTop < minTop) {
      panelTop = minTop;
      panelBottom = panelTop + panelHeight;
    }

    return Stack(
      children: [
        // Dismiss backdrop
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: FadeTransition(
              opacity: Tween(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: controller,
                  curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
                ),
              ),
              child: Container(color: Colors.black.withValues(alpha: 0.15)),
            ),
          ),
        ),
        // Animated panel
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;

            // Smooth spring scale — no overshoot, gentle critically-damped ease
            const w = 15.0;
            final springT = 1.0 - math.exp(-w * t);
            final scale = 0.85 + 0.15 * springT.clamp(0.0, 1.0);

            // Panel opacity fades in smoothly
            final panelOpacity = (t * 1.5).clamp(0.0, 1.0);

            return Stack(
              children: [
                // The panel itself — scales from bottom-center (grows upward from trigger)
                Positioned(
                  left: panelLeft,
                  top: panelTop,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    child: Opacity(
                      opacity: panelOpacity,
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
      ],
    );
  }
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

/// A dropdown row that fades + slides in based on the overall animation progress.
/// Rows closer to the trigger (bottom of panel) appear first.
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
    // Stagger: bottom rows (closer to trigger) appear first
    final reverseIndex = totalItems - 1 - index;
    final start = 0.15 + reverseIndex * 0.08;
    final end = start + 0.35;
    final localT = ((progress - start) / (end - start)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(localT);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(0, (1 - eased) * 8),
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
