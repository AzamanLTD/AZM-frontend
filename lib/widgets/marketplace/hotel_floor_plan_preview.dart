import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Compact hotel building explorer for marketplace business pages.
///
/// The preview keeps the full booking flow authoritative while giving the
/// customer a spatial property model: building floors first, then the rooms
/// on the selected floor.
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
      final floor = roomNumber == null
          ? 1
          : (roomNumber ~/ 100).clamp(1, 99).toInt();
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
          _BuildingOverview(
            floors: orderedFloors,
            roomsByFloor: floors,
            activeFloor: activeFloor,
            colors: widget.colors,
            onFloorSelected: (floor) =>
                setState(() => _selectedFloor = floor),
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
            'Select an available room to continue in the full booking flow.',
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
    final available = room.isActive;
    final match = RegExp(r'(\d+)').firstMatch(room.name);
    final roomNumber = match?.group(1) ?? '?';
    final deluxe = room.tags.any((tag) => tag.toLowerCase().contains('deluxe'));
    final accent = deluxe ? const Color(0xFFF59E0B) : widget.colors.accent;

    return Semantics(
      button: available,
      enabled: available,
      selected: selected,
      label: available
          ? '${room.name}, ${room.priceUsdc.toStringAsFixed(0)} USDC per night'
          : '${room.name}, unavailable',
      child: GestureDetector(
        onTap: available ? () => widget.onRoomSelected(room.id) : null,
        child: AnimatedOpacity(
          opacity: available ? 1 : 0.48,
          duration: 180.ms,
          child: AnimatedContainer(
            duration: 200.ms,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.14)
                  : widget.colors.surface,
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
                  available
                      ? '\$${room.priceUsdc.toStringAsFixed(0)}'
                      : 'Unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? accent : widget.colors.textTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
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

class _BuildingOverview extends StatelessWidget {
  final List<int> floors;
  final Map<int, List<BusinessProduct>> roomsByFloor;
  final int activeFloor;
  final AzamanColors colors;
  final ValueChanged<int> onFloorSelected;

  const _BuildingOverview({
    required this.floors,
    required this.roomsByFloor,
    required this.activeFloor,
    required this.colors,
    required this.onFloorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final visualFloors = [...floors]..sort((a, b) => b.compareTo(a));

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.accent.withValues(alpha: 0.08),
            colors.card.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apartment_outlined, size: 17, color: colors.accent),
              const SizedBox(width: 7),
              Text(
                'Building overview',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${floors.length} floor${floors.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              for (final floor in visualFloors) ...[
                _FloorStrip(
                  floor: floor,
                  rooms: roomsByFloor[floor]!,
                  selected: floor == activeFloor,
                  colors: colors,
                  onTap: () => onFloorSelected(floor),
                ),
                if (floor != visualFloors.last)
                  Container(
                    width: 1,
                    height: 5,
                    color: colors.divider,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FloorStrip extends StatelessWidget {
  final int floor;
  final List<BusinessProduct> rooms;
  final bool selected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _FloorStrip({
    required this.floor,
    required this.rooms,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = rooms.where((room) => room.isActive).length;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Floor $floor, $available of ${rooms.length} rooms available',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: 200.ms,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.accent.withValues(alpha: 0.13) : colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
              width: selected ? 1.1 : 0.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : colors.softSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'F$floor',
                  style: TextStyle(
                    color: selected ? Colors.white : colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Floor $floor',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$available of ${rooms.length} rooms available',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? colors.accent : colors.textTertiary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
