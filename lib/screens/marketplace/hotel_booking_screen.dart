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

  IconData _amenityIcon(String amenity) {
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
          // Room type cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Available Rooms', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              final room = products[i];
              final isSelected = _selectedRoomId == room.id;
              return GestureDetector(
                onTap: () => setState(() => _selectedRoomId = room.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        if (room.imageUrl != null)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                            child: CachedNetworkImage(imageUrl: room.imageUrl!,
                              height: 160, width: double.infinity, fit: BoxFit.cover),
                          ),
                        // Selected checkmark overlay
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
                              // Room type badge
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
                            // Amenities with icons
                            if (room.amenities != null && room.amenities!.isNotEmpty)
                              Wrap(spacing: 12, runSpacing: 6, children: room.amenities!.map((a) {
                                final icon = _amenityIcon(a);
                                return Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(icon, size: 14, color: colors.textTertiary),
                                  const SizedBox(width: 4),
                                  Text(a, style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                                ]);
                              }).toList()),
                            const SizedBox(height: 12),
                            Row(children: [
                              Text('${room.priceUsdc.toStringAsFixed(2)} USDC',
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
            }, childCount: products.length),
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
        itemBuilder: (_, i) => CachedNetworkImage(imageUrl: widget.images[i],
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