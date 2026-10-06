import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart' show HotelBookingFailureClass;
import 'package:azaman/providers/hotel_marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/marketplace/building_cross_section.dart';
import 'package:azaman/widgets/marketplace/hotel_arrival_sheet.dart';
import 'package:azaman/widgets/marketplace/marketplace_dossier_sheet.dart';
import 'package:azaman/widgets/marketplace/room_dossier_content.dart';
import 'package:azaman/widgets/marketplace/stay_date_ribbon.dart';
import 'package:azaman/marketplace/experiences/hotel/stay_decision.dart';
import 'package:azaman/widgets/marketplace/stay_step_indicator.dart';
import 'package:azaman/widgets/marketplace/stay_summary_bar.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

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

  /// ONE logical booking intent for the life of this screen (deep-dive
  /// step 6, parity with TransitSeatSelectionScreen._bookingRef): the
  /// durable instance this screen's reservation retries converge on. A
  /// materially changed room/dates/party begins a GENUINELY new
  /// operation; the unfinished old instance stays journal-recoverable.
  final FinancialOperationRef _bookingRef = FinancialOperationRef();
  static const _bookingOperationType = 'hotel.reserve_room';

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
    _syncStayDecision();
  }

  /// Mirrors the local picks into the UI-only [StayDecision] (Overhaul 03
  /// §4.1) so the step indicator and docks derive from one object. Price and
  /// availability authority stays with `hotelMarketplaceProvider`.
  void _syncStayDecision() {
    ref.read(stayDecisionProvider(widget.bizId).notifier).state = StayDecision(
      checkIn: _checkIn,
      checkOut: _checkOut,
      roomId: _selectedRoomId,
    );
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

  void _selectRoom(HotelRoom room) {
    if (!room.isBookable) return;
    setState(() => _selectedRoomId = room.id);
    _syncStayDecision();
  }

  void _openRoomDossier(HotelRoom room) {
    if (!room.isBookable) return;
    AzamanHaptics.selection();
    final colors = ref.read(themeProvider).colors;
    final rooms = ref.read(hotelMarketplaceProvider).rooms;
    final floorMates =
        rooms.where((r) => r.floor == room.floor).toList(growable: false);
    showMarketplaceDossierSheet(
      context,
      presentation: MarketplaceDetailPresentation.roomDossier,
      title: '${room.displayType} · Room ${room.roomNumber}',
      colors: colors,
      tempo: MarketplaceMotionTempo.relaxed,
      content: (_) => RoomDossierContent(
          room: room, floorMates: floorMates, colors: colors),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _selectRoom(room);
          },
          icon: const Icon(Icons.key_rounded),
          label: const Text('Select this room'),
        ),
      ),
    );
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
            operationType: _bookingOperationType,
            ref: _bookingRef,
          );
      if (!mounted) return;

      final amount = _reservationAmount(reservation['amountUsdc']);
      final reservationId = (reservation['id'] ?? '').toString();
      if (reservationId.isEmpty) throw StateError('Reservation response did not include an id.');

      HotelArrivalSheet.show(
        context,
        reservationRef: ((reservation['reservationRef'] ?? reservationId).toString()).split('-').last,
        room: room,
        checkIn: _checkIn!,
        nights: _nights,
        totalUsdc: amount,
      );

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) context.pushReplacement('/marketplace/booking/checkin-qr/$reservationId');
      });
    } catch (_) {
      if (!mounted) return;
      // Economic failure presentation (deep-dive step 6, parity with the
      // transit taxonomy): an UNPROVEN outcome (transport loss, 5xx,
      // 408/425, malformed success) must NOT be asserted as a failed
      // reservation — the room MAY be booked. The durable ref stays armed,
      // so retrying the SAME room and dates reuses the same key and
      // converges (the backend replays the committed reservation exactly).
      // 409 (key used for a materially different reservation) and
      // 401/429 get their own guidance; a definitive pre-economic 4xx
      // surfaces the backend's own message.
      final state = ref.read(hotelMarketplaceProvider);
      final cls = state.bookingFailureClass;
      String message =
          (state.error ?? 'Unable to complete the booking.')
              .replaceFirst('HotelMarketplaceException: ', '');
      if (cls == HotelBookingFailureClass.ambiguousOrUnknown) {
        message =
            'We couldn\'t confirm your reservation. Check your bookings first — '
            'if it isn\'t there, booking the same room and dates again will '
            'safely reuse your request.';
      } else if (cls == HotelBookingFailureClass.domainConflict) {
        message =
            'This reservation request conflicts with an earlier one. Check '
            'your bookings before booking again.';
      } else if (cls == HotelBookingFailureClass.authenticationRequired) {
        message =
            'Please sign in again, then book the same room and dates — your '
            'request will be safely reused.';
      } else if (cls == HotelBookingFailureClass.rateLimited) {
        message =
            'Too many attempts. Wait a moment, then book the same room and '
            'dates — your request will be safely reused.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(hotelMarketplaceProvider);

    if (state.isLoading && state.business == null) return _loading(colors);

    final business = state.business;
    final selectedRoom = _selectedRoom(state.rooms);
    final penaltyText = business?.businessMeta?['penaltyPolicy'] is Map
        ? 'No-show policy applies according to the hotel\'s published terms.'
        : null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      backgroundColor: colors.background,
      bottomNavigationBar: StaySummaryBar(
        room: selectedRoom,
        checkIn: _checkIn,
        checkOut: _checkOut,
        nights: _nights,
        isBooking: state.isBooking,
        onReserve: _confirmBooking,
        colors: colors,
      ),
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
                  const SizedBox(height: 12),
                  // Stay story (Overhaul 03 §4.6), derived — never a second
                  // source of truth for the booking.
                  StayStepIndicator(
                    current: ref
                        .watch(stayDecisionProvider(widget.bizId))
                        .stepFor(confirmed: false),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: BuildingCrossSection(
                rooms: state.rooms,
                selectedRoomId: _selectedRoomId,
                onRoomTap: _openRoomDossier,
                colors: colors,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your stay',
                          style: AzText.title.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pick exact dates',
                        onPressed: _selectDates,
                        icon: Icon(Icons.calendar_month_outlined,
                            size: 20, color: colors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AzSpace.sm),
                  StayDateRibbon(
                    firstDay: today,
                    checkIn: _checkIn,
                    checkOut: _checkOut,
                    nightlyRate: selectedRoom?.basePriceUsdc,
                    weekendRate: selectedRoom?.weekendPriceUsdc,
                    onRangeChanged: (range) => setState(() {
                      _checkIn = range.start;
                      _checkOut = range.end;
                    }),
                    onNightAdded: () => AzamanHaptics.threshold(),
                    colors: colors,
                  ),
                  if (penaltyText != null) ...[
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            penaltyText,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (selectedRoom != null &&
                      selectedRoom.weekendPriceUsdc != null &&
                      selectedRoom.weekendPriceUsdc !=
                          selectedRoom.basePriceUsdc) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Final total uses the hotel\'s date-specific rate calendar.',
                      style: AzText.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
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
