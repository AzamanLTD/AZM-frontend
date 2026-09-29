// =============================================================================
// LIQUID LAUNCHER — embedded radial burst (TASK-018)
//
// The unified radial launcher for hosts that already own their scrim and
// dismissal — bottom sheets, docks, hub pages. Unlike the trigger-style
// CategorySpeedDial / LiquidDropdownMenu (OverlayEntry + scrim + ghost), this
// widget bursts its satellites IN PLACE around an anchor point inside its own
// box. The host must give it bounded constraints (a fixed SizedBox); the burst
// solves its geometry once, in the widget's local coordinate space, on the
// first frame.
//
// One gesture vocabulary, shared with the dial and the dropdown:
//   launch  → satellites ride kPopSpring / kHouseSpring (satelliteScale /
//             satelliteTravel, reused from category_speed_dial.dart)
//   merge   → goo-rim merging via paintGoo + drawNeck + squirclePath
//   gate    → LiquidReveal (nothing is tappable before it is readable)
//   haptics → pick fires AzamanHaptics.confirm() EXACTLY once; opening and
//             dismissal are silent (the host owns both)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

import 'category_speed_dial.dart'
    show measureSatellitePill, satelliteScale, satelliteTravel, solveRadialFan;
import 'liquid_engine.dart';
import 'liquid_placement.dart';

// Satellite dims mirror category_speed_dial.dart's satellites so the burst
// is indistinguishable from the dial's. `measureSatellitePill` measures
// with those same dims — keep the two files' numbers in sync.
// (Audit 2026-09-29: these MUST be top-level, not State-class statics —
// `_LauncherGooPainter` and `_LauncherSatellite` below reference them
// unqualified; as originally written this file did not compile.)
const double _kSatPillHPad = 13;
const double _kSatPillRadius = 19;
const double _kSatIconSize = 15;
const double _kSatLabelFS = 12;
const double _kAnchorSize = 44;
const double _kAnchorRadius = 22;

class LiquidLauncherItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const LiquidLauncherItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class LiquidLauncher extends ConsumerStatefulWidget {
  final List<LiquidLauncherItem> items;
  final String semanticLabel;
  const LiquidLauncher({
    super.key,
    required this.items,
    this.semanticLabel = 'Menu',
  });

  @override
  ConsumerState<LiquidLauncher> createState() => _LiquidLauncherState();
}

