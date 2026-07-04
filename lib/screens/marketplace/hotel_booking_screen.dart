// lib/screens/marketplace/hotel_booking_screen.dart
// =============================================================================
// HOTEL BOOKING SCREEN — AZAMAN Marketplace v2
// Shows: showcase slideshow → room type cards → date picker → booking summary
// with escrow deposit + penalty policy → confirm booking
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/premium_shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
  int _nights = 0;

  void _selectDate(DateTime date) {
    AzamanHaptics.toggle();
    setState(() {
      if (_checkIn == null || (_checkIn != null && _checkOut != null)) { _checkIn = date; _checkOut = null; }
      else if (date.isAfter(_checkIn!)) { _checkOut = date; }
      else { _checkIn = date; _checkOut = null; }
      _nights = _checkIn != null && _checkOut != null ? _checkOut!.difference(_checkIn!).inDays : 0;
    });
  }

  void _bookRoom(BusinessProduct room) {
    setState(() => _selectedRoomId = room.id);
    _confirmBooking();
  }

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

    );
    if (picked != null) setState(() { _checkIn = picked.start; _checkOut = picked.end; });
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
        context.pushReplacement('/marketplace/booking/checkin-qr/${booking.id}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e')),
      );
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(marketplaceBookingProvider);
    final business = state.business;
    final products = state.products ?? [];

    if (state.isLoading) return Scaffold(
      backgroundColor: colors.background,
      body: const Center(child: CircularProgressIndicator()),
    );

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
                      Text('${business.averageRating.toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                    ],
                    const SizedBox(width: 8),
                    Text('${business?.categoryLabel ?? ""}',
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _premiumRoomCard(room, colors),
              );
            }, childCount: products.length),
          ),
          // Date Picker
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _premiumDateRangePicker(colors),
            ),
          ),
          // Penalty policy
          if (business?.penaltyPolicy != null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
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
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
  Widget _premiumDateRangePicker(AzamanColors colors) {
    return PremiumGlassContainer(
      blur: 12, opacity: 0.04, borderRadius: 16, padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: colors.accent),
            const SizedBox(width: 8),
            Text('Select Dates', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.textPrimary)),
            const Spacer(),
            Text('$_nights nights', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 30, separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final date = DateTime.now().add(Duration(days: i));
                final isCheckIn = _checkIn?.day == date.day && _checkIn?.month == date.month;
                final isCheckOut = _checkOut?.day == date.day && _checkOut?.month == date.month;
                final isInRange = _checkIn != null && _checkOut != null && date.isAfter(_checkIn!) && date.isBefore(_checkOut!);
                return GestureDetector(
                  onTap: () => _selectDate(date),
                  child: AnimatedContainer(
                    duration: 200.ms, width: 52,
                    decoration: BoxDecoration(
                      color: (isCheckIn || isCheckOut) ? colors.accent : isInRange ? colors.accentSurface : colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: (isCheckIn || isCheckOut) ? Colors.transparent : colors.divider),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][date.weekday - 1],
                          style: TextStyle(fontSize: 9, color: (isCheckIn || isCheckOut) ? colors.background.withOpacity(0.7) : colors.textTertiary)),
                        const SizedBox(height: 2),
                        Text('${date.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                          color: (isCheckIn || isCheckOut) ? colors.background : colors.textPrimary)),
                        Text(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.month - 1],
                          style: TextStyle(fontSize: 9, color: (isCheckIn || isCheckOut) ? colors.background.withOpacity(0.7) : colors.textTertiary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumRoomCard(BusinessProduct room, AzamanColors colors) {
    return PremiumGlassContainer(
      blur: 12, opacity: 0.04, borderRadius: 18, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: room.imageUrls.isNotEmpty
                ? CachedNetworkImage(imageUrl: room.imageUrls.first, width: 80, height: 80, fit: BoxFit.cover,
                    placeholder: (_, __) => PremiumShimmerBox(width: 80, height: 80, radius: 12))
                : Container(width: 80, height: 80, color: colors.softSurface, child: Icon(Icons.bed_outlined, size: 28, color: colors.textTertiary)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(room.description ?? 'Comfortable room with all amenities',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.king_bed_outlined, size: 13, color: colors.textTertiary), const SizedBox(width: 3),
                    Text('2 guests', style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                    const SizedBox(width: 10),
                    Icon(Icons.square_foot_outlined, size: 13, color: colors.textTertiary), const SizedBox(width: 3),
                    Text('30m²', style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('\$${room.priceUsdc.toStringAsFixed(0)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.accent)),
              Text('/ night', style: TextStyle(fontSize: 11, color: colors.textTertiary)),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: _checkIn != null && _checkOut != null ? () => _bookRoom(room) : null,
              child: AnimatedContainer(
                duration: 200.ms, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                  color: _checkIn != null && _checkOut != null ? colors.accent : colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _checkIn != null && _checkOut != null ? Colors.transparent : colors.divider),
                ),
                child: _loading && _selectedRoomId == room.id
                    ? SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.background))
                    : Text('Book', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                        color: _checkIn != null && _checkOut != null ? colors.background : colors.textTertiary)),
              ),
            ),
          ]),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideY(begin: 0.1, end: 0, delay: 100.ms, duration: 300.ms);
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
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(height: 220, color: widget.colors.accent.withValues(alpha: 0.1),
        child: Center(child: Icon(Icons.hotel, size: 48, color: widget.colors.accent)));
    }
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24), topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32),
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.images[i], fit: BoxFit.cover,
                  placeholder: (_, __) => PremiumShimmerBox(width: double.infinity, height: 220, radius: 24),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.images.length, (i) => AnimatedContainer(
            duration: 300.ms, margin: const EdgeInsets.only(right: 5),
            width: _index == i ? 20 : 6, height: 6,
            decoration: BoxDecoration(
              color: _index == i ? widget.colors.accent : widget.colors.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
