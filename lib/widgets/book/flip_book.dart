// lib/widgets/book/flip_book.dart
// =============================================================================
// FLIP BOOK — the widget layer.
//
// Composition (bottom → top):
//   ┌ pre-raster slot   fully occluded page kept in the tree only so it can be
//   │                   rasterised before it is needed (zero visual cost)
//   ├ under page        the page revealed beneath the leaf — a *live* widget
//   ├ leaf page         the page on top; live and fully interactive at rest,
//   │                   hidden the instant a turn starts (its raster takes over)
//   ├ book chrome       spine crease + page-block edge (static, own boundary)
//   └ curl layer        CustomPaint that draws the sheet in flight
//
// Why rasterise at all: a turning page has to be sampled as a texture to be
// deformed by drawVertices. Capturing once per turn with
// RenderRepaintBoundary.toImageSync() is a GPU-side copy.
// =============================================================================
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'flip_book_controller.dart';
import 'page_curl_painter.dart';
import 'page_geometry.dart';
import 'flip_physics.dart';

class FlipBook extends StatefulWidget {
  const FlipBook({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    this.controller,
    this.material = const BookMaterial(),
    this.physics = const FlipPhysics(),
    this.onPageChanged,
    this.idleHint = true,
    this.idleHintDelay = const Duration(seconds: 4),
    this.hapticsEnabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final int pageCount;
  final IndexedWidgetBuilder pageBuilder;
  final FlipBookController? controller;
  final BookMaterial material;
  final FlipPhysics physics;
  final ValueChanged<int>? onPageChanged;

  final bool idleHint;
  final Duration idleHintDelay;
  final bool hapticsEnabled;
  final BorderRadius borderRadius;

  @override
  State<FlipBook> createState() => FlipBookState();
}

class FlipBookState extends State<FlipBook> with SingleTickerProviderStateMixin {
  late FlipBookController _controller;
  bool _ownsController = false;

  final GlobalKey _leafKey = GlobalKey();
  final GlobalKey _prerasterKey = GlobalKey();

  ui.Image? _leafTexture;
  ui.Image? _previousTexture;
  int _previousTextureIndex = -1;
  int? _prerasterIndex;

  final PageCurlSolver _solver = PageCurlSolver();
  final LeafFrame _frame = LeafFrame();
  Size _size = Size.zero;
  int _lastPage = 0;
  bool _turning = false;

  Timer? _idleTimer;
  DateTime _lastInteraction = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        FlipBookController(physics: widget.physics, hapticsEnabled: widget.hapticsEnabled);
    _ownsController = widget.controller == null;
    _controller
      ..attach(this)
      ..addListener(_onControllerTick);
    _lastPage = _controller.page;
    if (widget.idleHint) {
      _idleTimer = Timer.periodic(const Duration(milliseconds: 900), _onIdleTick);
    }
  }

  @override
  void didUpdateWidget(covariant FlipBook oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.controller != widget.controller && widget.controller != null) {
      _controller.removeListener(_onControllerTick);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller!
        ..attach(this)
        ..addListener(_onControllerTick);
      _ownsController = false;
    }
    if (old.pageCount != widget.pageCount) {
      _dropTextures();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _controller.removeListener(_onControllerTick);
    if (_ownsController) _controller.dispose();
    _frame.dispose();
    _dropTextures();
    super.dispose();
  }

  void _dropTextures() {
    _leafTexture?.dispose();
    _leafTexture = null;
    _previousTexture?.dispose();
    _previousTexture = null;
    _previousTextureIndex = -1;
  }

  // ── Rasterisation ──────────────────────────────────────────────────────────

  ui.Image? _capture(GlobalKey key) {
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final boundary = obj;
    if (!boundary.attached || !boundary.hasSize || boundary.size.isEmpty) return null;
    final dpr = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0).clamp(1.0, 2.0);
    try {
      return boundary.toImageSync(pixelRatio: dpr);
    } catch (_) {
      return null;
    }
  }

  void _prepareTexture(int leafIndex) {
    if (leafIndex == _previousTextureIndex && _previousTexture != null) {
      _leafTexture?.dispose();
      _leafTexture = _previousTexture;
      _previousTexture = null;
      _previousTextureIndex = -1;
      return;
    }
    final img = _capture(leafIndex == _controller.page ? _leafKey : _prerasterKey);
    if (img != null) {
      _leafTexture?.dispose();
      _leafTexture = img;
    }
  }

  // ── Controller / idle plumbing ─────────────────────────────────────────────

  void _onControllerTick() {
    final turning = _controller.isTurning;
    final pageChanged = _controller.page != _lastPage;

    if (turning != _turning || pageChanged) {
      if (pageChanged) {
        _previousTexture?.dispose();
        _previousTexture = _leafTexture;
        _previousTextureIndex = _lastPage;
        _leafTexture = null;
        _lastPage = _controller.page;
        widget.onPageChanged?.call(_lastPage);
      }
      _turning = turning;
      if (!turning) _prerasterIndex = null;
      _solve();
      if (mounted) setState(() {});
      return;
    }
    _solve();
  }

