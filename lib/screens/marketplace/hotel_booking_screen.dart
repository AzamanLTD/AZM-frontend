import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/hotel_marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

IconData _hotelAmenityIcon(String amenity) {
  final a = amenity.toLowerCase();
  if (a.contains('wifi') || a.contains('internet')) return Icons.wifi;
  if (a.contains('ac') || a.contains('air')) return Icons.ac_unit;
  if (a.contains('tv')) return Icons.tv;
  if (a.contains('pool') || a.contains('spa')) return Icons.pool;
  if (a.contains('gym') || a.contains('fitness')) return Icons.fitness_center;
  if (a.contains('breakfast')) return Icons.free_breakfast;
  if (a.contains('parking')) return Icons.local_parking;
  if (a.contains('balcony') || a.contains('terrace')) return Icons.balcony;
  if (a.contains('kitchen')) return Icons.kitchen;
  if (a.contains('bar')) return Icons.local_bar;
  if (a.contains('pet')) return Icons.pets;
  if (a.contains('smoke')) return Icons.smoke_free;
  return Icons.check_circle_outline;
}

double _reservationAmount(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class HotelBookingScreen extends ConsumerStatefulWidget {
  final String bizId;
  const HotelBookingScreen({super.key, required this.bizId});

  @override
  ConsumerState<HotelBookingScreen> createState() => _HotelBookingScreenState();
}

class _HotelBookingScreenState extends ConsumerState<HotelBookingScreen> {
  DateTime? _checkIn;
  DateTime? _checkOut;
  String? _selectedRoomId;
  int? _selectedFloor;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(hotelMarketplaceProvider.notifier).load(widget.bizId));
  }

  Future<void> _selectDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDateRange: _checkIn != null && _checkOut != null
          ? DateTimeRange(start: _checkIn!, end: _checkOut!)
          : DateTimeRange(start: now, end: now.add(const Duration(days: 1))),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _checkIn = picked.start;
      _checkOut = picked.end;
    });
  }

  int get _nights {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays;
  }

  HotelRoom? _selectedRoom(List<HotelRoom> rooms) {
    if (_selectedRoomId == null) return null;
    for (final room in rooms) {
      if (room.id == _selectedRoomId) return room;
    }
    return null;
  }

  void _selectRoom(HotelRoom room, List<int> floors) {
    if (!room.isBookable) return;
    setState(() {
      _selectedRoomId = room.id;
      if (room.floor != null && floors.contains(room.floor)) _selectedFloor = room.floor;
    });
  }

  Future<void> _confirmBooking() async {
    final state = ref.read(hotelMarketplaceProvider);
    final room = _selectedRoom(state.rooms);
    if (room == null || _checkIn == null || _checkOut == null || _nights < 1) return;

    try {
      final reservation = await ref.read(hotelMarketplaceProvider.notifier).reserve(
            bizId: widget.bizId,
            roomId: room.id,
            checkIn: _checkIn!,
            checkOut: _checkOut!,
          );
      if (!mounted) return;

      final amount = _reservationAmount(reservation['amountUsdc']);
      final reservationId = (reservation['id'] ?? '').toString();
      if (reservationId.isEmpty) throw StateError('Reservation response did not include an id.');

      BookingSuccessSheet.show(
        context,
        bookingRef: ((reservation['reservationRef'] ?? reservationId).toString()).split('-').last,
        seatCount: 1,
        totalFare: amount,
        route: '${room.displayType} • Room ${room.roomNumber} • $_nights night${_nights == 1 ? '' : 's'}',
        departureTime: _checkIn!,
      );

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) context.pushReplacement('/marketplace/booking/checkin-qr/$reservationId');
      });
    } catch (_) {
      if (!mounted) return;
      final message = ref.read(hotelMarketplaceProvider).error ?? 'Unable to complete the booking.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(hotelMarketplaceProvider);

    if (state.isLoading && state.business == null) return _loading(colors);

    final business = state.business;
    final floors = state.rooms.map((room) => room.floor).whereType<int>().toSet().toList()..sort();
    final effectiveFloor = _selectedFloor != null && floors.contains(_selectedFloor)
        ? _selectedFloor!
        : (floors.isNotEmpty ? floors.first : null);
    final floorRooms = effectiveFloor == null
        ? state.rooms
        : state.rooms.where((room) => room.floor == effectiveFloor).toList();
    final selectedRoom = _selectedRoom(state.rooms);

    return Scaffold(
      backgroundColor: colors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ShowcaseSlider(
              images: business?.showcaseUrls ?? const [],
              colors: colors,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        business?.businessName ?? '',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colors.textPrimary),
                      ),
                    ),
                    if (business?.isVerified == true)
                      Icon(Icons.verified, color: colors.accent, size: 18),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (business != null && business.averageRating > 0) ...[
                      RatingStars(rating: business.averageRating, size: 14),
                      const SizedBox(width: 5),
                      Text(business.averageRating.toStringAsFixed(1), style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(width: 10),
                    ],
                    Text('Stay', style: TextStyle(fontSize: 13, color: colors.textTertiary)),
                  ]),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _RoomExplorer(
              rooms: state.rooms,
              floorRooms: floorRooms,
              floors: floors,
              selectedFloor: effectiveFloor,
              selectedRoomId: _selectedRoomId,
              onFloorChanged: (floor) => setState(() => _selectedFloor = floor),
              onRoomSelected: (room) => _selectRoom(room, floors),
              colors: colors,
            ),
          ),
          SliverToBoxAdapter(
            child: _BookingPanel(
              colors: colors,
              checkIn: _checkIn,
              checkOut: _checkOut,
              nights: _nights,
              selectedRoom: selectedRoom,
              isBooking: state.isBooking,
              onDates: _selectDates,
              onConfirm: _confirmBooking,
              penaltyText: business?.businessMeta?['penaltyPolicy'] is Map
                  ? 'No-show policy applies according to the hotel\'s published terms.'
                  : null,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _loading(dynamic colors) {
    return Scaffold(
      backgroundColor: colors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 54),
            SkeletonBlock(height: 220, width: double.infinity, borderRadius: BorderRadius.circular(20)),
            const SizedBox(height: 18),
            SkeletonBlock(height: 24, width: 180, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 14),
            SkeletonBlock(height: 150, width: double.infinity, borderRadius: BorderRadius.circular(18)),
            const SizedBox(height: 12),
            SkeletonBlock(height: 150, width: double.infinity, borderRadius: BorderRadius.circular(18)),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseSlider extends StatefulWidget {
  final List<String> images;
  final dynamic colors;
  const _ShowcaseSlider({required this.images, required this.colors});

  @override
  State<_ShowcaseSlider> createState() => _ShowcaseSliderState();
}

class _ShowcaseSliderState extends State<_ShowcaseSlider> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        height: 220,
        color: widget.colors.accent.withValues(alpha: 0.1),
        child: Center(child: Icon(Icons.hotel, size: 52, color: widget.colors.accent)),
      );
    }
    return Stack(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) => AzamanNetworkImage(
              imageUrl: widget.images[index],
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: widget.images.asMap().entries.map((entry) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.key == _index ? Colors.white : Colors.white54,
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _RoomExplorer extends StatelessWidget {
  final List<HotelRoom> rooms;
  final List<HotelRoom> floorRooms;
  final List<int> floors;
  final int? selectedFloor;
  final String? selectedRoomId;
  final ValueChanged<int> onFloorChanged;
  final ValueChanged<HotelRoom> onRoomSelected;
  final dynamic colors;

  const _RoomExplorer({
    required this.rooms,
    required this.floorRooms,
    required this.floors,
    required this.selectedFloor,
    required this.selectedRoomId,
    required this.onFloorChanged,
    required this.onRoomSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(children: [
            Icon(Icons.hotel_outlined, size: 44, color: colors.textTertiary),
            const SizedBox(height: 10),
            Text('No room inventory has been published yet.', style: TextStyle(color: colors.textSecondary)),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Choose your room', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: colors.textPrimary))),
          if (floorRooms.isNotEmpty)
            Text('${floorRooms.where((r) => r.isBookable).length} available', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
        ]),
        const SizedBox(height: 12),
        if (floors.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: floors.map((floor) {
                final selected = floor == selectedFloor;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('Floor $floor'),
                    selected: selected,
                    onSelected: (_) => onFloorChanged(floor),
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : colors.textSecondary),
                    selectedColor: colors.accent,
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            if (selectedFloor != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.stairs_outlined, size: 16, color: colors.textTertiary),
                const SizedBox(width: 6),
                Text('Floor $selectedFloor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textTertiary)),
              ]),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: floorRooms.map((room) => _RoomTile(
                room: room,
                selected: room.id == selectedRoomId,
                onTap: () => onRoomSelected(room),
                colors: colors,
              )).toList(),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (selectedRoomId != null)
          ...floorRooms.where((room) => room.id == selectedRoomId).map((room) => _RoomDetailCard(
            room: room,
            colors: colors,
          )),
      ]),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final HotelRoom room;
  final bool selected;
  final VoidCallback onTap;
  final dynamic colors;

  const _RoomTile({required this.room, required this.selected, required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    final accent = selected ? colors.accent : colors.divider;
    final disabled = !room.isBookable;
    return SizedBox(
      width: 86,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: 180.ms,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: disabled ? colors.card.withValues(alpha: 0.45) : selected ? colors.accent.withValues(alpha: 0.1) : colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: disabled ? 0.35 : selected ? 0.9 : 0.5), width: selected ? 1.5 : 0.6),
          ),
        child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(disabled ? Icons.lock_outline : Icons.hotel_outlined, size: 15, color: disabled ? colors.textTertiary : colors.textSecondary),
              const SizedBox(width: 4),
              Text(room.roomNumber, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: disabled ? colors.textTertiary : colors.textPrimary)),
            ]),
            const SizedBox(height: 5),
            Text(room.displayType, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: colors.textTertiary)),
            const SizedBox(height: 5),
            Text('${room.basePriceUsdc.toStringAsFixed(0)} USDC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: disabled ? colors.textTertiary : colors.accent)),
          ]),
        ),
      ),
    );
  }
}

