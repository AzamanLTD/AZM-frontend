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
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'seat_layout_models.dart';
import 'seat_geometry_solver.dart';
import 'seat_canvas_painter.dart';
import 'seat_selector_controller.dart';
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
  });

  @override
  State<BusSeatSelector> createState() => _BusSeatSelectorState();
}

class _BusSeatSelectorState extends State<BusSeatSelector>
    with SingleTickerProviderStateMixin {
  late SeatSelectorController _controller;

  // SVG icon cache
  SeatIconCache? _iconCache;
  bool _iconsLoading = false;

  // Animation controller for the selection pulse ring
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Previous total for animated digit-roll
  double _previousTotal = 0;

  @override
  void initState() {
    super.initState();

    _controller = widget.controller ??
        SeatSelectorController(selectionLimit: 0);

    // Pulse animation for selected-seat rings
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Load layout if provided
    if (widget.layout != null) {
      _controller.loadLayout(widget.layout!);
      _loadIcons();
      _scheduleAutoFit();
    }

    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(BusSeatSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layout != oldWidget.layout && widget.layout != null) {
      _controller.loadLayout(widget.layout!);
      _loadIcons();
      _scheduleAutoFit();
    }
  }

  void _onControllerChanged() {
    final currentTotal = _controller.totalFare;
    if (currentTotal != _previousTotal) {
      // The TweenAnimationBuilder in the checkout dock handles the visual
      _previousTotal = currentTotal;
    }
    widget.onSelectionChanged?.call(_controller.selectedSeats);
    setState(() {}); // Rebuild for dock/legend updates
  }

  Future<void> _loadIcons() async {
    if (_iconsLoading || _iconCache != null) return;
    _iconsLoading = true;

    try {
      final available = await _decodeSvg('assets/icons/seats/seat_available.svg');
      final selected = await _decodeSvg('assets/icons/seats/seat_selected.svg');
      final occupied = await _decodeSvg('assets/icons/seats/seat_occupied.svg');
      final blocked = await _decodeSvg('assets/icons/seats/seat_blocked.svg');

      if (mounted) {
        _iconCache = SeatIconCache(
          available: available,
          selected: selected,
          occupied: occupied,
          blocked: blocked,
        );
        setState(() {});
      }
    } catch (e) {
      // Icons will fall back to simple rect rendering
      debugPrint('Seat icon decode failed: $e');
    } finally {
      _iconsLoading = false;
    }
  }

  Future<ui.Picture?> _decodeSvg(String assetPath) async {
    try {
      final svg = await vg.loadPicture(
        SvgAssetLoader(assetPath),
        null,
      );
      return svg.picture;
    } catch (e) {
      debugPrint('Failed to decode $assetPath: $e');
      return null;
    }
  }

  void _scheduleAutoFit() {
    final geometry = _controller.geometry;
    if (geometry == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFit(geometry.totalBounds);
    });
  }

  void _autoFit(Rect bounds) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;

    final viewportSize = renderBox.size;
    if (viewportSize.isEmpty || bounds.isEmpty) return;

    // Compute scale to fit bounds in viewport with padding
    const padding = 40.0;
    final scaleX = (viewportSize.width - padding * 2) / bounds.width;
    final scaleY = (viewportSize.height - padding * 2) / bounds.height;
    final scale = math.min(scaleX, scaleY);
    final clampedScale = scale.clamp(0.8, 3.0);

    // Center the bounds in the viewport
    final offsetX = (viewportSize.width - bounds.width * clampedScale) / 2 -
        bounds.left * clampedScale;
    final offsetY = (viewportSize.height - bounds.height * clampedScale) / 2 -
        bounds.top * clampedScale;

    final targetMatrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(clampedScale);

    // Animate with spring-like curve
    final currentMatrix = _controller.transformController.value.clone();
    _animateMatrix(currentMatrix, targetMatrix);
  }

  void _animateMatrix(Matrix4 from, Matrix4 to) {
    // Use a TweenAnimationBuilder-like approach via the controller
    final animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    final tween = Matrix4Tween(begin: from, end: to);
    final animation = tween.animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOutBack,
      ),
    );

    animation.addListener(() {
      if (mounted) {
        _controller.transformController.value = animation.value;
      }
    });

    animationController.forward().then((_) {
      animationController.dispose();
    });
  }

  void _onSeatTap(String seatId) {
    final success = _controller.toggleSeat(seatId);
    if (success) {
      HapticFeedback.selectionClick();

      // Animate viewport to center on the tapped seat
      final geometry = _controller.geometry;
      if (geometry != null) {
        final slotRect = geometry.rectForSeat(seatId);
        if (slotRect != null) {
          _centerOnRect(slotRect.visualRect);
        }
      }
    }
  }

  void _centerOnRect(Rect rect) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;

    final viewportSize = renderBox.size;
    if (viewportSize.isEmpty) return;

    final zoomScale = 1.5;

    // Center the rect in the viewport at the target zoom
    final offsetX =
        viewportSize.width / 2 - (rect.left + rect.width / 2) * zoomScale;
    final offsetY =
        viewportSize.height / 2 - (rect.top + rect.height / 2) * zoomScale;

    final targetMatrix = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(zoomScale);

    _animateMatrix(_controller.transformController.value, targetMatrix);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _pulseController.dispose();
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

    return Column(
      children: [
        // ── Deck switcher (if multi-deck) ──────────────────────────────
        if (widget.layout!.isMultiDeck) _buildDeckSwitcher(),

        // ── Main canvas + minimap ───────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // InteractiveViewer with canvas
              InteractiveViewer(
                transformationController: _controller.transformController,
                constrained: false,
                minScale: 0.8,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(80),
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
                          iconCache: _iconCache ?? const SeatIconCache(),
                          selectedSeats: _controller.selectedSeats,
                          hullStyle: hullStyle,
                          accentColor: widget.accentColor,
                          selectionPulse: _pulseAnimation.value,
                          currentDeck: _controller.currentDeck,
                          repaint: Listenable.merge([
                            _controller,
                            _pulseAnimation,
                          ]),
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

              // Floating minimap (top-right)
              if (widget.showMinimap)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildMinimap(geometry, hullStyle),
                ),
            ],
          ),
        ),

        // ── Status legend ──────────────────────────────────────────────
        if (widget.showLegend) _buildLegend(),

        // ── Sticky checkout dock ────────────────────────────────────────
        if (widget.showCheckoutDock) _buildCheckoutDock(),
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
                onTap: () => _controller.setDeck(deck.deckIndex),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? widget.accentColor
                        : widget.cardColor,
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
    final minimapSize = 80.0;
    final aspectRatio = geometry.totalBounds.width / geometry.totalBounds.height;
    final minimapWidth = minimapSize;
    final minimapHeight = minimapSize / aspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: minimapWidth,
        height: minimapHeight,
        decoration: BoxDecoration(
          color: widget.surfaceColor.withValues(alpha: 0.9),
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

  Widget _buildLegend() {
    final hasTiers =
        widget.layout!.allSeats.any((s) => s.tier != SeatTier.standard);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: widget.surfaceColor,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 8,
        children: [
          _legendItem('assets/icons/seats/seat_available.svg',
              hasTiers ? 'Standard' : 'Available'),
          _legendItem('assets/icons/seats/seat_selected.svg', 'Selected'),
          _legendItem('assets/icons/seats/seat_occupied.svg', 'Occupied'),
          if (widget.layout!.allSeats
              .any((s) => s.status == SeatBookStatus.blocked))
            _legendItem('assets/icons/seats/seat_blocked.svg', 'Blocked'),
          if (hasTiers)
            _legendItem('assets/icons/seats/seat_vip.svg', 'VIP'),
        ],
      ),
    );
  }

  Widget _legendItem(String svgPath, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(svgPath, width: 18, height: 18),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: widget.textSecondary, fontSize: 11),
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
        border: Border(
          top: BorderSide(color: widget.dividerColor, width: 0.5),
        ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.textTertiary,
                  ),
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
                  ? () => widget.onBook
                      ?.call(checkout.selectedSeats, checkout.totalFare)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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

