import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Compact read-only hotel floor-plan preview for marketplace business pages.
///
/// This previews the same room/floor mental model used by the full hotel
/// booking flow without duplicating its booking state or network lifecycle.
class HotelFloorPlanPreview extends StatefulWidget {
  final List<BusinessProduct> products;
  final String? selectedRoomId;
  final ValueChanged<String> onRoomSelected;
  final AzamanColors colors;

  const HotelFloorPlanPreview({
    super.key,
    required this.products,
    required this.selectedRoomId,
    required this.onRoomSelected,
    required this.colors,
  });

  @override
  State<HotelFloorPlanPreview> createState() => _HotelFloorPlanPreviewState();
}

class _HotelFloorPlanPreviewState extends State<HotelFloorPlanPreview> {
  int? _selectedFloor;

  Map<int, List<BusinessProduct>> get _roomsByFloor {
    final floors = <int, List<BusinessProduct>>{};
    for (final product in widget.products) {
      final match = RegExp(r'Room\s+(\d+)', caseSensitive: false)
          .firstMatch(product.name);
      final roomNumber = int.tryParse(match?.group(1) ?? '');
      final floor = roomNumber == null ? 1 : (roomNumber ~/ 100).clamp(1, 99);
      floors.putIfAbsent(floor, () => []).add(product);
    }
    return floors;
  }

  @override
  Widget build(BuildContext context) {
    final floors = _roomsByFloor;
    if (floors.isEmpty) return _emptyState();

    final orderedFloors = floors.keys.toList()..sort();
    final activeFloor = orderedFloors.contains(_selectedFloor)
        ? _selectedFloor!
        : orderedFloors.first;
    final rooms = floors[activeFloor]!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Explore the property',
                  style: TextStyle(
                    color: widget.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${widget.products.length} room${widget.products.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: widget.colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final floor in orderedFloors) ...[
                  ChoiceChip(
                    label: Text('Floor $floor'),
                    selected: floor == activeFloor,
                    onSelected: (_) => setState(() => _selectedFloor = floor),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: widget.colors.card.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: widget.colors.divider.withValues(alpha: 0.65),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < rooms.length; i += 2)
                        _roomTile(rooms[i]),
                    ],
                  ),
                ),
                Container(
                  width: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  constraints: const BoxConstraints(minHeight: 180),
                  decoration: BoxDecoration(
                    color: widget.colors.divider.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(Icons.elevator_outlined,
                          size: 16, color: widget.colors.textTertiary),
                      Container(
                        width: 1,
                        height: 42,
                        color: widget.colors.divider,
                      ),
                      Icon(Icons.stairs_outlined,
                          size: 16, color: widget.colors.textTertiary),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 1; i < rooms.length; i += 2)
                        _roomTile(rooms[i]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Select a room to continue in the full booking flow.',
            style: TextStyle(
              color: widget.colors.textTertiary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomTile(BusinessProduct room) {
    final selected = room.id == widget.selectedRoomId;
    final match = RegExp(r'(\d+)').firstMatch(room.name);
    final roomNumber = match?.group(1) ?? '?';
    final deluxe = room.tags.any((tag) => tag.toLowerCase().contains('deluxe'));
    final accent = deluxe ? const Color(0xFFF59E0B) : widget.colors.accent;

    return Semantics(
      button: true,
      selected: selected,
      label: '${room.name}, ${room.priceUsdc.toStringAsFixed(0)} USDC per night',
      child: GestureDetector(
        onTap: () => widget.onRoomSelected(room.id),
        child: AnimatedContainer(
          duration: 200.ms,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : widget.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent
                  : widget.colors.divider.withValues(alpha: 0.55),
              width: selected ? 1.4 : 0.6,
            ),
          ),
          child: Column(
            children: [
              Text(
                roomNumber,
                style: TextStyle(
                  color: selected ? accent : widget.colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '\$${room.priceUsdc.toStringAsFixed(0)}',
                style: TextStyle(
                  color: selected ? accent : widget.colors.textTertiary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hotel_outlined,
                size: 36, color: widget.colors.textTertiary),
            const SizedBox(height: 8),
            Text(
              'Room inventory is not available yet.',
              style: TextStyle(color: widget.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
