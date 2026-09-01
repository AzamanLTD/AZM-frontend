// lib/widgets/book/flip_book_controller.dart
// =============================================================================
// FLIP BOOK CONTROLLER — the state machine between gesture and geometry.
//
// Owns: which leaf is in flight, how far it has turned, where the finger is,
// and the spring that finishes the job when the finger leaves. Emits change
// notifications on the animation ticker only — never setState on the whole
// subtree — so a turn repaints the curl layer and nothing else.
// =============================================================================
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'flip_physics.dart';
import 'page_geometry.dart';

enum FlipState { idle, dragging, settling, hinting }

class FlipBookController extends ChangeNotifier {
  FlipBookController({
    int initialPage = 0,
    this.physics = const FlipPhysics(),
    this.hapticsEnabled = true,
    this.edgeAnchored = false,
  })  : assert(initialPage >= 0),
        _page = initialPage;

  final FlipPhysics physics;
  final bool hapticsEnabled;

  /// Restricts gesture grabs to the horizontal outer edge and keeps the curl
  /// axis stable. Menu-style books therefore turn predictably instead of
  /// allowing top/middle/bottom corner curls.
  final bool edgeAnchored;

  AnimationController? _anim;
  int _pageCount = 0;
  Size _size = Size.zero;

  int _page;
  FlipState _state = FlipState.idle;
  FlipDirection _direction = FlipDirection.forward;
  FlipAnchor _anchor = FlipAnchor.bottomOuter;
  Offset _touch = Offset.zero;
  double _progress = 0.0;
  double _anchorY = 0.0;
  bool _fingerDriven = false;
  bool _crossedThreshold = false;
  int? _pendingSettleTarget;

  int get page => _page;
  int get leafIndex => _direction == FlipDirection.forward ? _page : _page - 1;
  int get underIndex => leafIndex + 1;

  FlipState get state => _state;
  FlipDirection get direction => _direction;
  FlipAnchor get anchor => _anchor;
  double get progress => _progress;
  bool get isTurning => _state != FlipState.idle;

  double get readProgress => _pageCount <= 1 ? 0 : _page / (_pageCount - 1);

  Listenable get repaint => this;

  Offset get touch => _touch;

  Offset get anchorCorner => FlipPath.cornerFor(_anchor, _size);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void attach(TickerProvider vsync) {
    _anim ??= AnimationController.unbounded(vsync: vsync)..addListener(_onTick);
  }

  void updateMetrics({required int pageCount, required Size size}) {
    _pageCount = pageCount;
    if (_size != size) {
      _size = size;
      _anchorY = edgeAnchored ? size.height * 0.5 : size.height * 0.82;
    }
    if (_page > math.max(0, pageCount - 1)) {
      _page = math.max(0, pageCount - 1);
    }
  }

  @override
  void dispose() {
    _anim?.removeListener(_onTick);
    _anim?.dispose();
    _anim = null;
    super.dispose();
  }

  // ── Gesture entry points ───────────────────────────────────────────────────

  bool beginDrag(Offset local, {required bool forward}) {
    if (_size.isEmpty) return false;
    final dir = forward ? FlipDirection.forward : FlipDirection.backward;
    if (!_canTurn(dir)) return false;
    if (edgeAnchored) {
      final edgeThreshold = _size.width * 0.58;
      final validEdge = forward
          ? local.dx >= edgeThreshold
          : local.dx <= _size.width - edgeThreshold;
      if (!validEdge) return false;
    }

    _anim?.stop();
    _direction = dir;
    _anchor = edgeAnchored
        ? FlipAnchor.middleOuter
        : FlipPath.anchorForGrab(local, _size);
    _anchorY = edgeAnchored
        ? _size.height * 0.5
        : FlipPath.cornerFor(_anchor, _size).dy;
    _state = FlipState.dragging;
    _fingerDriven = true;
    _touch = _effectiveTouch(local);
    _progress = FlipPath.progressFor(touch: _touch, size: _size);
    _crossedThreshold = _progress >= 0.5;
    notifyListeners();
    return true;
  }

  Offset _effectiveTouch(Offset local) {
    final clamped = Offset(
      local.dx,
      edgeAnchored
          ? _anchorY
          : local.dy.clamp(-_size.height * 0.35, _size.height * 1.35),
    );
    if (edgeAnchored) return clamped;
    if (_direction == FlipDirection.forward) return clamped;
    final a = FlipPath.cornerFor(_anchor, _size);
    return Offset(clamped.dx * 2 - a.dx, clamped.dy * 2 - a.dy);
  }

  void updateDrag(Offset local) {
    if (_state != FlipState.dragging) return;
    _touch = _effectiveTouch(local);
    _setProgress(FlipPath.progressFor(touch: _touch, size: _size));
  }

