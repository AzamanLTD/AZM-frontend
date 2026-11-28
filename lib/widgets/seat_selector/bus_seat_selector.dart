// =============================================================================
// AZAMAN — BUS SEAT SELECTOR (Main Widget)
//
// The main interactive widget: InteractiveViewer wrapping the canvas,
// deck switcher (if multi-deck), floating minimap, status legend, and
// sticky checkout dock.
//
// Architecture:
//   - InteractiveViewer provides raw pinch/pan/zoom — no hand-rolled gestures.
//   - CustomPainter draws via `repaint: Listenable` (the controller), not
//     via setState — zero parent rebuilds during pan/zoom/selection.
//   - SVG seat icons are decoded once on init and cached as ui.Picture objects.
//   - Auto-fit animates the TransformationController on layout load.
//   - Seat tap animates the viewport to center/zoom on the tapped seat.
// =============================================================================

import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/models/marketplace_booking_models.dart' as booking;
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

import 'seat_layout_models.dart';
import 'seat_geometry_solver.dart';
import 'seat_canvas_painter.dart';
import 'seat_selector_controller.dart';
export 'seat_selector_controller.dart' show SeatSelectorController;
export 'seat_canvas_painter.dart'
    show CabinLighting, SeatPalette, SeatLook, SeatGlyphPainter;
import 'seat_semantics_overlay.dart';

/// The main seat selector widget.
///
/// Usage:
/// ```dart
/// BusSeatSelector(
///   layout: vehicleLayout,
///   controller: myController,
///   onSelectionChanged: (seats) => print('Selected: $seats'),
/// )
/// ```
class BusSeatSelector extends StatefulWidget {
  /// The vehicle layout to render.
  final VehicleLayout? layout;

  /// Controller managing selection state and transform.
  final SeatSelectorController? controller;

  /// Called when the selection set changes.
  final void Function(Set<String> selectedSeats)? onSelectionChanged;

  /// Color scheme — typically from AzamanColors.
  final Color accentColor;
  final Color surfaceColor;
  final Color cardColor;
  final Color dividerColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color successColor;
  final Color dangerColor;
  final Color backgroundColor;

  /// Whether to show the floating minimap.
  final bool showMinimap;

  /// Whether to show the status legend.
  final bool showLegend;

  /// Whether to show the sticky checkout dock.
  final bool showCheckoutDock;

  /// Called when the user taps "Book Now" in the checkout dock.
  final void Function(Set<String> selectedSeats, double totalFare)? onBook;

  /// Whether booking is in progress (disables the Book button).
  final bool isBooking;

  /// Cabin lighting overlay; null keeps legacy rendering.
  final CabinLighting? cabinLighting;

  /// The smallest scale the opening fit may use. The vehicle is drawn top to
  /// bottom; when it is taller than the view at this scale it opens at the
  /// cab (the front) and scrolls down, instead of opening mid-vehicle.
  final double minFitScale;

  const BusSeatSelector({
    super.key,
    required this.layout,
    this.controller,
    this.onSelectionChanged,
    required this.accentColor,
    required this.surfaceColor,
    required this.cardColor,
    required this.dividerColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.successColor,
    required this.dangerColor,
    required this.backgroundColor,
    this.showMinimap = true,
    this.showLegend = true,
    this.showCheckoutDock = true,
    this.onBook,
    this.isBooking = false,
    this.cabinLighting,
    this.minFitScale = 0.8,
  });

  @override
  State<BusSeatSelector> createState() => _BusSeatSelectorState();
}

