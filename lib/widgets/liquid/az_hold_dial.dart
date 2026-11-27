// lib/widgets/liquid/az_hold_dial.dart
// =============================================================================
// THE HOLD DIAL — press, hold, lean, release.
//
// A four-way action dial that opens around whatever it wraps (a story avatar,
// later a store's profile) after a short hold:
//
//              [ up ]
//     [ left ]  (you)  [ right ]
//             [ down ]
//
//   • Tap does the wrapped thing's normal action, untouched.
//   • Hold (350 ms) opens the dial. The hold claims the touch ONLY once it
//     fires, so a horizontal row of avatars still scrolls under a normal
//     swipe.
//   • Lean toward a chip and release to run it (a selection tick on each
//     lean, a commit haptic on release). Release in the centre and the dial
//     stays open: tap a chip, or tap anywhere else to close.
//   • Less obstructive than a scrim: only a soft radial dim around the anchor
//     (the anchor itself stays crisp), small glass chips, and a label only
//     on the chip you lean toward. The rest of the screen stays readable.
//   • Unavailable directions are dimmed, never hidden: the layout is stable.
//   • Every action is also a semantics custom action, for screen readers.
//   • Reduced motion: chips appear in place, no travel.
// =============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/utils/azaman_haptics.dart';

enum AzDialDirection { up, down, left, right }

@immutable
class AzHoldDialAction {
  const AzHoldDialAction({required this.icon, required this.label, this.onSelect});

  final IconData icon;
  final String label;

  /// Null = unavailable here (dimmed, not selectable).
  final VoidCallback? onSelect;

  bool get enabled => onSelect != null;
}

class AzHoldDial extends StatefulWidget {
  const AzHoldDial({
    super.key,
    required this.child,
    required this.actions,
    this.onTap,
    this.holdDuration = const Duration(milliseconds: 350),
    this.radius = 78,
  });

  final Widget child;
  final Map<AzDialDirection, AzHoldDialAction> actions;
  final VoidCallback? onTap;
  final Duration holdDuration;

  /// Distance from the anchor's centre to each chip's centre.
  final double radius;

  /// Which direction a drag offset leans toward, or null inside the dead
  /// zone. Pure, so it is unit-tested.
  static AzDialDirection? leanFor(Offset offset, {double deadZone = 22}) {
    if (offset.distance < deadZone) return null;
    if (offset.dx.abs() > offset.dy.abs()) {
      return offset.dx > 0 ? AzDialDirection.right : AzDialDirection.left;
    }
    return offset.dy > 0 ? AzDialDirection.down : AzDialDirection.up;
  }

  @override
  State<AzHoldDial> createState() => _AzHoldDialState();
}

