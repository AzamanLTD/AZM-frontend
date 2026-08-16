// lib/screens/marketplace/hotel_booking_screen.dart
// =============================================================================
// HOTEL BOOKING SCREEN — AZAMAN Marketplace v2
// Shows: showcase slideshow → room type cards → date picker → booking summary
// with escrow deposit + penalty policy → confirm booking
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

// Top-level amenity icon helper — shared across hotel widgets
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
  if (a.contains('kitchen') || a.contains('kitchenette')) return Icons.kitchen;
  if (a.contains('bar')) return Icons.local_bar;
  if (a.contains('pet')) return Icons.pets;
  if (a.contains('smoke')) return Icons.smoke_free;
  return Icons.check_circle_outline;
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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(marketplaceBookingProvider.notifier)
        .loadBusinessDetail(widget.bizId));
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 1))),
    );
    if (picked != null) setState(() { _checkIn = picked.start; _checkOut = picked.end; });
  }

  // _amenityIcon moved to top-level _hotelAmenityIcon below

  int get _nightsCount {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays;
  }

  Future<void> _confirmBooking() async {
    if (_checkIn == null || _checkOut == null || _selectedRoomId == null) return;
    setState(() => _loading = true);
    try {
      final booking = await ref.read(marketplaceBookingProvider.notifier)
          .createHotelReservation(
            bizId: widget.bizId,
            checkIn: _checkIn!,
            checkOut: _checkOut!,
            productId: _selectedRoomId!,
          );
      if (mounted) {
        // Show celebration sheet, then navigate to QR
        final nights = _checkOut!.difference(_checkIn!).inDays;
        final products = ref.read(marketplaceBookingProvider).products ?? [];
        final room = products.firstWhere((p) => p.id == _selectedRoomId, orElse: () => products.first);
        BookingSuccessSheet.show(
          context,
          bookingRef: booking.id.substring(0, 8).toUpperCase(),
          seatCount: 1,
          totalFare: (room.priceUsdc as double) * (nights > 0 ? nights : 1),
          route: '${room.name} x $nights night${nights > 1 ? 's' : ''}',
          departureTime: _checkIn!,
        );
        // Navigate to QR after a delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) context.pushReplacement('/marketplace/booking/checkin-qr/${booking.id}');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e')),
      );
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(marketplaceBookingProvider);
    final business = state.business;
    final products = state.products ?? [];

    if (state.isLoading) {
      return Scaffold(
      backgroundColor: colors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            SkeletonBlock(height: 180, width: double.infinity, borderRadius: BorderRadius.circular(20)),
            const SizedBox(height: 16),
            SkeletonBlock(height: 20, width: 160, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 8),
            SkeletonBlock(height: 14, width: 200, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 20),
            SkeletonBlock(height: 80, width: double.infinity, borderRadius: BorderRadius.circular(14)),
            const SizedBox(height: 12),
            SkeletonBlock(height: 80, width: double.infinity, borderRadius: BorderRadius.circular(14)),
          ],
        ),
      ),
    );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: CustomScrollView(
        slivers: [
          // Showcase Slideshow
          SliverToBoxAdapter(
            child: _ShowcaseSlider(images: business?.showcaseUrls ?? [], colors: colors),
          ),
          // Business info header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(business?.businessName ?? '',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.textPrimary))),
                      if (business?.isVerified == true)
                        Icon(Icons.verified, color: colors.accent, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (business?.averageRating != null && business!.averageRating > 0) ...[
                      RatingStars(rating: business.averageRating, size: 14),
                      const SizedBox(width: 4),
                      Text(business.averageRating.toStringAsFixed(1),
                        style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                    ],
                    const SizedBox(width: 8),
                    Text(business?.categoryLabel ?? "",
                      style: TextStyle(fontSize: 13, color: colors.textTertiary)),
                  ]),
                ],
              ),
            ),
          ),
          // 2D Floor Plan + Room cards
          SliverToBoxAdapter(
            child: _HotelFloorPlan(
              products: products.cast<BusinessProduct>().toList(),
              selectedRoomId: _selectedRoomId,
              onRoomSelected: (id) => setState(() => _selectedRoomId = id),
              colors: colors,
            ),
          ),
          // Date picker + penalty policy + CTA
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider, width: 0.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Select Dates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _selectDates,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.divider), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, color: colors.textTertiary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        _checkIn != null && _checkOut != null
                            ? '${_checkIn!.toString().split(" ")[0]} → ${_checkOut!.toString().split(" ")[0]}'
                            : 'Tap to select check-in and check-out',
                        style: TextStyle(fontSize: 14, color: _checkIn != null ? colors.textPrimary : colors.textTertiary),
                      )),
                    ]),
                  ),
                ),
                // Penalty policy
                if (business?.penaltyPolicy != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'No-show penalty: ${(business!.penaltyPolicy!.penaltyPct * 100).toStringAsFixed(0)}% of deposit. '
                        'Grace period: ${business.penaltyPolicy!.gracePeriodMins} min after check-in window.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
                    ]),
                  ),
                ],
                // Price breakdown
                if (_checkIn != null && _checkOut != null && _selectedRoomId != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Price Breakdown',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      const SizedBox(height: 8),
                      (() {
                        final nights = _nightsCount;
                        final products = state.products ?? [];
                        final room = products.firstWhere((p) => p.id == _selectedRoomId, orElse: () => products.first);
                        final pricePerNight = room.priceUsdc as double;
                        final total = pricePerNight * (nights > 0 ? nights : 1);
                        return Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('$pricePerNight USDC x $nights night${nights > 1 ? 's' : ''}',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                            Text('$total USDC',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                          ]),
                          const Divider(height: 16),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Total',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                            Text('$total USDC',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.accent)),
                          ]),
                        ]);
                      })(),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_checkIn != null && _checkOut != null && _selectedRoomId != null && !_loading)
                        ? _confirmBooking : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Confirm Booking', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ],
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
      return Container(height: 220, color: widget.colors.accent.withValues(alpha: 0.1),
        child: Center(child: Icon(Icons.hotel, size: 48, color: widget.colors.accent)));
    }
    return Stack(children: [
      SizedBox(height: 220, child: PageView.builder(
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => AzamanNetworkImage(imageUrl: widget.images[i],
          height: 220, width: double.infinity, fit: BoxFit.cover),
      )),
      Positioned(bottom: 10, left: 0, right: 0, child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: widget.images.asMap().entries.map((e) =>
          Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: e.key == _index ? Colors.white : Colors.white54,
            ))).toList(),
      )),
    ]);
  }
}