class _LiquidLauncherState extends ConsumerState<LiquidLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 660),
    reverseDuration: const Duration(milliseconds: 340),
  );

  // Reversed so widget.items.first lands at the TOP of the right-opening fan
  // (solveRadialFan puts index 0 at the bottom) — the burst reads in the
  // host's list order, top to bottom.
  late final List<LiquidLauncherItem> _fanOrder = widget.items.reversed
      .toList();

  List<ArcSlot>? _slots;
  Rect _anchorLocal = Rect.zero;
  bool _solved = false;

  // The measured style must match the rendered style's metrics exactly —
  // same fontSize / weight / decoration as the satellite TextStyle below.
  TextStyle get _satLabelStyle => const TextStyle(
    fontSize: _kSatLabelFS,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.none,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _solveFor(Size box) {
    _solved = true;
    if (widget.items.isEmpty) return;

    // The anchor is the box centre: the fan opens symmetrically around it and
    // the safe-area clamp keeps every satellite inside the host's box.
    _anchorLocal = Rect.fromCenter(
      center: box.center(Offset.zero),
      width: _kAnchorSize,
      height: _kAnchorSize,
    );
    final media = MediaQuery.of(context);
    final dir = Directionality.of(context);
    final safe = LiquidSafeArea(
      screen: box,
      padding: EdgeInsets.zero,
      margin: 6,
    );
    final slots = solveRadialFan(
      anchor: _anchorLocal,
      sizes: [
        for (final it in _fanOrder)
          measureSatellitePill(it.label, _satLabelStyle, media.textScaler, dir),
      ],
      safe: safe,
    );
    if (!mounted) return;
    setState(() => _slots = slots);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final reduced = liquidReducedMotion(context);

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          // The host contract is bounded constraints (the host wraps the
          // launcher in a fixed SizedBox). Without a finite box there is
          // nowhere to solve the fan — render nothing.
          if (box.isEmpty || !box.isFinite) {
            return const SizedBox.shrink();
          }
          if (!_solved) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _solveFor(box);
            });
          }
          final slots = _slots;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (slots != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (_, __) => CustomPaint(
                            painter: _LauncherGooPainter(
                              t: reduced ? 1 : _c.value,
                              anchor: _anchorLocal,
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
              if (slots != null)
                for (var i = 0; i < slots.length; i++)
                  _LauncherSatellite(
                    controller: _c,
                    slot: slots[i],
                    anchor: _anchorLocal,
                    item: _fanOrder[i],
                    total: slots.length,
                    colors: colors,
                    reduced: reduced,
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The goo-rim merging layer: the painted anchor hub plus every satellite's
/// neck and squircle, composed through paintGoo so overlapping shapes merge
/// with a constant-width rim — identical recipe to `_DialGooPainter`, in
/// local coordinates (origin is Offset.zero).
///
/// At rest the hub REMAINS VISIBLE as the fan's origin (the necks attach to
/// it). The dial covers its equivalent blob with the trigger ghost — the
/// launcher has no trigger, so the hub is a decorative painted element; the
/// layer is wrapped in IgnorePointer + ExcludeSemantics (never tappable,
/// never read out).
class _LauncherGooPainter extends CustomPainter {
  final double t;
  final Rect anchor;
  final List<ArcSlot> slots;
  final Color body, rim;

  _LauncherGooPainter({
    required this.t,
    required this.anchor,
    required this.slots,
    required this.body,
    required this.rim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.001) return;
    final flight =
        (t / 0.45).clamp(0.0, 1.0) * (1 - ((t - 0.62) / 0.38).clamp(0.0, 1.0));
    final sigma = kGooBlurRest + (kGooBlurActive - kGooBlurRest) * flight;

    paintGoo(
      canvas,
      bounds: Offset.zero & size,
      sigma: sigma,
      body: body,
      rim: rim,
      shapes: (c, paint) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            anchor.inflate(2 * flight),
            const Radius.circular(_kAnchorRadius),
          ),
          paint,
        );
        for (final slot in slots) {
          final s = satelliteScale(t, slot.index);
          final travel = satelliteTravel(t, slot.index);
          if (travel <= 0) continue;
          final centre = Offset.lerp(anchor.center, slot.rect.center, travel)!;
          final r = Rect.fromCenter(
            center: centre,
            width: slot.rect.width * s.sx,
            height: slot.rect.height * s.sy,
          );
          drawNeck(
            c,
            paint,
            from: anchor.center,
            to: centre,
            baseRadius: _kAnchorSize * 0.30,
            t: (travel * 1.4).clamp(0.0, 1.0),
            tension: flight,
          );
          c.drawPath(squirclePath(r, _kSatPillRadius * s.sy), paint);
        }
      },
    );
  }

  @override
  // body/rim/anchor: a theme switch at rest must repaint the goo layer — the
  // satellites rebuild via the themeProvider watch, the painter would not.
  bool shouldRepaint(_LauncherGooPainter old) =>
      old.t != t ||
      old.slots != slots ||
      old.body != body ||
      old.rim != rim ||
      old.anchor != anchor;
}

/// One interactive satellite: flies from the anchor to its slot, gated by
/// LiquidReveal (untappable until readable), fires exactly one confirm on
/// pick. Mirror of `_SatellitePill` in category_speed_dial.dart.
class _LauncherSatellite extends StatelessWidget {
  final AnimationController controller;
  final ArcSlot slot;
  final Rect anchor;
  final LiquidLauncherItem item;
  final int total;
  final AzamanColors colors;
  final bool reduced;

  const _LauncherSatellite({
    required this.controller,
    required this.slot,
    required this.anchor,
    required this.item,
    required this.total,
    required this.colors,
    required this.reduced,
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
            item.onTap();
          },
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(_kSatPillRadius),
              border: Border.all(color: colors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: _kSatPillHPad),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: _kSatIconSize, color: colors.textPrimary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: _kSatLabelFS,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
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