class _AzHoldDialState extends State<AzHoldDial> with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  OverlayEntry? _entry;
  Offset _anchor = Offset.zero;
  double _anchorRadius = 32;
  AzDialDirection? _lean;
  bool _persistent = false;

  @override
  void dispose() {
    _removeEntry();
    _open.dispose();
    super.dispose();
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _anchor = box.localToGlobal(box.size.center(Offset.zero));
    _anchorRadius = box.size.shortestSide / 2;
    _lean = null;
    _persistent = false;
    AzamanHaptics.selection();
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
    if (AzMotion.of(context).travel) {
      _open.forward(from: 0);
    } else {
      _open.value = 1;
    }
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _close() {
    if (_entry == null) return;
    if (!mounted || !AzMotion.of(context).travel) {
      _removeEntry();
      return;
    }
    _open.reverse().whenComplete(_removeEntry);
  }

  void _setLean(AzDialDirection? d) {
    if (d == _lean) return;
    _lean = d;
    if (d != null && (widget.actions[d]?.enabled ?? false)) AzamanHaptics.selection();
    _entry?.markNeedsBuild();
  }

  void _select(AzDialDirection d) {
    final action = widget.actions[d];
    if (action == null || !action.enabled) return;
    AzamanHaptics.commit();
    _close();
    action.onSelect!();
  }

  // ── gestures ──────────────────────────────────────────────────────────

  void _onHoldStart(LongPressStartDetails _) => _show();

  void _onHoldMove(LongPressMoveUpdateDetails d) => _setLean(AzHoldDial.leanFor(d.offsetFromOrigin));

  void _onHoldEnd(LongPressEndDetails _) {
    final lean = _lean;
    if (lean != null && (widget.actions[lean]?.enabled ?? false)) {
      _select(lean);
    } else {
      // Released in the centre: stay open for a tap.
      _persistent = true;
      _setLean(null);
      _entry?.markNeedsBuild();
    }
  }

  // ── overlay ───────────────────────────────────────────────────────────

  Offset _chipCentre(AzDialDirection d, Size screen) {
    final r = widget.radius;
    final raw = switch (d) {
      AzDialDirection.up => _anchor + Offset(0, -r),
      AzDialDirection.down => _anchor + Offset(0, r),
      AzDialDirection.left => _anchor + Offset(-r, 0),
      AzDialDirection.right => _anchor + Offset(r, 0),
    };
    const margin = 30.0;
    return Offset(
      raw.dx.clamp(margin, screen.width - margin),
      raw.dy.clamp(margin, screen.height - margin),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF15121A);
    final glass = dark ? const Color(0xE6242228) : const Color(0xF2FFFFFF);
    final screen = MediaQuery.of(overlayContext).size;
    final dimRadius = widget.radius + 64;

    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_open.value);
        return Stack(
          children: [
            // Tap anywhere else closes (persistent mode only blocks taps).
            Positioned.fill(
              child: GestureDetector(
                behavior: _persistent ? HitTestBehavior.opaque : HitTestBehavior.translucent,
                onTap: _persistent ? _close : null,
                child: const SizedBox.expand(),
              ),
            ),
            // The soft radial dim: clear at the anchor, so the avatar stays
            // crisp; fading out well before the screen edges.
            Positioned(
              left: _anchor.dx - dimRadius,
              top: _anchor.dy - dimRadius,
              width: dimRadius * 2,
              height: dimRadius * 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
                          Colors.transparent,
                        ],
                        stops: [_anchorRadius / dimRadius, 0.62, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (final d in AzDialDirection.values)
              if (widget.actions[d] != null) _chip(d, widget.actions[d]!, t, screen, ink, glass),
          ],
        );
      },
    );
  }

  Widget _chip(AzDialDirection d, AzHoldDialAction a, double t, Size screen, Color ink, Color glass) {
    final target = _chipCentre(d, screen);
    final centre = Offset.lerp(_anchor, target, t)!;
    final leaning = _lean == d;
    final showLabel = leaning || _persistent;
    const size = 46.0;
    final scale = (leaning ? 1.14 : 1.0) * (0.6 + 0.4 * t);
    final labelAbove = d == AzDialDirection.up;
    return Positioned(
      left: centre.dx - 70,
      top: centre.dy - size / 2 - (labelAbove ? 26 : 0),
      width: 140,
      child: Opacity(
        opacity: t * (a.enabled ? 1 : 0.38),
        child: GestureDetector(
          onTap: _persistent && a.enabled ? () => _select(d) : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (labelAbove) _label(a.label, showLabel, ink, glass),
              Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: leaning ? ink : glass,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Icon(a.icon, size: 21, color: leaning ? glass.withValues(alpha: 1) : ink),
                ),
              ),
              if (!labelAbove) _label(a.label, showLabel, ink, glass),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, bool show, Color ink, Color glass) => AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: show ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(999)),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final semanticActions = <CustomSemanticsAction, VoidCallback>{
      for (final e in widget.actions.entries)
        if (e.value.enabled) CustomSemanticsAction(label: e.value.label): e.value.onSelect!,
    };
    return Semantics(
      customSemanticsActions: semanticActions,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          if (widget.onTap != null)
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) => r.onTap = widget.onTap,
            ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: widget.holdDuration),
            (r) => r
              ..onLongPressStart = _onHoldStart
              ..onLongPressMoveUpdate = _onHoldMove
              ..onLongPressEnd = _onHoldEnd,
          ),
        },
        child: widget.child,
      ),
    );
  }
}