// ── 2D HOTEL FLOOR PLAN ────────────────────────────────────────────────────────

class _HotelFloorPlan extends StatefulWidget {
  final List<BusinessProduct> products;
  final String? selectedRoomId;
  final void Function(String id) onRoomSelected;
  final AzamanColors colors;

  const _HotelFloorPlan({
    required this.products,
    required this.selectedRoomId,
    required this.onRoomSelected,
    required this.colors,
  });

  @override
  State<_HotelFloorPlan> createState() => _HotelFloorPlanState();
}

class _HotelFloorPlanState extends State<_HotelFloorPlan> {
  int _selectedFloor = 1;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final products = widget.products;

    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.hotel_outlined, size: 40, color: colors.textTertiary),
              const SizedBox(height: 10),
              Text('No rooms available', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    // Parse room numbers from product names (e.g. "Room 101" → floor 1, room 1)
    final floorMap = <int, List<BusinessProduct>>{};
    for (final p in products) {
      final match = RegExp(r'Room\s+(\d+)').firstMatch(p.name);
      int floor = 1;
      if (match != null) {
        final roomNum = int.tryParse(match.group(1)!) ?? 1;
        floor = roomNum ~/ 100;
        if (floor < 1) floor = 1;
      }
      floorMap.putIfAbsent(floor, () => []).add(p);
    }

    final floors = floorMap.keys.toList()..sort();
    if (floors.isEmpty) {
      // Fallback: just show a list
      return Column(
        children: products.map((p) => _roomCard(p, colors)).toList(),
      );
    }

    final floorRooms = floorMap[_selectedFloor] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text('Available Rooms', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          const SizedBox(height: 12),

          // Floor selector tabs
          Row(
            children: floors.map((f) {
              final isSel = f == _selectedFloor;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedFloor = f),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? colors.accent : colors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? colors.accent : colors.divider,
                        width: isSel ? 0 : 0.5,
                      ),
                    ),
                    child: Text(
                      'Floor \$f',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // 2D floor plan — hallway with rooms on both sides
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.divider.withValues(alpha: 0.3), width: 1),
            ),
            child: Column(
              children: [
                // Floor label
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.stairs_outlined, size: 16, color: colors.textTertiary),
                    const SizedBox(width: 6),
                    Text('Floor \$_selectedFloor — \${floorRooms.length} rooms',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 12),
                // Rooms grid — 2 columns representing left/right side of hallway
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side rooms
                    Expanded(
                      child: Column(
                        children: [
                          for (int i = 0; i < floorRooms.length; i += 2)
                            _floorRoomTile(floorRooms[i], colors),
                        ],
                      ),
                    ),
                    // Hallway
                    Container(
                      width: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors.divider.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Icon(Icons.elevator_outlined, size: 14, color: colors.textTertiary),
                          const SizedBox(height: 40),
                          Icon(Icons.stairs_outlined, size: 14, color: colors.textTertiary),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    // Right side rooms
                    Expanded(
                      child: Column(
                        children: [
                          for (int i = 1; i < floorRooms.length; i += 2)
                            _floorRoomTile(floorRooms[i], colors),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Selected room detail card
          if (widget.selectedRoomId != null)
            ...widget.products.where((p) => p.id == widget.selectedRoomId).map((p) => _roomCard(p, colors))
          else
            ...floorRooms.take(2).map((p) => _roomCard(p, colors)),
        ],
      ),
    );
  }

  // ── Floor room tile (compact, in the floor plan) ──────────────────────
  Widget _floorRoomTile(BusinessProduct room, AzamanColors colors) {
    final isSelected = widget.selectedRoomId == room.id;
    final match = RegExp(r'(\d+)').firstMatch(room.name);
    final roomNum = match?.group(1) ?? '?';

    // Parse room type for color
    final isDeluxe = room.tags.any((t) => t.toLowerCase().contains('deluxe'));
    final isStandard = room.tags.any((t) => t.toLowerCase().contains('standard'));
    Color typeColor = colors.accent;
    if (isDeluxe) typeColor = const Color(0xFFF59E0B);
    else if (isStandard) typeColor = const Color(0xFF3B82F6);

    return GestureDetector(
      onTap: () => widget.onRoomSelected(room.id),
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? typeColor.withValues(alpha: 0.12) : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? typeColor : colors.divider.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            // Room number
            Text(roomNum,
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: isSelected ? typeColor : colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            // Price
            Text('\$\${room.priceUsdc.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: isSelected ? typeColor : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Room detail card (expanded, below floor plan) ─────────────────────
  Widget _roomCard(BusinessProduct room, AzamanColors colors) {
    final isSelected = widget.selectedRoomId == room.id;
    return GestureDetector(
      onTap: () => widget.onRoomSelected(room.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? colors.accent : colors.divider,
            width: isSelected ? 2 : 0.5,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [
              if (room.primaryImage != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: AzamanNetworkImage(imageUrl: room.primaryImage!,
                    height: 160, width: double.infinity, fit: BoxFit.cover),
                ),
              if (isSelected)
                Positioned(top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  )).animate().scale(duration: 200.ms),
            ]),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (room.category != null)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(room.category!,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors.accent)),
                      ),
                    Expanded(child: Text(room.name, style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary))),
                  ]),
                  if (room.description != null) ...[
                    const SizedBox(height: 6),
                    Text(room.description!, style: TextStyle(
                      fontSize: 13, color: colors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 10),
                  if (room.tags.isNotEmpty)
                    Wrap(spacing: 12, runSpacing: 6, children: room.tags.map((a) {
                      final icon = _hotelAmenityIcon(a);
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 14, color: colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(a, style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                      ]);
                    }).toList()),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('\${room.priceUsdc.toStringAsFixed(2)} USDC',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.accent)),
                    const SizedBox(width: 4),
                    Text('/ night',
                      style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