  void _solve() {
    if (_size.isEmpty || !_controller.isTurning) {
      _frame.commit(texture: _leafTexture, geometry: null, progress: 0);
      return;
    }
    final tex = _leafTexture;
    _frame.commit(
      texture: tex,
      geometry: _solver.solve(
        pageRect: Offset.zero & _size,
        anchorCorner: _controller.anchorCorner,
        touch: _controller.touch,
        textureSize:
            tex == null ? _size : Size(tex.width.toDouble(), tex.height.toDouble()),
      ),
      progress: _controller.progress,
    );
  }

  void _onIdleTick(Timer _) {
    if (!widget.idleHint || !mounted) return;
    if (_controller.isTurning) {
      _lastInteraction = DateTime.now();
      return;
    }
    if (DateTime.now().difference(_lastInteraction) >= widget.idleHintDelay) {
      _lastInteraction = DateTime.now();
      if (_controller.page < widget.pageCount - 1) {
        _prepareTexture(_controller.page);
        _controller.playHint();
      }
    }
  }

  void _markInteraction() {
    _lastInteraction = DateTime.now();
    if (_controller.state == FlipState.hinting) _controller.stopHint();
  }

  // ── Gestures ───────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    _markInteraction();
    final local = d.localPosition;
    final forward = local.dx > _size.width * 0.22;
    final leafIndex = forward ? _controller.page : _controller.page - 1;
    if (leafIndex < 0 || leafIndex >= widget.pageCount) return;
    _prepareTexture(leafIndex);
    if (_leafTexture == null && leafIndex != _controller.page) {
      setState(() => _prerasterIndex = leafIndex);
    }
    _controller.beginDrag(local, forward: forward);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_leafTexture == null && _prerasterIndex != null) {
      _prepareTexture(_prerasterIndex!);
    }
    _controller.updateDrag(d.localPosition);
  }

  void _onDragEnd(DragEndDetails d) {
    _controller.endDrag(Offset(d.velocity.pixelsPerSecond.dx, 0));
  }

  void _onDragCancel() => _controller.cancelDrag();

  /// Public API for host widgets (arrow buttons, keyboard shortcuts).
  void turnForward() {
    _markInteraction();
    _prepareTexture(_controller.page);
    _controller.turnForward();
  }

  void turnBackward() {
    _markInteraction();
    final target = _controller.page - 1;
    if (target < 0) return;
    _prepareTexture(target);
    if (_leafTexture == null) setState(() => _prerasterIndex = target);
    _controller.turnBackward();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _size) {
          _size = size;
          _dropTextures();
        }
        _controller.updateMetrics(pageCount: widget.pageCount, size: size);

        final page = _controller.page;
        final leaf = _controller.leafIndex;
        final under = _controller.isTurning ? _controller.underIndex : page + 1;

        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Occluded pre-raster slot.
                if (_prerasterIndex != null &&
                    _prerasterIndex! >= 0 &&
                    _prerasterIndex! < widget.pageCount)
                  IgnorePointer(
                    child: RepaintBoundary(
                      key: _prerasterKey,
                      child: widget.pageBuilder(context, _prerasterIndex!),
                    ),
                  ),

                // Under page — revealed beneath the leaf during a turn.
                if (under >= 0 && under < widget.pageCount)
                  IgnorePointer(
                    ignoring: _turning,
                    child: RepaintBoundary(
                      child: widget.pageBuilder(context, under),
                    ),
                  ),

                // The leaf — live and interactive at rest.
                if (leaf >= 0 && leaf < widget.pageCount)
                  Visibility(
                    visible: !_turning,
                    maintainState: true,
                    maintainSize: true,
                    maintainAnimation: true,
                    child: IgnorePointer(
                      ignoring: _turning,
                      child: RepaintBoundary(
                        key: _leafKey,
                        child: widget.pageBuilder(context, leaf),
                      ),
                    ),
                  ),

                // Static book chrome.
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BookChromePainter(
                        material: widget.material,
                        readProgress: _controller.readProgress,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),

                // The sheet in flight.
                if (_turning)
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: PageCurlPainter(
                          frame: _frame,
                          material: widget.material,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Convenience wrapper: constrains the book to a page aspect ratio and centres it.
class FlipBookFrame extends StatelessWidget {
  const FlipBookFrame({
    super.key,
    required this.child,
    this.aspectRatio = 0.68,
    this.maxWidth = 460,
  });

  final Widget child;
  final double aspectRatio;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(aspectRatio: aspectRatio, child: child),
      ),
    );
  }
}