class _RoomDetailCard extends StatelessWidget {
  final HotelRoom room;
  final dynamic colors;

  const _RoomDetailCard({required this.room, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.accent.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (room.primaryImage != null)
          AzamanNetworkImage(imageUrl: room.primaryImage!, height: 180, width: double.infinity, fit: BoxFit.cover),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${room.displayType} • Room ${room.roomNumber}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colors.textPrimary))),
              Text('${room.basePriceUsdc.toStringAsFixed(2)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.accent)),
            ]),
            const SizedBox(height: 4),
            Text('per night', style: TextStyle(fontSize: 11, color: colors.textTertiary)),
            if (room.bedConfig != null) ...[
              const SizedBox(height: 9),
              Row(children: [Icon(Icons.bed_outlined, size: 16, color: colors.textTertiary), const SizedBox(width: 6), Text(room.bedConfig!, style: TextStyle(fontSize: 12, color: colors.textSecondary))]),
            ],
            const SizedBox(height: 8),
            Row(children: [Icon(Icons.people_outline, size: 16, color: colors.textTertiary), const SizedBox(width: 6), Text('${room.capacity} guest${room.capacity == 1 ? '' : 's'} max', style: TextStyle(fontSize: 12, color: colors.textSecondary))]),
            if (room.amenities.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, children: room.amenities.take(8).map((amenity) => Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_hotelAmenityIcon(amenity), size: 14, color: colors.textTertiary),
                const SizedBox(width: 4),
                Text(amenity, style: TextStyle(fontSize: 11, color: colors.textTertiary)),
              ])).toList()),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _BookingPanel extends StatelessWidget {
  final dynamic colors;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final HotelRoom? selectedRoom;
  final bool isBooking;
  final VoidCallback onDates;
  final VoidCallback onConfirm;
  final String? penaltyText;

  const _BookingPanel({
    required this.colors,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.selectedRoom,
    required this.isBooking,
    required this.onDates,
    required this.onConfirm,
    this.penaltyText,
  });

  String _date(DateTime? value) => value == null ? '' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final canBook = selectedRoom != null && selectedRoom!.isBookable && checkIn != null && checkOut != null && nights > 0 && !isBooking;
    final estimated = selectedRoom == null ? 0 : selectedRoom!.basePriceUsdc * nights;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your stay', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.textPrimary)),
        const SizedBox(height: 12),
        InkWell(
          onTap: onDates,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(border: Border.all(color: colors.divider), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.calendar_month_outlined, size: 18, color: colors.textTertiary),
              const SizedBox(width: 10),
              Expanded(child: Text(checkIn == null ? 'Select check-in and check-out dates' : '${_date(checkIn)} → ${_date(checkOut)}', style: TextStyle(color: checkIn == null ? colors.textTertiary : colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        if (penaltyText != null) ...[
          const SizedBox(height: 11),
          Row(children: [Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700), const SizedBox(width: 7), Expanded(child: Text(penaltyText!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900)))]),
        ],
        if (selectedRoom != null && nights > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${selectedRoom!.basePriceUsdc.toStringAsFixed(2)} USDC × $nights night${nights == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                Text('${estimated.toStringAsFixed(2)} USDC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textPrimary)),
              ]),
              if (selectedRoom!.weekendPriceUsdc != null && selectedRoom!.weekendPriceUsdc != selectedRoom!.basePriceUsdc) ...[
                const SizedBox(height: 6),
                Text('Final total uses the hotel\'s date-specific rate calendar.', style: TextStyle(fontSize: 10, color: colors.textTertiary)),
              ],
              const Divider(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Estimated total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                Text('${estimated.toStringAsFixed(2)} USDC', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: colors.accent)),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canBook ? onConfirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: isBooking
                ? const SizedBox(height: 19, width: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(canBook ? 'Reserve room' : 'Choose a room and dates', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