class _BusSeatSelectorState extends State<BusSeatSelector>
    with TickerProviderStateMixin {
  late SeatSelectorController _controller;

  // Animation controller for the selection pulse ring
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Animation controller for the auto-fit / center-on-seat zoom
  late AnimationController _fitController;

  // Previous total for animated digit-roll
  double _previousTotal = 0;

  // Timestamp of the last seat-tap-driven fit animation, to guard against
  // auto-fit racing with center-on-seat animations.
  DateTime? _lastSeatTapFit;
  double _autoFitScale = 1.0;
  double _currentZoomScale = 1.0;

  /// The canvas viewport (the area between the deck switcher and the
  /// legend), measured by a LayoutBuilder. The fit and the reveal use it,
  /// never the whole widget, whose height includes the legend and dock.
  Size? _viewport;

  /// The passenger panned or zoomed; viewport changes then leave their view
  /// alone instead of refitting.
  bool _userMoved = false;

  /// The seat most recently selected: a refit keeps it in view.
  String? _focusSeat;

  // One-shot controller for the vertical deck-slice transition.
  late final AnimationController _deckSliceController;
  late Animation<double> _deckSliceAnimation;

  /// Direction of the incoming deck: negative = entering from above.
  double _deckSliceOffset = 1.0;
  int? _previousDeck;
  bool _deckSliceReady = false;

  @override
  void initState() {
    super.initState();

    _controller =
        widget.controller ?? SeatSelectorController(selectionLimit: 0);

    // Pulse animation for selected-seat rings
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Auto-fit animation controller (reused for each zoom transition)
    _fitController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    // Load layout if provided
    if (widget.layout != null) {
      _controller.loadLayout(widget.layout!);
      _scheduleAutoFit();
    }

    _controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion reads MediaQuery, so the slice controller's duration
    // is resolved here — never from initState (corrigendum 2.2).
    final duration = MotionTokens.accessibleDuration(
      context,
      const Duration(milliseconds: 420),
    );
    if (!_deckSliceReady) {
      _deckSliceReady = true;
      // One-shot; pinned at 1.0 when idle so the canvas renders
      // un-transformed between deck changes.
      _deckSliceController = AnimationController(
        duration: duration,
        vsync: this,
      )..value = 1.0;
      _deckSliceAnimation = CurvedAnimation(
        parent: _deckSliceController,
        curve: MotionTokens.enter,
      );
    } else if (_deckSliceController.duration != duration) {
      // Dependency change updates the duration without replaying the slice.
      _deckSliceController.duration = duration;
    }
  }

  @override
  void didUpdateWidget(BusSeatSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layout != oldWidget.layout && widget.layout != null) {
      _controller.loadLayout(widget.layout!);
      _userMoved = false;
      _scheduleAutoFit();
    }
  }

  void _onControllerChanged() {
    final currentDeck = _controller.currentDeck;
    final previousDeck = _previousDeck;
    if (previousDeck != null && currentDeck != previousDeck) {
      // Entering from above when moving to an upper (lower-index) deck.
      _deckSliceOffset = currentDeck < previousDeck ? -1.0 : 1.0;
      _deckSliceController.forward(from: 0);
    }
    _previousDeck = currentDeck;

    final currentTotal = _controller.totalFare;
    if (currentTotal != _previousTotal) {
      // The TweenAnimationBuilder in the checkout dock handles the visual
      _previousTotal = currentTotal;
    }
    widget.onSelectionChanged?.call(_controller.selectedSeats);
    setState(() {}); // Rebuild for dock/legend updates
  }

  void _scheduleAutoFit({bool force = false}) {
    final geometry = _controller.geometry;
    if (geometry == null) return;

    // Skip auto-fit if a seat-tap-driven center animation is in flight
    // (within the last 300ms), to prevent the viewport from snapping back
    // to full-vehicle fit view between rapid seat taps. A viewport change
    // forces the fit: it keeps the tapped seat in view itself.
    if (!force &&
        _lastSeatTapFit != null &&
        DateTime.now().difference(_lastSeatTapFit!) <
            const Duration(milliseconds: 300) &&
        _fitController.isAnimating) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFit(geometry.totalBounds);
    });
  }

  Size? _viewportSize() {
    if (!mounted) return null;
    if (_viewport != null) return _viewport;
    final renderBox = context.findRenderObject() as RenderBox?;
    return renderBox?.hasSize == true ? renderBox!.size : null;
  }

  void _autoFit(Rect bounds) {
    final viewportSize = _viewportSize();
    if (viewportSize == null || viewportSize.isEmpty || bounds.isEmpty) {
      return;
    }

    // Fit the whole vehicle when it fits at a readable scale. A long one
    // fits its width instead and opens at the cab, so the first thing a
    // passenger sees is the front, the driver and the door.
    const padding = 16.0;
    final scaleX = (viewportSize.width - padding * 2) / bounds.width;
    final scaleY = (viewportSize.height - padding * 2) / bounds.height;
    final fitAll = math.min(scaleX, scaleY);
    final clampedScale =
        (fitAll >= widget.minFitScale ? fitAll : math.min(scaleX, 1.0))
            .clamp(widget.minFitScale, 1.5)
            .toDouble();
    _autoFitScale = clampedScale;
    _currentZoomScale = clampedScale;

    final offsetX =
        (viewportSize.width - bounds.width * clampedScale) / 2 -
        bounds.left * clampedScale;
    final fitsTall = bounds.height * clampedScale <= viewportSize.height;
    var offsetY = fitsTall
        ? (viewportSize.height - bounds.height * clampedScale) / 2 -
              bounds.top * clampedScale
        : padding - bounds.top * clampedScale;

    // Keep the passenger's latest seat in view through a refit (the dock
    // appearing shrinks the viewport).
    final focus = _focusSeat == null
        ? null
        : _controller.geometry?.rectForSeat(_focusSeat!)?.visualRect;
    if (!fitsTall && focus != null) {
      const margin = 12.0;
      final bottom = focus.bottom * clampedScale + offsetY;
      if (bottom > viewportSize.height - margin) {
        offsetY -= bottom - (viewportSize.height - margin);
      }
    }

    // ignore: deprecated_member_use
    final targetMatrix = Matrix4.identity()
      // ignore: deprecated_member_use
      ..translate(offsetX, offsetY)
      // ignore: deprecated_member_use
      ..scale(clampedScale);

    // Animate with spring-like curve
    final currentMatrix = _controller.transformController.value.clone();
    _animateMatrix(currentMatrix, targetMatrix);
  }

  Animation<Matrix4>? _fitAnimation;

  void _animateMatrix(Matrix4 from, Matrix4 to) {
    // Reuse the single _fitController instead of creating new ones
    _fitController.stop();
    _fitController.value = 0.0;

    final tween = Matrix4Tween(begin: from, end: to);
    _fitAnimation = tween.animate(
      CurvedAnimation(parent: _fitController, curve: Curves.easeOutBack),
    );

    _fitController.removeListener(_applyFitAnimation);
    _fitController.addListener(_applyFitAnimation);

    _fitController.forward();
  }

  void _applyFitAnimation() {
    if (mounted && _fitAnimation != null) {
      _controller.transformController.value = _fitAnimation!.value;
    }
  }

  void _onSeatTap(String seatId) {
    final wasSelected = _controller.selectedSeats.contains(seatId);
    final success = _controller.toggleSeat(seatId);
    if (success) {
      _focusSeat = wasSelected
          ? (_focusSeat == seatId ? null : _focusSeat)
          : seatId;
      if (wasSelected) {
        // Deselect: a soft click, not a rung of the ascending ladder.
        AzamanHaptics.selection();
      } else {
        // The tapped seat is now the last of the selection; the 0-based
        // index drives TASK-006's rising-intensity ladder.
        AzamanHaptics.seatSelected(_controller.selectedSeats.length - 1);
      }

      // Keep the tapped seat in view (no zoom)
      final geometry = _controller.geometry;
      if (geometry != null) {
        final slotRect = geometry.rectForSeat(seatId);
        if (slotRect != null) {
          _revealRect(slotRect.visualRect);
        }
      }
    }
  }

  void _revealRect(Rect rect) {
    final viewportSize = _viewportSize();
    if (viewportSize == null || viewportSize.isEmpty) return;
    _lastSeatTapFit = DateTime.now();

    // Keep the passenger's view: no zoom on a tap. Only when the seat is
    // partly out of view does the vehicle slide (vertically) to show it.
    final current = _controller.transformController.value;
    final scale = current.getMaxScaleOnAxis();
    final t = current.getTranslation();
    final top = rect.top * scale + t.y;
    final bottom = rect.bottom * scale + t.y;
    const margin = 12.0;
    if (top >= margin && bottom <= viewportSize.height - margin) return;
    final dy = top < margin
        ? margin - top
        : (viewportSize.height - margin) - bottom;

    final targetMatrix = current.clone()
      // ignore: deprecated_member_use
      ..translate(0.0, dy / scale);

    _animateMatrix(current, targetMatrix);
  }

  @override
  void dispose() {
    _fitController.removeListener(_applyFitAnimation);
    _fitController.dispose();
    _pulseController.dispose();
    if (_deckSliceReady) {
      _deckSliceController.dispose();
    }
    _controller.removeListener(_onControllerChanged);
    // Only dispose if we created it internally
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _controller.geometry;
    if (geometry == null) {
      return Center(
        child: CircularProgressIndicator(color: widget.accentColor),
      );
    }

    final hullStyle = HullStyle(
      bodyColor: widget.cardColor.withValues(alpha: 0.35),
      borderColor: widget.dividerColor.withValues(alpha: 0.35),
    );
    final palette = _palette();

    return Column(
      children: [
        // ── Deck switcher (if multi-deck) ──────────────────────────────
        if (widget.layout!.isMultiDeck) _buildDeckSwitcher(),

        // ── Main canvas + minimap ───────────────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              if (_viewport != size) {
                final hadViewport = _viewport != null;
                _viewport = size;
                // The viewport changed under an untouched view (the booking
                // dock arrived, the sheet resized): refit to it.
                if (hadViewport && !_userMoved) _scheduleAutoFit(force: true);
              }
              return _canvas(geometry, hullStyle, palette);
            },
          ),
        ),

        // ── Status legend ──────────────────────────────────────────────
        if (widget.showLegend) _buildLegend(),

        // ── Sticky checkout dock ────────────────────────────────────────
        if (widget.showCheckoutDock) _buildCheckoutDock(),
      ],
    );
  }

  Widget _canvas(
    ComputedGeometry geometry,
    HullStyle hullStyle,
    SeatPalette palette,
  ) {
    return Stack(
      children: [
        // Vertical deck slice: the canvas (not the floating minimap)
        // enters as a slice with perspective when the deck changes.
        // AnimatedSwitcher is deliberately NOT used here — two live
        // InteractiveViewers would share one TransformationController
        // and trip the framework's "already attached" assertion.
        AnimatedBuilder(
          animation: _deckSliceAnimation,
          builder: (context, child) {
            final t = _deckSliceAnimation.value;
            if (t >= 1.0) return child!;
            return Opacity(
              opacity: 0.45 + 0.55 * t,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012) // perspective
                  ..rotateX(_deckSliceOffset * 0.10 * (1 - t)),
                child: FractionalTranslation(
                  translation: Offset(0, _deckSliceOffset * 0.12 * (1 - t)),
                  child: child,
                ),
              ),
            );
          },
          child: InteractiveViewer(
            transformationController: _controller.transformController,
            constrained: false,
            minScale: math.min(0.8, widget.minFitScale),
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(80),
            onInteractionUpdate: (details) {
              // A real pan or pinch (a seat tap is neither): the passenger
              // owns the view from here.
              if (details.focalPointDelta != Offset.zero ||
                  details.scale != 1.0) {
                _userMoved = true;
              }
              _currentZoomScale = _controller.transformController.value
                  .getMaxScaleOnAxis();
              setState(() {});
            },
            child: SizedBox(
              width: geometry.totalBounds.width,
              height: geometry.totalBounds.height,
              child: Stack(
                children: [
                  // Canvas painter
                  CustomPaint(
                    size: Size(
                      geometry.totalBounds.width,
                      geometry.totalBounds.height,
                    ),
                    painter: SeatCanvasPainter(
                      geometry: geometry,
                      iconCache: const SeatIconCache(),
                      palette: palette,
                      fontFamily: AzText.uiFamily,
                      selectedSeats: _controller.selectedSeats,
                      hullStyle: hullStyle,
                      accentColor: widget.accentColor,
                      selectionPulse: _pulseAnimation.value,
                      currentDeck: _controller.currentDeck,
                      cabinLighting: widget.cabinLighting,
                      repaint: Listenable.merge([_controller, _pulseAnimation]),
                    ),
                  ),
                  // Semantics overlay
                  SeatSemanticsOverlay(
                    geometry: geometry,
                    selectedSeats: _controller.selectedSeats,
                    currentDeck: _controller.currentDeck,
                    onSeatTap: _onSeatTap,
                    viewportWidth: geometry.totalBounds.width,
                    viewportHeight: geometry.totalBounds.height,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Floating minimap (top-right) — only show when zoomed in
        // past the auto-fit overview, so it doesn't overlap seats at full view.
        if (widget.showMinimap && _currentZoomScale > _autoFitScale * 1.15)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildMinimap(geometry, hullStyle),
            ),
          ),
      ],
    );
  }

  Widget _buildDeckSwitcher() {
    final decks = widget.layout!.decks;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: widget.surfaceColor,
      child: Row(
        children: [
          Text(
            'Deck',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          ...decks.map((deck) {
            final isSelected = deck.deckIndex == _controller.currentDeck;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  AzamanHaptics.selection();
                  _controller.setDeck(deck.deckIndex);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? widget.accentColor : widget.cardColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    deck.label ?? 'Deck ${deck.deckIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? widget.backgroundColor
                          : widget.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMinimap(ComputedGeometry geometry, HullStyle hullStyle) {
    // Guard against degenerate layouts (zero seats, empty bounds)
    if (geometry.totalBounds.isEmpty || geometry.totalBounds.height == 0) {
      return const SizedBox.shrink();
    }
    const minimapSize = 80.0;
    final aspectRatio =
        geometry.totalBounds.width / geometry.totalBounds.height;
    const minimapWidth = minimapSize;
    final minimapHeight = minimapSize / aspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: minimapWidth,
        height: minimapHeight,
        decoration: BoxDecoration(
          color: widget.surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.dividerColor, width: 0.5),
        ),
        child: CustomPaint(
          size: Size(minimapWidth, minimapHeight),
          painter: SeatMinimapPainter(
            geometry: geometry,
            selectedSeats: _controller.selectedSeats,
            availableColor: widget.dividerColor,
            selectedColor: widget.accentColor,
            bookedColor: widget.dangerColor,
            blockedColor: widget.dangerColor,
            currentDeck: _controller.currentDeck,
            repaint: _controller,
          ),
        ),
      ),
    );
  }

  SeatPalette _palette() => SeatPalette.fromTheme(
    accent: widget.accentColor,
    surface: widget.surfaceColor,
    divider: widget.dividerColor,
    textPrimary: widget.textPrimary,
    textSecondary: widget.textSecondary,
    textTertiary: widget.textTertiary,
    background: widget.backgroundColor,
    danger: widget.dangerColor,
  );

  Widget _buildLegend() {
    final layout = widget.layout!;
    final seats = layout.allSeats;
    final hasTiers = seats.any((s) => s.tier != SeatTier.standard);
    final hasNotForSale = seats.any(
      (s) =>
          s.status == SeatBookStatus.blocked ||
          s.status == SeatBookStatus.reserved,
    );
    final crew = layout.decks
        .expand((d) => d.grid.expand((r) => r))
        .where((s) => s.isCrew)
        .toList();
    final palette = _palette();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          _legendItem(
            palette,
            SeatLook.open,
            hasTiers ? 'Standard' : 'Available',
          ),
          _legendItem(palette, SeatLook.mine, 'Your seat'),
          _legendItem(palette, SeatLook.taken, 'Taken'),
          if (hasNotForSale)
            _legendItem(palette, SeatLook.notForSale, 'Not for sale'),
          if (hasTiers) _legendItem(palette, SeatLook.open, 'VIP', vip: true),
          if (crew.isNotEmpty) _legendItem(palette, SeatLook.crew, 'Crew'),
        ],
      ),
    );
  }

  Widget _legendItem(
    SeatPalette palette,
    SeatLook look,
    String label, {
    bool vip = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(17, 18),
          painter: SeatGlyphPainter(palette, look, vip: vip),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: widget.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutDock() {
    final checkout = _controller.checkoutState;
    final hasSelection = checkout.selectedSeats.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        border: Border(top: BorderSide(color: widget.dividerColor, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${checkout.selectedSeats.length} seat${checkout.selectedSeats.length == 1 ? "" : "s"}',
                  style: TextStyle(fontSize: 12, color: widget.textTertiary),
                ),
                // Animated total — TweenAnimationBuilder for digit-roll
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: _previousTotal,
                    end: checkout.totalFare,
                  ),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Text(
                      '\$${value.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: widget.accentColor,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
            const Spacer(),
            GestureDetector(
              onTap: (hasSelection && !widget.isBooking)
                  ? () => widget.onBook?.call(
                      checkout.selectedSeats,
                      checkout.totalFare,
                    )
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: hasSelection ? widget.accentColor : widget.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: hasSelection
                      ? [
                          BoxShadow(
                            color: widget.accentColor.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: widget.isBooking
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.backgroundColor,
                        ),
                      )
                    : Text(
                        'Book Now',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: hasSelection
                              ? widget.backgroundColor
                              : widget.textTertiary,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds the vehicle a passenger sees from the backend's seat map
/// (`TransitSeatMap.layout`: one `{seatId, row, col, type, tier}` per cell,
/// as the operator drew it in the business portal).
///
/// - Seats sit at the operator's real columns. A column with no seat in any
///   row is the walkway. When the operator drew no walkway (the editor's
///   default grid has none), it goes between the two halves, as it always
///   has.
/// - Cells marked NONE are empty space, never seats; a missing seat keeps
///   its width so the columns stay aligned.
/// - With [withCab], a cab row leads: the driver front-left (Ghana's
///   vehicles are left-hand drive) and, with [withMate], the mate's seat
///   front-right, beside the kerb-side door. Neither is ever bookable. The
///   mate is assumed for anything with eight or more seats (trotros,
///   Sprinters, coaches) unless [withMate] says otherwise.
VehicleLayout vehicleLayoutFromSeats({
  required String layoutId,
  required List<booking.TransitSeat> seats,
  String? vehicleType,
  String? vehicleMake,
  String? vehicleModel,
  bool withCab = true,
  bool? withMate,
  String? mateLabel,
}) {
  VehicleLayout build(List<List<GridSlot>> grid) => VehicleLayout(
    id: layoutId,
    vehicleType: vehicleType,
    vehicleMake: vehicleMake,
    vehicleModel: vehicleModel,
    decks: [Deck(deckIndex: 0, grid: grid)],
  );

  final real = seats.where((s) => !s.isSpace).toList();
  if (real.isEmpty) return build(const []);

  // Columns, trimmed to the span that holds seats.
  final seatCols = real.map((s) => s.col).toSet();
  final firstCol = seatCols.reduce(math.min);
  final lastCol = seatCols.reduce(math.max);
  final columns = [for (var c = firstCol; c <= lastCol; c++) c];
  final walkway = {
    for (final c in columns)
      if (!seatCols.contains(c)) c,
  };
  final byPos = <(int, int), booking.TransitSeat>{
    for (final s in real) (s.row, s.col): s,
  };
  final rows = (real.map((s) => s.row).toSet().toList()..sort());

  // A column empty in at least half the rows is the operator's walkway,
  // even when a back bench crosses it: it keeps a seat's width (the bench
  // seat fills it in its row) and no other walkway is added.
  final drawnGap = columns.any((c) {
    if (walkway.contains(c)) return false;
    final missing = rows.where((r) => !byPos.containsKey((r, c))).length;
    return missing * 2 >= rows.length;
  });
  final seatColumnCount = columns.length - walkway.length;
  // Index in [columns] after which a virtual walkway goes, when the
  // operator drew none.
  final splitAfter = walkway.isEmpty && !drawnGap && seatColumnCount > 2
      ? seatColumnCount ~/ 2 - 1
      : null;

  GridSlot seatSlot(booking.TransitSeat s, int row, int col) => GridSlot(
    type: SlotType.seat,
    row: row,
    col: col,
    seatId: s.seatId,
    seatLabel: s.seatId,
    tier: switch (s.tier) {
      booking.SeatTier.economy => SeatTier.standard,
      booking.SeatTier.standard => SeatTier.standard,
      booking.SeatTier.vip => SeatTier.vip,
    },
    status: switch (s.status) {
      booking.SeatStatus.available => SeatBookStatus.available,
      booking.SeatStatus.occupied => SeatBookStatus.booked,
      booking.SeatStatus.blocked => SeatBookStatus.blocked,
    },
    fare: s.fare,
  );

  /// One grid row across [columns]; [cell] fills each seat column.
  List<GridSlot> lay(int gridRow, GridSlot Function(int c, int col) cell) {
    final out = <GridSlot>[];
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      out.add(
        walkway.contains(c)
            ? GridSlot(type: SlotType.aisle, row: gridRow, col: out.length)
            : cell(c, out.length),
      );
      if (i == splitAfter) {
        out.add(GridSlot(type: SlotType.aisle, row: gridRow, col: out.length));
      }
    }
    return out;
  }

  final grid = <List<GridSlot>>[];
  if (withCab) {
    final mate = withMate ?? real.length >= 8;
    final seatColumns = columns.where((c) => !walkway.contains(c)).toList();
    grid.add(
      lay(0, (c, col) {
        if (c == seatColumns.first) {
          return GridSlot(
            type: SlotType.driver,
            row: 0,
            col: col,
            seatLabel: 'Driver',
          );
        }
        if (mate && c == seatColumns.last && seatColumns.length > 1) {
          return GridSlot(
            type: SlotType.crew,
            row: 0,
            col: col,
            seatLabel: mateLabel ?? 'Mate',
          );
        }
        return GridSlot(type: SlotType.empty, row: 0, col: col);
      }),
    );
  }
  for (final r in rows) {
    final gridRow = grid.length;
    grid.add(
      lay(gridRow, (c, col) {
        final s = byPos[(r, c)];
        return s == null
            ? GridSlot(type: SlotType.empty, row: gridRow, col: col)
            : seatSlot(s, gridRow, col);
      }),
    );
  }
  return build(grid);
}