/// Helper: convert a [TransitSeat] list (from the existing booking models)
/// into a [VehicleLayout] for the new seat selector module.
/// This adapter allows the new module to consume the existing backend data
/// without changing the API layer.
import 'package:azaman/models/marketplace_booking_models.dart' as booking;

VehicleLayout vehicleLayoutFromSeats({
  required String layoutId,
  required List<booking.TransitSeat> seats,
  String? vehicleType,
  String? vehicleMake,
  String? vehicleModel,
}) {
  // Group seats by row
  final rowMap = <int, List<booking.TransitSeat>>{};
  for (final seat in seats) {
    rowMap.putIfAbsent(seat.row, () => []).add(seat);
  }
  final sortedRows = rowMap.keys.toList()..sort();

  // Build grid: 4 columns per row (existing layout is always 4 cols: A,B,C,D)
  // Aisle between col 1 and 2 (after first seat)
  final grid = <List<GridSlot>>[];

  for (final rowNum in sortedRows) {
    final rowSeats = rowMap[rowNum]!..sort((a, b) => a.col.compareTo(b.col));
    final row = <GridSlot>[];

    for (int colIdx = 0; colIdx < rowSeats.length; colIdx++) {
      final s = rowSeats[colIdx];

      // Map old SeatStatus → new SeatBookStatus
      final bookStatus = switch (s.status) {
        booking.SeatStatus.available => SeatBookStatus.available,
        booking.SeatStatus.occupied => SeatBookStatus.booked,
        booking.SeatStatus.blocked => SeatBookStatus.blocked,
      };

      // Map old SeatTier → new SeatTier
      final tier = switch (s.tier) {
        booking.SeatTier.economy => SeatTier.standard,
        booking.SeatTier.standard => SeatTier.standard,
        booking.SeatTier.vip => SeatTier.vip,
      };

      row.add(GridSlot(
        type: SlotType.seat,
        row: s.row - 1, // 0-indexed
        col: s.col - 1,
        seatId: s.seatId,
        seatLabel: s.seatId,
        tier: tier,
        status: bookStatus,
        fare: s.fare,
      ));
    }

    grid.add(row);
  }

  return VehicleLayout(
    id: layoutId,
    vehicleType: vehicleType,
    vehicleMake: vehicleMake,
    vehicleModel: vehicleModel,
    decks: [
      Deck(deckIndex: 0, grid: grid),
    ],
  );
}
