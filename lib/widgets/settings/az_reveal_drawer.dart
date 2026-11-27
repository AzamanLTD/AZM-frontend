// lib/widgets/settings/az_reveal_drawer.dart
// =============================================================================
// THE REVEAL DRAWER — the page moves, the drawer was always there.
//
// The settings drawer no longer slides OVER the app. It lives underneath, on
// the right, and the whole app (page + bottom nav) slides left to reveal it,
// rounding its corners and dimming as it goes. Tapping or dragging the
// slid-away page brings it back; so does system back.
//
//   closed                         open
//   ┌──────────────┐              ┌────┐┌──────────────┐
//   │   the app    │      →       │app ││   drawer     │
//   │              │              │dim ││  (was here)  │
//   └──────────────┘              └────┘└──────────────┘
//
// Gestures: drag from the right edge to open (the drawer follows the finger),
// drag the page right or tap it to close, fling either way. Reduced motion
// snaps instead of travelling.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:azaman/theme/az_motion.dart';

/// Opens and closes an [AzRevealDrawer] from anywhere that holds it.
class AzRevealDrawerController extends ChangeNotifier {
  _AzRevealDrawerState? _state;

  bool get isOpen => _state?._isOpen ?? false;

  void open() => _state?._animateTo(1);
  void close() => _state?._animateTo(0);
  void toggle() => isOpen ? close() : open();

  void _changed() => notifyListeners();
}

/// Lets anything inside the drawer close it (a row that navigates should
/// close the drawer first, never pop a route).
class AzRevealDrawerScope extends InheritedWidget {
  const AzRevealDrawerScope({super.key, required this.close, required super.child});

  final VoidCallback close;

  static AzRevealDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AzRevealDrawerScope>();

  @override
  bool updateShouldNotify(AzRevealDrawerScope old) => false;
}

class AzRevealDrawer extends StatefulWidget {
  const AzRevealDrawer({
    super.key,
    required this.controller,
    required this.drawer,
    required this.child,
    this.edgeDragWidth = 20,
    this.enabled = true,
  });

  final AzRevealDrawerController controller;
  final Widget drawer;
  final Widget child;

  /// Width of the right-edge strip that starts an opening drag.
  final double edgeDragWidth;

  /// When false (e.g. the + launcher owns the screen) the edge drag is off.
  final bool enabled;

  @override
  State<AzRevealDrawer> createState() => _AzRevealDrawerState();
}

class _AzRevealDrawerState extends State<AzRevealDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  double _drawerWidth = 320;

  bool get _isOpen => _t.value > 0.5 || (_t.isAnimating && _t.velocity > 0);

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(AzRevealDrawer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _t.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    if (!mounted) return;
    final opening = target > _t.value;
    if (opening && _t.value < 0.05) HapticFeedback.lightImpact();
    final travel = AzMotion.of(context).travel;
    if (!travel) {
      _t.value = target;
    } else {
      _t.animateTo(
        target,
        duration: Duration(milliseconds: (380 * (target - _t.value).abs()).clamp(140, 380).round()),
        curve: opening ? Curves.easeOutCubic : Curves.easeInOutCubic,
      );
    }
    widget.controller._changed();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Dragging LEFT opens (the page travels left with the finger).
    _t.value = (_t.value - d.primaryDelta! / _drawerWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -350) {
      _animateTo(1);
    } else if (v > 350) {
      _animateTo(0);
    } else {
      _animateTo(_t.value > 0.5 ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _drawerWidth = math.min(box.maxWidth * 0.84, 360.0);
      final radius = MediaQuery.of(context).size.width > 0 ? 30.0 : 0.0;
      return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            final shown = t > 0;
            // Inside the builder so canPop tracks the drawer as it moves:
            // while it shows, system back closes it instead of leaving.
            return PopScope(
              canPop: !shown,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _animateTo(0);
              },
              child: Stack(
              fit: StackFit.expand,
              children: [
                // The drawer, underneath. A slight parallax: it starts a
                // quarter-width in and settles as the page clears it.
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: _drawerWidth,
                  child: Offstage(
                    offstage: !shown,
                    child: TickerMode(
                      enabled: shown,
                      child: Transform.translate(
                        offset: Offset(_drawerWidth * 0.22 * (1 - t), 0),
                        child: AzRevealDrawerScope(
                          close: () => _animateTo(0),
                          child: widget.drawer,
                        ),
                      ),
                    ),
                  ),
                ),

                // The app, travelling left.
                Transform.translate(
                  offset: Offset(-_drawerWidth * t, 0),
                  child: DecoratedBox(
                    // On a dark theme the slid page would vanish into the black
                    // drawer: a faint hairline keeps its edge readable.
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius * t),
                      border: shown && Theme.of(context).brightness == Brightness.dark
                          ? Border.all(color: Colors.white.withValues(alpha: 0.12 * t), width: 0.8)
                          : null,
                      boxShadow: shown
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28 * t),
                                blurRadius: 32,
                                offset: const Offset(-6, 0),
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius * t),
                      clipBehavior: shown ? Clip.antiAlias : Clip.none,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeSemantics(excluding: t >= 1, child: widget.child),
                          if (shown)
                            Positioned.fill(
                              child: Semantics(
                                button: true,
                                label: 'Close menu',
                                child: GestureDetector(
                                  key: const ValueKey('reveal-drawer-scrim'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _animateTo(0),
                                  onHorizontalDragUpdate: _onDragUpdate,
                                  onHorizontalDragEnd: _onDragEnd,
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.32 * t),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // The opening edge: a thin strip on the right of the closed
                // page that hands the drag to the drawer.
                if (!shown && widget.enabled)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: widget.edgeDragWidth,
                    child: GestureDetector(
                      key: const ValueKey('reveal-drawer-edge'),
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                    ),
                  ),
              ],
            ),
            );
          },
      );
    });
  }
}
