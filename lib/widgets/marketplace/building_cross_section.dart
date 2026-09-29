// =============================================================================
// BUILDING CROSS-SECTION — hotel browse as "walking the building" (TASK-015)
//
// The blueprint's navigationMode for hotels is `floorTraverse`: the property is
// a vertical building section, not a card list. Floors are horizontal bands in
// a vertical PageView; the centred floor is full-bright and upright, floors
// above/below dim and skew as they drift past. Rooms render as footprints —
// a bed glyph, an availability colour, a rate — never as cards.
//
// Ground floor is page 0 (swipe up to climb). `hotelBandsFromRooms` is pure and
// unit-tested: rooms without a floor land in the lowest band; a property with
// no floor data collapses to a single unlabelled band.
//
// TEST-SAFETY: one vertical PageView inside a SliverToBoxAdapter. The inner
// scrollable claims vertical drags over its own bounds (standard Flutter
// gesture-arena behaviour) — the page around it still scrolls normally. No
// timers, no repeating tickers; the skew/dim transform is driven by the
// PageController via AnimatedBuilder.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';

/// One horizontal band of the building section: a floor and its rooms.
class HotelFloorBand {
  final int? floor;
  final List<HotelRoom> rooms;

  const HotelFloorBand({this.floor, required this.rooms});
}

/// Floors present in [rooms], sorted ascending (ground first).
List<int> hotelFloorsFromRooms(List<HotelRoom> rooms) {
  final floors = rooms.map((r) => r.floor).whereType<int>().toSet().toList();
  floors.sort();
  return floors;
}

/// Groups [rooms] into bands, one per floor, lowest floor first.
///
/// Rooms with a null floor land in the lowest band (the ground band). If no
/// room declares a floor, the result is a single unlabelled band.
List<HotelFloorBand> hotelBandsFromRooms(List<HotelRoom> rooms) {
  if (rooms.isEmpty) return const [];
  final floors = hotelFloorsFromRooms(rooms);
  if (floors.isEmpty) {
    return [
      HotelFloorBand(floor: null, rooms: List<HotelRoom>.unmodifiable(rooms)),
    ];
  }
  final bands = <HotelFloorBand>[
    for (final floor in floors)
      HotelFloorBand(
        floor: floor,
        rooms: List<HotelRoom>.unmodifiable(
          rooms.where((r) => r.floor == floor),
        ),
      ),
  ];
  final unassigned =
      rooms.where((r) => r.floor == null).toList(growable: false);
  if (unassigned.isNotEmpty) {
    bands[0] = HotelFloorBand(
      floor: bands[0].floor,
      rooms: List<HotelRoom>.unmodifiable([...unassigned, ...bands[0].rooms]),
    );
  }
  return bands;
}

class BuildingCrossSection extends StatefulWidget {
  final List<HotelRoom> rooms;
  final String? selectedRoomId;
  final ValueChanged<HotelRoom> onRoomTap;
  final ValueChanged<int?>? onFloorChanged;
  final AzamanColors colors;

  const BuildingCrossSection({
    super.key,
    required this.rooms,
    required this.selectedRoomId,
    required this.onRoomTap,
    required this.colors,
    this.onFloorChanged,
  });

  @override
  State<BuildingCrossSection> createState() => _BuildingCrossSectionState();
}

class _BuildingCrossSectionState extends State<BuildingCrossSection> {
  late final PageController _pageController;
  List<HotelFloorBand> _bands = const [];
  int _currentBand = 0;

  @override
  void initState() {
    super.initState();
    _bands = hotelBandsFromRooms(widget.rooms);
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(BuildingCrossSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rooms, widget.rooms)) {
      _bands = hotelBandsFromRooms(widget.rooms);
      if (_currentBand >= _bands.length) {
        _currentBand = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bands.isEmpty) return _emptyState();
    return SizedBox(
      height: 200,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _bands.length,
        onPageChanged: (index) {
          setState(() => _currentBand = index);
          widget.onFloorChanged?.call(_bands[index].floor);
        },
        itemBuilder: (context, index) {
          final band = _bands[index];
          return AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              final page = _pageController.hasClients &&
                      _pageController.position.hasContentDimensions
                  ? _pageController.page ?? _currentBand.toDouble()
                  : _currentBand.toDouble();
              final delta = (page - index).clamp(-1.0, 1.0).toDouble();
              final skew = -delta * 0.10;
              final opacity =
                  (1.0 - 0.45 * delta.abs()).clamp(0.0, 1.0).toDouble();
              return Opacity(
                opacity: opacity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(skew),
                  child: child,
                ),
              );
            },
            child: _FloorBand(
              band: band,
              selectedRoomId: widget.selectedRoomId,
              onRoomTap: widget.onRoomTap,
              colors: widget.colors,
            ),
          );
        },
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
                size: 44, color: widget.colors.textTertiary),
            const SizedBox(height: 10),
            Text(
              'No room inventory has been published yet.',
              style: AzText.bodyS.copyWith(color: widget.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorBand extends StatelessWidget {
  final HotelFloorBand band;
  final String? selectedRoomId;
  final ValueChanged<HotelRoom> onRoomTap;
  final AzamanColors colors;

  const _FloorBand({
    required this.band,
    required this.selectedRoomId,
    required this.onRoomTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final available = band.rooms.where((r) => r.isBookable).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AzSpace.xs, AzSpace.xs, AzSpace.xs, AzSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apartment_outlined,
                  size: 15, color: colors.textTertiary),
              const SizedBox(width: AzSpace.xs),
              Text(
                band.floor == null ? 'Ground level' : 'Floor ${band.floor}',
                style: AzText.label.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Text(
                '$available of ${band.rooms.length} available',
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AzSpace.sm),
          SizedBox(
            height: 156,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final room in band.rooms) ...[
                    _RoomFootprint(
                      room: room,
                      selected: room.id == selectedRoomId,
                      onTap: () => onRoomTap(room),
                      colors: colors,
                    ),
                    const SizedBox(width: AzSpace.sm),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomFootprint extends StatelessWidget {
  final HotelRoom room;
  final bool selected;
  final VoidCallback onTap;
  final AzamanColors colors;

  const _RoomFootprint({
    required this.room,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bookable = room.isBookable;
    final fill = !bookable
        ? colors.card.withValues(alpha: 0.45)
        : selected
            ? colors.accent.withValues(alpha: 0.12)
            : colors.surface;
    return Semantics(
      button: bookable,
      selected: selected,
      label:
          '${room.displayType} room ${room.roomNumber}, \$${room.basePriceUsdc.toStringAsFixed(0)} USDC per night${bookable ? '' : ', unavailable'}',
      child: GestureDetector(
        onTap: bookable ? onTap : null,
        child: Container(
          width: 84,
          height: 148,
          padding: const EdgeInsets.all(AzSpace.sm),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AzRadius.brMd,
            border: Border.all(
              color: selected
                  ? colors.accent
                  : colors.divider.withValues(alpha: 0.55),
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                bookable ? Icons.bed_outlined : Icons.lock_outline,
                size: 18,
                color: selected ? colors.accent : colors.textTertiary,
              ),
              Text(
                room.roomNumber,
                style: AzText.title.copyWith(
                  color: selected ? colors.accent : colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                bookable
                    ? '\$${room.basePriceUsdc.toStringAsFixed(0)}'
                    : 'Unavailable',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
