// =============================================================================
// AZAMAN — STORY VIEWER: GESTURE ARBITER
//
// ONE Listener-based state machine deciding tap / hold / horizontal /
// vertical / pinch (Overhaul 05 §2). The PageView itself is
// NeverScrollable so it can never win a gesture on its own; horizontal pans
// are forwarded through ScrollPosition.drag and the parent PageScrollPhysics
// still supplies the page snap on release.
//
// No Timer: the hold delay is a Ticker owned (and disposed) here.
// =============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

enum StoryGesturePhase { idle, deciding, horizontal, vertical, pinch, holding }

class StoryGestureCallbacks {
  /// Tap in the right (true) or left (false) zone.
  final ValueChanged<bool> onTap;

  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  /// Vertical drag delta in px, +down / -up.
  final ValueChanged<double> onVerticalUpdate;

  /// Vertical drag ended; velocity is px/s, +down.
  final ValueChanged<double> onVerticalEnd;

  /// Absolute pinch scale (caller clamps to its own range).
  final ValueChanged<double> onPinchScale;
  final VoidCallback onPinchEnd;

  const StoryGestureCallbacks({
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onVerticalUpdate,
    required this.onVerticalEnd,
    required this.onPinchScale,
    required this.onPinchEnd,
  });
}

class StoryGestureArbiter extends StatefulWidget {
  const StoryGestureArbiter({
    super.key,
    required this.child,
    required this.pageController,
    required this.callbacks,
    this.slop = kTouchSlop,
    this.holdDelay = const Duration(milliseconds: 350),
  });

  final Widget child;
  final PageController pageController;
  final StoryGestureCallbacks callbacks;
  final double slop;
  final Duration holdDelay;

  @override
  State<StoryGestureArbiter> createState() => _StoryGestureArbiterState();
}

class _StoryGestureArbiterState extends State<StoryGestureArbiter>
    with SingleTickerProviderStateMixin {
  StoryGesturePhase _phase = StoryGesturePhase.idle;
  final Map<int, Offset> _pointers = {};
  Offset? _origin;
  Duration? _downTime;
  Drag? _pageDrag;
  VelocityTracker? _velocity;
  double _pinchBase = 0;
  late final Ticker _holdTicker;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _holdTicker = createTicker(_onHoldTick);
  }

  void _onHoldTick(Duration elapsed) {
    if (_phase == StoryGesturePhase.deciding &&
        elapsed >= widget.holdDelay) {
      _holdTicker.stop();
      _phase = StoryGesturePhase.holding;
      widget.callbacks.onHoldStart();
    }
  }

  double _pointerDistance() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 1) {
      _origin = e.position;
      _downTime = e.timeStamp;
      _velocity =
          VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
      _phase = StoryGesturePhase.deciding;
      _holdTicker.start();
    } else if (_pointers.length == 2 &&
        (_phase == StoryGesturePhase.deciding ||
            _phase == StoryGesturePhase.holding ||
            _phase == StoryGesturePhase.vertical)) {
      _holdTicker.stop();
      if (_phase == StoryGesturePhase.holding) widget.callbacks.onHoldEnd();
      _phase = StoryGesturePhase.pinch;
      _pinchBase = _pointerDistance();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    _velocity?.addPosition(e.timeStamp, e.position);
    switch (_phase) {
      case StoryGesturePhase.deciding:
        final d = e.position - _origin!;
        if (d.distance < widget.slop) return;
        _holdTicker.stop();
        if (d.dx.abs() > d.dy.abs()) {
          _phase = StoryGesturePhase.horizontal;
          _pageDrag = widget.pageController.position.drag(
            DragStartDetails(globalPosition: e.position),
            () => _pageDrag = null,
          );
        } else {
          _phase = StoryGesturePhase.vertical;
        }
        _move(e); // apply this delta through the chosen phase
      case StoryGesturePhase.horizontal:
        _pageDrag?.update(DragUpdateDetails(
          globalPosition: e.position,
          delta: Offset(e.delta.dx, 0),
          primaryDelta: e.delta.dx,
        ));
      case StoryGesturePhase.vertical:
        widget.callbacks.onVerticalUpdate(e.delta.dy);
      case StoryGesturePhase.pinch:
        if (_pointers.length == 2 && _pinchBase > 0) {
          widget.callbacks.onPinchScale(_pointerDistance() / _pinchBase);
        }
      case StoryGesturePhase.holding:
        // Finger drift keeps the hold (Instagram behaviour); a large move
        // ends it and hands the gesture to the vertical channel.
        if ((e.position - _origin!).distance > widget.slop * 3) {
          widget.callbacks.onHoldEnd();
          _phase = StoryGesturePhase.vertical;
        }
      case StoryGesturePhase.idle:
        break;
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    final velocity =
        _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    switch (_phase) {
      case StoryGesturePhase.deciding:
        _holdTicker.stop();
        final isTap =
            (e.timeStamp - (_downTime ?? e.timeStamp)) < widget.holdDelay;
        if (isTap && _origin != null) {
          widget.callbacks.onTap(_origin!.dx > _width * 0.35);
        }
      case StoryGesturePhase.holding:
        widget.callbacks.onHoldEnd();
      case StoryGesturePhase.horizontal:
        _pageDrag?.end(DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(velocity.dx, 0)),
          primaryVelocity: velocity.dx,
        ));
        _pageDrag = null;
      case StoryGesturePhase.vertical:
        widget.callbacks.onVerticalEnd(velocity.dy);
      case StoryGesturePhase.pinch:
        if (_pointers.isEmpty) {
          widget.callbacks.onPinchEnd();
        } else {
          return; // one finger still down: stay in pinch, no accidental flips
        }
      case StoryGesturePhase.idle:
        break;
    }
    if (_pointers.isEmpty) {
      _phase = StoryGesturePhase.idle;
      _origin = null;
      _downTime = null;
      _velocity = null;
    }
  }

  @override
  void dispose() {
    _holdTicker.dispose();
    _pageDrag?.cancel();
    _pageDrag = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _width = MediaQuery.sizeOf(context).width;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
