import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart'; // AzamanHaptics
import 'liquid_engine.dart';
import 'liquid_placement.dart';

class LiquidDropdownItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const LiquidDropdownItem({required this.icon, required this.label, required this.onTap});
}

const double _rowHeight = 48;      // ≥ 44 dp tap target
const double _panelPad = 8;
const double _panelRadius = 20;
const double _panelWidth = 200;
const double _panelGap = 14;
const double _panelRestScale = 0.08;

class LiquidDropdownMenu extends StatefulWidget {
  final List<LiquidDropdownItem> items;
  final AzamanColors colors;
  final double size;
  final String semanticLabel;
  const LiquidDropdownMenu({
    super.key,
    required this.items,
    required this.colors,
    this.size = kLiquidMinTapTarget, // 44, was 36
    this.semanticLabel = 'Attachments',
  });

  @override
  State<LiquidDropdownMenu> createState() => _LiquidDropdownMenuState();
}

class _LiquidDropdownMenuState extends State<LiquidDropdownMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 300),
  );
  final LayerLink _link = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  LiquidPhase _phase = LiquidPhase.closed;

  bool get _isOpen => _phase == LiquidPhase.open || _phase == LiquidPhase.opening;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _c.dispose();
    super.dispose();
  }

  void _toggle() => _isOpen ? _close() : _open();

  void _open() {
    if (_phase != LiquidPhase.closed || widget.items.isEmpty) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final dir = Directionality.of(context);

    final placement = solvePanel(
      anchor: anchor,
      panel: Size(_panelWidth, widget.items.length * _rowHeight + _panelPad * 2),
      safe: LiquidSafeArea(screen: media.size, padding: media.padding),
      direction: dir,
      gap: _panelGap,
    );

    AzamanHaptics.toggle();
    _entry = OverlayEntry(
      builder: (_) => Directionality(
        textDirection: dir,
        child: _LiquidPanelOverlay(
          controller: _c,
          link: _link,
          items: widget.items,
          colors: widget.colors,
          anchor: anchor,
          placement: placement,
          reduced: liquidReducedMotion(context),
          onClose: _close,
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() => _phase = LiquidPhase.opening);
    _c.forward(from: 0).whenComplete(() {
      if (mounted && _phase == LiquidPhase.opening) {
        setState(() => _phase = LiquidPhase.open);
      }
    });
  }

  void _close() {
    if (!_isOpen) return;
    setState(() => _phase = LiquidPhase.closing);
    AzamanHaptics.confirm();
    _c.reverse().whenComplete(() {
      _entry?.remove();
      _entry = null;
      if (mounted) setState(() => _phase = LiquidPhase.closed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final side = widget.size < kLiquidMinTapTarget ? kLiquidMinTapTarget : widget.size;

    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        expanded: _isOpen,
        label: widget.semanticLabel,
        hint: _isOpen ? 'Close attachment menu' : 'Open attachment menu',
        child: GestureDetector(
          key: _anchorKey,
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: side,
            height: side,
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => Transform.rotate(
                  angle: _c.value * 0.785398,
                  child: Container(
                    width: side - 4,
                    height: side - 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(c.surface, c.accentSurface, _c.value),
                      border: Border.all(color: c.textPrimary, width: 1.5),
                    ),
                    child: Icon(Icons.add, color: c.textPrimary, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidPanelOverlay extends StatelessWidget {
  final AnimationController controller;
  final LayerLink link;
  final List<LiquidDropdownItem> items;
  final AzamanColors colors;
  final Rect anchor;
  final PanelPlacement placement;
  final bool reduced;
  final VoidCallback onClose;

  const _LiquidPanelOverlay({
    required this.controller,
    required this.link,
    required this.items,
    required this.colors,
    required this.anchor,
    required this.placement,
    required this.reduced,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final rect = placement.rect;
    final follow = placement.followerOffset(anchor);
    final gooBounds = rect.expandToInclude(anchor).inflate(64);
    final gooFollow = gooBounds.topLeft - anchor.topLeft;

    return Stack(children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: controller,
                curve: const Interval(0, 0.2, curve: Curves.easeOut),
              ),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
            ),
          ),
        ),
      ),
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: gooFollow,
        child: SizedBox(
          width: gooBounds.width,
          height: gooBounds.height,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => CustomPaint(
                    painter: _PanelGooPainter(
                      t: reduced ? 1 : controller.value,
                      origin: gooBounds.topLeft,
                      anchor: anchor,
                      panel: rect,
                      body: colors.card,
                      rim: colors.divider,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: follow,
        child: SizedBox(
          width: rect.width,
          height: rect.height,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, child) {
              final t = reduced ? 1.0 : controller.value;
              final body = kHouseSpring.transform(Curves.easeOut.transform(t.clamp(0, 1)));
              final scale = _panelRestScale + (1 - _panelRestScale) * body;
              return Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translate(placement.origin.dx, placement.origin.dy)
                  ..scale(scale, scale)
                  ..translate(-placement.origin.dx, -placement.origin.dy),
                child: LiquidReveal(
                  opacity: ((t - 0.18) / 0.25).clamp(0.0, 1.0),
                  child: child!,
                ),
              );
            },
            child: Material(
              type: MaterialType.transparency,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: _panelPad),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (_, i) => _Row(
                  item: items[i],
                  index: placement.above ? items.length - 1 - i : i,
                  position: i,
                  total: items.length,
                  controller: controller,
                  colors: colors,
                  reduced: reduced,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ),
      ),
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: Offset.zero,
        child: SizedBox(
          width: anchor.width,
          height: anchor.height,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final t = reduced ? 1.0 : controller.value;
              final side = anchor.width;
              return Center(
                child: Transform.rotate(
                  angle: t * 0.785398,
                  child: Container(
                    width: side - 4,
                    height: side - 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(colors.surface, colors.accentSurface, t),
                      border: Border.all(color: colors.textPrimary, width: 1.5),
                    ),
                    child: Icon(Icons.add, color: colors.textPrimary, size: 22),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  final LiquidDropdownItem item;
  final int index, position, total;
  final AnimationController controller;
  final AzamanColors colors;
  final bool reduced;
  final VoidCallback onClose;
  const _Row({
    required this.item,
    required this.index,
    required this.position,
    required this.total,
    required this.controller,
    required this.colors,
    required this.reduced,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final start = 0.22 + index * 0.045;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final v = reduced ? 1.0 : controller.value;
        final t = ((v - start) / 0.34).clamp(0.0, 1.0);
        return LiquidReveal(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - kOutStrong.transform(t))),
            child: child!,
          ),
        );
      },
      child: Semantics(
        button: true,
        label: item.label,
        value: '${position + 1} of $total',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              AzamanHaptics.confirm();
              onClose();
              item.onTap();
            },
            child: SizedBox(
              height: _rowHeight,
              child: Row(children: [
                const SizedBox(width: 16),
                Icon(item.icon, size: 20, color: colors.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelGooPainter extends CustomPainter {
  final double t;
  final Offset origin;
  final Rect anchor;
  final Rect panel;
  final Color body, rim;

  _PanelGooPainter({
    required this.t,
    required this.origin,
    required this.anchor,
    required this.panel,
    required this.body,
    required this.rim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.001) return;

    final flight = (t / 0.55).clamp(0.0, 1.0) * (1 - ((t - 0.6) / 0.4).clamp(0.0, 1.0));
    final sigma = kGooBlurRest + (kGooBlurActive - kGooBlurRest) * flight;

    final grow = kHouseSpring.transform(Curves.easeOut.transform(t));
    final scale = _panelRestScale + (1 - _panelRestScale) * grow;
    final localAnchor = anchor.shift(-origin);
    final localPanel = panel.shift(-origin);
    final panelOrigin = localAnchor.center;
    final scaled = Rect.fromLTWH(
      panelOrigin.dx + (localPanel.left - panelOrigin.dx) * scale,
      panelOrigin.dy + (localPanel.top - panelOrigin.dy) * scale,
      localPanel.width * scale,
      localPanel.height * scale,
    );

    paintGoo(
      canvas,
      bounds: Offset.zero & size,
      sigma: sigma,
      body: body,
      rim: rim,
      shapes: (c, paint) {
        c.drawCircle(localAnchor.center, localAnchor.width / 2 * (1 + 0.12 * flight), paint);
        drawNeck(
          c,
          paint,
          from: localAnchor.center,
          to: Offset(scaled.center.dx, panel.top < anchor.top ? scaled.bottom : scaled.top),
          baseRadius: localAnchor.width * 0.34,
          t: (t / 0.5).clamp(0.0, 1.0),
          tension: flight,
        );
        c.drawPath(squirclePath(scaled, _panelRadius * scale), paint);
      },
    );
  }

  @override
  bool shouldRepaint(_PanelGooPainter old) =>
      old.t != t || old.panel != panel || old.anchor != anchor;
}
