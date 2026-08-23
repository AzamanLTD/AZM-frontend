// =============================================================================
// AZAMAN — SEAT SEMANTICS OVERLAY
//
// A Stack layer of invisible Semantics widgets positioned via the geometry
// solver's Rects, one per seat. Each is labeled with seat number/tier/price/
// status and has an onTap matching the canvas hit-test logic, so the entire
// flow is fully usable with TalkBack/VoiceOver without a separate UI mode.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'seat_layout_models.dart';
import 'seat_geometry_solver.dart';

/// Builds the semantics overlay for the seat selector.
class SeatSemanticsOverlay extends StatelessWidget {
  final ComputedGeometry geometry;
  final Set<String> selectedSeats;
  final int currentDeck;
  final void Function(String seatId) onSeatTap;
  final double viewportWidth;
  final double viewportHeight;

  const SeatSemanticsOverlay({
    super.key,
    required this.geometry,
    required this.selectedSeats,
    required this.currentDeck,
    required this.onSeatTap,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  @override
  Widget build(BuildContext context) {
    final deckRects = geometry.deckRects[currentDeck] ?? [];

    return Stack(
      clipBehavior: Clip.none,
      children: deckRects.where((r) => r.slot.isSeat).map((slotRect) {
        final slot = slotRect.slot;
        final isSelected = selectedSeats.contains(slot.seatId);

        // Build the semantic label
        final parts = <String>[
          'Seat ${slot.seatLabel ?? slot.seatId}',
          slot.tier.label,
        ];

        if (isSelected) {
          parts.add('Selected');
        } else {
          parts.add(slot.status.label);
        }

        if (slot.fare > 0) {
          parts.add('\$${slot.fare.toStringAsFixed(0)}');
        }

        final label = parts.join(', ');

        // Position the invisible semantics widget at the seat's hit-test rect
        return Positioned(
          left: slotRect.hitRect.left,
          top: slotRect.hitRect.top,
          width: slotRect.hitRect.width,
          height: slotRect.hitRect.height,
          child: Semantics(
            label: label,
            button: slot.isTappable,
            enabled: slot.isTappable,
            onTap: slot.isTappable
                ? () => onSeatTap(slot.seatId!)
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: slot.isTappable
                  ? () => onSeatTap(slot.seatId!)
                  : null,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
