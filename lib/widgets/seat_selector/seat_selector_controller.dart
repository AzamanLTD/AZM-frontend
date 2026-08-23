// =============================================================================
// AZAMAN — SEAT SELECTOR CONTROLLER
//
// ChangeNotifier-based state for the seat selector. Manages:
//   - Selected seats (local UI state, layered on top of backend availability)
//   - Selection limits (max seats per booking)
//   - Pricing total (sum of selected seat fares)
//   - Current deck (for multi-deck vehicles)
//   - TransformationController (for InteractiveViewer viewport)
//
// All seat-state changes notify listeners WITHOUT triggering a full widget
// rebuild — the CustomPainter repaints via its `repaint: Listenable`
// parameter, not via setState on the parent widget.
// =============================================================================

import 'package:flutter/material.dart';

import 'seat_layout_models.dart';
import 'seat_geometry_solver.dart';

/// State snapshot for the checkout dock.
class CheckoutState {
  final Set<String> selectedSeats;
  final double totalFare;
  final int selectionLimit;

  const CheckoutState({
    required this.selectedSeats,
    required this.totalFare,
    required this.selectionLimit,
  });

  bool get isLimitReached =>
      selectionLimit > 0 && selectedSeats.length >= selectionLimit;
  int get remainingSlots =>
      selectionLimit > 0 ? selectionLimit - selectedSeats.length : 999;
}

/// Controller for seat selection state.
class SeatSelectorController extends ChangeNotifier {
  /// The vehicle layout being rendered.
  VehicleLayout? _layout;
  VehicleLayout? get layout => _layout;

  /// Precomputed geometry for the current layout.
  ComputedGeometry? _geometry;
  ComputedGeometry? get geometry => _geometry;

  /// The transformation controller for InteractiveViewer.
  final TransformationController transformController;

  /// Currently selected seat IDs.
  final Set<String> _selectedSeats = {};
  Set<String> get selectedSeats => Set.unmodifiable(_selectedSeats);

  /// Maximum seats a user can select (0 = unlimited).
  int _selectionLimit;
  int get selectionLimit => _selectionLimit;

  /// Current deck index (for multi-deck).
  int _currentDeck = 0;
  int get currentDeck => _currentDeck;

  /// Map of seatId → fare for pricing.
  final Map<String, double> _fareMap = {};

  SeatSelectorController({
    TransformationController? transformController,
    int selectionLimit = 0,
  })  : transformController =
            transformController ?? TransformationController(),
        _selectionLimit = selectionLimit;

  /// Load a layout and compute its geometry.
  void loadLayout(
    VehicleLayout layout, {
    SeatGeometryConfig? geometryConfig,
  }) {
    _layout = layout;
    final solver = SeatGeometrySolver(geometryConfig ?? const SeatGeometryConfig());
    _geometry = solver.compute(layout);

    // Build fare map from seats
    _fareMap.clear();
    for (final seat in layout.allSeats) {
      if (seat.seatId != null) {
        _fareMap[seat.seatId!] = seat.fare;
      }
    }

    // Reset deck if out of range
    if (_currentDeck >= layout.decks.length) {
      _currentDeck = 0;
    }

    notifyListeners();
  }

  /// Toggle a seat's selection state. Returns true if the seat was
  /// successfully toggled (false if e.g. selection limit reached).
  bool toggleSeat(String seatId) {
    if (_selectedSeats.contains(seatId)) {
      _selectedSeats.remove(seatId);
      notifyListeners();
      return true;
    }

    // Check if we can add (limit + seat must exist and be tappable)
    if (_selectionLimit > 0 && _selectedSeats.length >= _selectionLimit) {
      return false;
    }

    final seat = _layout?.findSeat(seatId);
    if (seat == null || !seat.isTappable) return false;

    // Switch to the correct deck if needed
    final deckIdx = _layout?.deckIndexForSeat(seatId);
    if (deckIdx != null && deckIdx != _currentDeck) {
      _currentDeck = deckIdx;
    }

    _selectedSeats.add(seatId);
    notifyListeners();
    return true;
  }

  /// Select a seat (no toggle — adds only, respects limit).
  bool selectSeat(String seatId) {
    if (_selectedSeats.contains(seatId)) return true;
    return toggleSeat(seatId);
  }

  /// Deselect a seat (no toggle — removes only).
  void deselectSeat(String seatId) {
    if (_selectedSeats.remove(seatId)) {
      notifyListeners();
    }
  }

  /// Clear all selected seats.
  void clearSelection() {
    if (_selectedSeats.isEmpty) return;
    _selectedSeats.clear();
    notifyListeners();
  }

  /// Set the selection limit.
  set selectionLimit(int value) {
    _selectionLimit = value;
    // If current selection exceeds new limit, trim it
    while (_selectedSeats.length > _selectionLimit && _selectionLimit > 0) {
      _selectedSeats.remove(_selectedSeats.last);
    }
    notifyListeners();
  }

  /// Switch to a different deck.
  void setDeck(int index) {
    if (_layout == null || index < 0 || index >= _layout!.decks.length) return;
    if (_currentDeck == index) return;
    _currentDeck = index;
    notifyListeners();
  }

  /// Total fare for currently selected seats.
  double get totalFare {
    double total = 0;
    for (final seatId in _selectedSeats) {
      total += _fareMap[seatId] ?? 0;
    }
    return total;
  }

  /// Whether a given seatId is currently selected.
  bool isSelected(String seatId) => _selectedSeats.contains(seatId);

  /// Checkout state snapshot for the dock.
  CheckoutState get checkoutState => CheckoutState(
        selectedSeats: Set.unmodifiable(_selectedSeats),
        totalFare: totalFare,
        selectionLimit: _selectionLimit,
      );

  @override
  void dispose() {
    // Only dispose if we created it
    // (if passed in externally, the owner manages it)
    transformController.dispose();
    super.dispose();
  }
}
