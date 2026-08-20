import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'liquid_engine.dart';
import 'liquid_placement.dart';

class CategoryDialItem {
  final String? wire;
  final IconData icon;
  final String label;
  const CategoryDialItem({required this.wire, required this.icon, required this.label});
}

const double _pillHeight = kLiquidMinTapTarget; // 44, was 38
const double _pillHPad = 16;
const double _pillRadius = 22;
const double _iconSize = 17;
const double _labelFS = 13;
const double _restScale = 0.12;

/// Real measurement — no character counting, honours the user's text scale.
Size measurePill(String label, TextStyle style, TextScaler scaler, TextDirection dir) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: dir,
    textScaler: scaler,
  )..layout();
  return Size(_pillHPad * 2 + _iconSize + 8 + tp.width, _pillHeight);
}

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 660),
    reverseDuration: const Duration(milliseconds: 340),
  );
  final LayerLink _link = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  LiquidPhase _phase = LiquidPhase.closed;

  bool get _isOpen => _phase == LiquidPhase.open || _phase == LiquidPhase.opening;

  CategoryDialItem get _current => widget.categories.firstWhere(
        (c) => c.wire == widget.selectedWire,
        orElse: () => widget.categories.first,
      );

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _c.dispose();
    super.dispose();
  }

  TextStyle get _labelStyle => TextStyle(
        fontSize: _labelFS,
        fontWeight: FontWeight.w600,
        color: widget.colors.textPrimary,
        decoration: TextDecoration.none,
      );

  void _toggle() => _isOpen ? _close() : _open();

  void _open() {
    if (_phase != LiquidPhase.closed) return; // re-entrancy guard
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final dir = Directionality.of(context);
    final satellites =
        widget.categories.where((c) => c.wire != widget.selectedWire).toList();
    if (satellites.isEmpty) return;

    final slots = solveArc(
      anchor: anchor,
      sizes: [
        for (final s in satellites) measurePill(s.label, _labelStyle, media.textScaler, dir)
      ],
      safe: LiquidSafeArea(screen: media.size, padding: media.padding),
      direction: dir,
    );

    AzamanHaptics.toggle();
    _entry = OverlayEntry(
      builder: (_) => Directionality(
        textDirection: dir,
        child: _DialOverlay(
          controller: _c,
          link: _link,
          anchor: anchor,
          slots: slots,
          items: satellites,
          colors: widget.colors,
          labelStyle: _labelStyle,
          reduced: liquidReducedMotion(context),
          onClose: _close,
          onPick: (item) {
            _close();
            widget.onSelected(item.wire);
          },
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
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        expanded: _isOpen,
        label: 'Category: ${_current.label}',
        hint: _isOpen ? 'Close category picker' : 'Open category picker',
        child: GestureDetector(
          key: _anchorKey,
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final w = liquidReducedMotion(context)
                  ? (x: 1.0, y: 1.0)
                  : jelloWobble(_c.value);
              return Transform.scale(
                scaleX: w.x,
                scaleY: w.y,
                child: ExcludeSemantics(
                  child: Container(
                    height: _pillHeight,
                    padding: const EdgeInsets.symmetric(horizontal: _pillHPad),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(_pillRadius),
                      border: Border.all(color: c.divider),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_current.icon, size: _iconSize, color: c.textPrimary),
                      const SizedBox(width: 8),
                      Text(_current.label, style: _labelStyle),
                      const SizedBox(width: 4),
                      Transform.rotate(
                        angle: _c.value * 3.14159,
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            size: 18, color: c.textSecondary),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Two-beat launch: OOZE (0.16s to 0.42) then LAUNCH on the pop spring, with
/// the width axis 30 ms behind the height axis.
({double sx, double sy}) satelliteScale(double t, int index) {
  final at = 0.03 + index * 0.045;
  final local = t - at;
  if (local <= 0) return (sx: _restScale, sy: _restScale);
  if (local < 0.16) {
    final k = Curves.easeInOut.transform(local / 0.16);
    final s = _restScale + (0.42 - _restScale) * k;
    return (sx: s, sy: s);
  }
  final ky = kPopSpring.transform(((local - 0.16) / 0.30).clamp(0.0, 1.0));
  final kx = kPopSpring.transform(((local - 0.19) / 0.30).clamp(0.0, 1.0));
  return (sx: 0.42 + 0.58 * kx, sy: 0.42 + 0.58 * ky);
}

double satelliteTravel(double t, int index) =>
    kHouseSpring.transform(((t - 0.03 - index * 0.045) / 0.46).clamp(0.0, 1.0));

class _DialOverlay extends StatelessWidget {
  final AnimationController controller;
  final LayerLink link;
  final Rect anchor;
  final List<ArcSlot> slots;
  final List<CategoryDialItem> items;
  final AzamanColors colors;
  final TextStyle labelStyle;
  final bool reduced;
  final VoidCallback onClose;
  final ValueChanged<CategoryDialItem> onPick;

  const _DialOverlay({
    required this.controller,
    required this.link,
    required this.anchor,
    required this.slots,
    required this.items,
    required this.colors,
    required this.labelStyle,
    required this.reduced,
    required this.onClose,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    var bounds = anchor;
    for (final s in slots) {
      bounds = bounds.expandToInclude(s.rect);
    }
    bounds = bounds.inflate(56);

    return Stack(children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: FadeTransition(
              opacity: CurvedAnimation(parent: controller, curve: const Interval(0, 0.2)),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.14)),
            ),
          ),
        ),
      ),
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: bounds.topLeft - anchor.topLeft,
        child: SizedBox(
          width: bounds.width,
          height: bounds.height,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => CustomPaint(
                    painter: _DialGooPainter(
                      t: reduced ? 1 : controller.value,
                      origin: bounds.topLeft,
                      anchor: anchor,
                      slots: slots,
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
      for (var i = 0; i < slots.length; i++)
        _SatellitePill(
          controller: controller,
          slot: slots[i],
          anchor: anchor,
          item: items[i],
          total: slots.length,
          colors: colors,
          labelStyle: labelStyle,
          reduced: reduced,
          onPick: onPick,
        ),
    ]);
  }
}

class _SatellitePill extends StatelessWidget {
  final AnimationController controller;
  final ArcSlot slot;
  final Rect anchor;
  final CategoryDialItem item;
  final int total;
  final AzamanColors colors;
  final TextStyle labelStyle;
  final bool reduced;
  final ValueChanged<CategoryDialItem> onPick;

  const _SatellitePill({
    required this.controller,
    required this.slot,
    required this.anchor,
    required this.item,
    required this.total,
    required this.colors,
    required this.labelStyle,
    required this.reduced,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = reduced ? 1.0 : controller.value;
        final s = satelliteScale(t, slot.index);
        final travel = satelliteTravel(t, slot.index);
        final pos = Rect.fromLTWH(
          anchor.center.dx + (slot.rect.left - anchor.center.dx) * travel,
          anchor.center.dy + (slot.rect.top - anchor.center.dy) * travel,
          slot.rect.width,
          slot.rect.height,
        );
        return Positioned(
          left: pos.left,
          top: pos.top,
          width: pos.width,
          height: pos.height,
          // Gate taps: a pill you cannot read yet is not tappable.
          child: LiquidReveal(
            opacity: ((travel - 0.25) / 0.35).clamp(0.0, 1.0),
            child: Transform.scale(scaleX: s.sx, scaleY: s.sy, child: child!),
          ),
        );
      },
      child: Semantics(
        button: true,
        label: item.label,
        value: '${slot.index + 1} of $total',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AzamanHaptics.confirm();
            onPick(item);
          },
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(_pillRadius),
              border: Border.all(color: colors.divider),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: _pillHPad),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: _iconSize, color: colors.textPrimary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: labelStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialGooPainter extends CustomPainter {
  final double t;
  final Offset origin;
  final Rect anchor;
  final List<ArcSlot> slots;
  final Color body, rim;

  _DialGooPainter({
    required this.t,
    required this.origin,
    required this.anchor,
    required this.slots,
    required this.body,
    required this.rim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.001) return;
    final flight = (t / 0.45).clamp(0.0, 1.0) * (1 - ((t - 0.62) / 0.38).clamp(0.0, 1.0));
    final sigma = kGooBlurRest + (kGooBlurActive - kGooBlurRest) * flight;
    final a = anchor.shift(-origin);

    paintGoo(
      canvas,
      bounds: Offset.zero & size,
      sigma: sigma,
      body: body,
      rim: rim,
      shapes: (c, paint) {
        c.drawRRect(
          RRect.fromRectAndRadius(a.inflate(2 * flight), const Radius.circular(_pillRadius)),
          paint,
        );
        for (final slot in slots) {
          final s = satelliteScale(t, slot.index);
          final travel = satelliteTravel(t, slot.index);
          if (travel <= 0) continue;
          final target = slot.rect.shift(-origin);
          final centre = Offset.lerp(a.center, target.center, travel)!;
          final r = Rect.fromCenter(
            center: centre,
            width: target.width * s.sx,
            height: target.height * s.sy,
          );
          drawNeck(
            c,
            paint,
            from: a.center,
            to: centre,
            baseRadius: _pillHeight * 0.30,
            t: (travel * 1.4).clamp(0.0, 1.0),
            tension: flight,
          );
          c.drawPath(squirclePath(r, _pillRadius * s.sy), paint);
        }
      },
    );
  }

  @override
  bool shouldRepaint(_DialGooPainter old) => old.t != t || old.slots != slots;
}