  void endDrag(Offset velocityPx) {
    if (_state != FlipState.dragging) return;
    _fingerDriven = false;
    final w = _size.width <= 0 ? 1.0 : _size.width;
    final gain = _direction == FlipDirection.forward ? 2 * w : w;
    final v = -velocityPx.dx / gain;

    final outcome = physics.resolve(_progress, v);
    _anchorY = edgeAnchored
        ? _size.height * 0.5
        : _touch.dy + FlipPath.anchorCompensation(progress: _progress, size: _size);
    _startSettle(outcome == FlipRelease.complete ? 1.0 : 0.0, v);
  }

  void cancelDrag() {
    if (_state != FlipState.dragging) return;
    _fingerDriven = false;
    _anchorY = edgeAnchored
        ? _size.height * 0.5
        : _touch.dy + FlipPath.anchorCompensation(progress: _progress, size: _size);
    _startSettle(_progress >= 0.5 ? 1.0 : 0.0, 0);
  }

  // ── Programmatic turns ─────────────────────────────────────────────────────

  bool turnForward() {
    if (_state == FlipState.dragging || !_canTurn(FlipDirection.forward)) return false;
    _anim?.stop();
    _direction = FlipDirection.forward;
    _anchor = edgeAnchored ? FlipAnchor.middleOuter : FlipAnchor.bottomOuter;
    _anchorY = edgeAnchored ? _size.height * 0.5 : _size.height * 0.86;
    _progress = 0;
    _fingerDriven = false;
    _crossedThreshold = false;
    _startSettle(1.0, 1.4);
    return true;
  }

  bool turnBackward() {
    if (_state == FlipState.dragging || !_canTurn(FlipDirection.backward)) return false;
    _anim?.stop();
    _direction = FlipDirection.backward;
    _anchor = edgeAnchored ? FlipAnchor.middleOuter : FlipAnchor.bottomOuter;
    _anchorY = edgeAnchored ? _size.height * 0.5 : _size.height * 0.86;
    _progress = 1;
    _fingerDriven = false;
    _crossedThreshold = true;
    _startSettle(0.0, -1.4);
    return true;
  }

  void playHint() {
    if (_state != FlipState.idle || !_canTurn(FlipDirection.forward)) return;
    final anim = _anim;
    if (anim == null) return;
    _direction = FlipDirection.forward;
    _anchor = edgeAnchored ? FlipAnchor.middleOuter : FlipAnchor.bottomOuter;
    _anchorY = edgeAnchored ? _size.height * 0.5 : _size.height * 0.92;
    _state = FlipState.hinting;
    _fingerDriven = false;
    _pendingSettleTarget = null;
    anim
      ..value = 0
      ..animateTo(
        0.085,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (_state != FlipState.hinting) return;
        anim
            .animateTo(0.0,
                duration: const Duration(milliseconds: 620), curve: Curves.easeInOutCubic)
            .then((_) {
          if (_state == FlipState.hinting) {
            _state = FlipState.idle;
            _progress = 0;
            notifyListeners();
          }
        });
      });
  }

  void stopHint() {
    if (_state != FlipState.hinting) return;
    _anim?.stop();
    _state = FlipState.idle;
    _progress = 0;
    notifyListeners();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  bool _canTurn(FlipDirection dir) {
    if (_pageCount <= 1) return false;
    return dir == FlipDirection.forward ? _page < _pageCount - 1 : _page > 0;
  }

  void _startSettle(double target, double velocity) {
    final anim = _anim;
    _state = FlipState.settling;
    _pendingSettleTarget = target >= 0.5 ? 1 : 0;
    if (anim == null) {
      _finishSettle();
      return;
    }
    anim.value = _progress;
    final sim = physics.settle(
      progress: _progress,
      velocity: velocity,
      outcome: target >= 0.5 ? FlipRelease.complete : FlipRelease.cancel,
    );
    anim.animateWith(sim).then((_) {
      if (_state == FlipState.settling) _finishSettle();
    });
  }

  void _finishSettle() {
    final completed = _pendingSettleTarget == 1;
    _pendingSettleTarget = null;
    if (_direction == FlipDirection.forward) {
      if (completed) _page = math.min(_page + 1, _pageCount - 1);
    } else {
      if (!completed) _page = math.max(_page - 1, 0);
    }
    _progress = 0;
    _state = FlipState.idle;
    _direction = FlipDirection.forward;
    _crossedThreshold = false;
    notifyListeners();
  }

  void _onTick() {
    if (_state == FlipState.settling || _state == FlipState.hinting) {
      _setProgress((_anim!.value).clamp(0.0, 1.0));
    }
  }

  void _setProgress(double p) {
    if (!_fingerDriven) {
      final nextTouch = FlipPath.touchFor(
        progress: p,
        size: _size,
        anchorY: _anchorY,
      );
      _touch = edgeAnchored
          ? Offset(nextTouch.dx, _anchorY)
          : nextTouch;
    }
    final crossed = p >= 0.5;
    if (crossed != _crossedThreshold && _state != FlipState.hinting) {
      _crossedThreshold = crossed;
      if (hapticsEnabled) HapticFeedback.selectionClick();
    }
    _progress = p;
    notifyListeners();
  }
}
