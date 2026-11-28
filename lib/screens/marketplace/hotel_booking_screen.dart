// =============================================================================
// HOTEL BOOKING — dates and guests first, then a room, then the request.
//
// The order a guest decides in: when, how many, which room. The room picker
// shows which rooms are free for those dates and that group (the server's
// stay quote: taken, closed or too small rooms are greyed, with the reason),
// and the total is the server's own per-night price.
//
// Paying (the quote says payAt APP): "Pay $X" charges price + Azaman fee from
// the wallet behind the second factor; the money is held until the guest
// checks in with their QR, and the stay is confirmed at once (its QR is
// ready). A server without in-app pay answers payAt HOTEL: the stay is then a
// request the hotel confirms, paid at the hotel.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart'
    show HotelBookingFailureClass;
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hotel_marketplace_provider.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/widgets/marketplace/store_order_pay.dart'
    show storeUsdcLabel;
import 'package:azaman/widgets/security/second_factor.dart';
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

  /// Replaces the second-factor sheet (tests).
  final Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  secondFactorPrompt;

  const HotelBookingScreen({
    super.key,
    required this.bizId,
    this.secondFactorPrompt,
  });

  @override
  ConsumerState<HotelBookingScreen> createState() => _HotelBookingScreenState();
}

class _HotelBookingScreenState extends ConsumerState<HotelBookingScreen> {
  DateTime? _checkIn;
  DateTime? _checkOut;
  String? _selectedRoomId;
  int _guests = 1;

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
    Future.microtask(
      () => ref.read(hotelMarketplaceProvider.notifier).load(widget.bizId),
    );
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
    _setDates(picked.start, picked.end);
  }

  void _setDates(DateTime start, DateTime end) {
    setState(() {
      _checkIn = DateTime(start.year, start.month, start.day);
      _checkOut = DateTime(end.year, end.month, end.day);
    });
    _syncStayDecision();
  }

  void _setGuests(int n, int max) {
    final next = n.clamp(1, max);
    if (next == _guests) return;
    AzamanHaptics.selection();
    setState(() => _guests = next);
    _syncStayDecision();
  }

  /// Mirrors the local picks into the UI-only [StayDecision] (Overhaul 03
  /// §4.1) so the step indicator and docks derive from one object. Price and
  /// availability authority stays with the server (stay quote).
  void _syncStayDecision() {
    ref.read(stayDecisionProvider(widget.bizId).notifier).state = StayDecision(
      checkIn: _checkIn,
      checkOut: _checkOut,
      guests: _guests,
      roomId: _selectedRoomId,
    );
  }

  int get _nights {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays;
  }

  String? get _quoteKey => _nights > 0
      ? stayQuoteKey(widget.bizId, _checkIn!, _checkOut!, _guests)
      : null;

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
    final floorMates = rooms
        .where((r) => r.floor == room.floor)
        .toList(growable: false);
    showMarketplaceDossierSheet(
      context,
      presentation: MarketplaceDetailPresentation.roomDossier,
      title: '${room.displayType} · Room ${room.roomNumber}',
      colors: colors,
      tempo: MarketplaceMotionTempo.relaxed,
      content: (_) => RoomDossierContent(
        room: room,
        floorMates: floorMates,
        colors: colors,
      ),
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

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/business-market');
    }
  }

  Future<void> _confirmBooking() async {
    final state = ref.read(hotelMarketplaceProvider);
    final room = _selectedRoom(state.rooms);
    if (room == null || _checkIn == null || _checkOut == null || _nights < 1) {
      return;
    }
    final key = _quoteKey;
    final quote = key == null
        ? null
        : ref.read(stayQuoteProvider(key)).valueOrNull;
    final roomQuote = quote?.rooms[room.id];
    final payTotal = roomQuote?.payTotalUsdc;
    final paying = quote?.payInApp == true && payTotal != null;
    final notifier = ref.read(hotelMarketplaceProvider.notifier);

    Future<Map<String, dynamic>> reserve({Map<String, String>? factor}) =>
        notifier.reserve(
          bizId: widget.bizId,
          roomId: room.id,
          checkIn: _checkIn!,
          checkOut: _checkOut!,
          partySize: _guests,
          operationType: _bookingOperationType,
          ref: _bookingRef,
          payWithWallet: paying,
          expectedTotalUsdc: paying ? payTotal : null,
          secondFactor: factor,
        );

    try {
      Map<String, dynamic>? reservation;
      if (paying) {
        final label = 'Pay ${storeUsdcLabel(payTotal)}';
        reservation = await withSecondFactor<Map<String, dynamic>>(
          context,
          initial: secondFactorKindFor(ref.read(authProvider).user),
          title: label,
          actionLabel: label,
          detail: 'Held until you check in with your QR.',
          ask: widget.secondFactorPrompt,
          attempt: (f) => reserve(factor: f.toWire()),
        );
        if (reservation == null) return; // closed the second factor
      } else {
        reservation = await reserve();
      }
      if (!mounted) return;

      final amount = _reservationAmount(reservation['amountUsdc']);
      final reservationId = (reservation['id'] ?? '').toString();
      if (reservationId.isEmpty) {
        throw StateError('Reservation response did not include an id.');
      }
      // The hub's Reservations tab lists it from now on.
      ref.invalidate(myReservationsProvider);

      final choice = await HotelArrivalSheet.show(
        context,
        reservationRef:
            ((reservation['reservationRef'] ?? reservationId).toString())
                .split('-')
                .last,
        room: room,
        checkIn: _checkIn!,
        nights: _nights,
        totalUsdc: amount,
        hotelName: state.business?.businessName,
        guests: _guests,
        paidUsdc: paying ? payTotal : null,
      );
      if (!mounted) return;
      if (choice == 'qr') {
        // A paid stay is confirmed: its check-in QR exists now.
        context.push('/marketplace/booking/checkin-qr/$reservationId');
      } else if (choice == 'bookings') {
        context.push('/bookings?tab=reservations');
      }
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      // Paying: a short balance offers a top-up; a changed price re-prices.
      if (e is ApiException && e.code == 'INSUFFICIENT_BALANCE') {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Not enough in your wallet for this stay. Nothing was charged.',
            ),
            action: SnackBarAction(
              label: 'Add money',
              onPressed: () => context.push('/deposit'),
            ),
          ),
        );
        return;
      }
      if (e is ApiException && e.code == 'PRICE_CHANGED' && key != null) {
        ref.invalidate(stayQuoteProvider(key));
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'The price changed. Check the new total, then pay. Nothing was charged.',
            ),
          ),
        );
        return;
      }
      if (e is ApiException &&
          const {
            'BOOKED',
            'BLOCKED',
            'ROOM_UNAVAILABLE',
            'TOO_SMALL',
          }.contains(e.code) &&
          key != null) {
        ref.invalidate(stayQuoteProvider(key));
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      // Economic failure presentation (deep-dive step 6, parity with the
      // transit taxonomy): an UNPROVEN outcome (transport loss, 5xx,
      // 408/425, malformed success) must NOT be asserted as a failed
      // reservation — the room MAY be booked. The durable ref stays armed,
      // so retrying the SAME room and dates reuses the same key and
      // converges (the backend replays the committed reservation exactly).
      final failed = ref.read(hotelMarketplaceProvider);
      final cls = failed.bookingFailureClass;
      String message = (failed.error ?? 'Unable to complete the booking.')
          .replaceFirst('HotelMarketplaceException: ', '');
      if (e is ApiException) message = e.message;
      if (cls == HotelBookingFailureClass.ambiguousOrUnknown) {
        message =
            'We couldn\'t confirm your booking. Check Orders & bookings first. '
            'If it isn\'t there, booking the same room and dates again '
            'safely reuses your request (you are never charged twice).';
      } else if (cls == HotelBookingFailureClass.domainConflict) {
        message =
            'This booking conflicts with an earlier one. Check Orders & '
            'bookings before booking again.';
      } else if (cls == HotelBookingFailureClass.authenticationRequired) {
        message =
            'Please sign in again, then book the same room and dates. Your '
            'request will be safely reused.';
      } else if (cls == HotelBookingFailureClass.rateLimited) {
        message =
            'Too many attempts. Wait a moment, then book the same room and '
            'dates. Your request will be safely reused.';
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(hotelMarketplaceProvider);

    if (state.isLoading && state.business == null) return _loading(colors);

    final business = state.business;
    final key = _quoteKey;
    final quoteAsync = key == null ? null : ref.watch(stayQuoteProvider(key));
    final quote = quoteAsync?.valueOrNull;
    final pricing = quoteAsync != null && quoteAsync.isLoading;

    // Rooms as the guest can book them for these dates and this group.
    final rooms = quote == null
        ? state.rooms
        : [
            for (final r in state.rooms)
              (quote.rooms[r.id]?.bookable ?? r.isBookable)
                  ? r
                  : r.unavailableForStay(),
          ];
    final selectedRoom = _selectedRoom(state.rooms);
    final roomQuote = selectedRoom == null
        ? null
        : quote?.rooms[selectedRoom.id];
    final payInApp = quote?.payInApp == true;
    final unavailable = quoteAsync?.hasError == true
        ? 'Could not price these dates'
        : (roomQuote != null && !roomQuote.bookable
              ? roomQuote.reasonLabel ?? 'Not available for these dates'
              : null);
    final maxGuests = state.rooms.isEmpty
        ? 10
        : state.rooms
              .map((r) => r.capacity)
              .reduce((a, b) => a > b ? a : b)
              .clamp(1, 20);

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
        quotedTotalUsdc: payInApp
            ? (roomQuote?.payTotalUsdc ?? roomQuote?.totalUsdc)
            : roomQuote?.totalUsdc,
        pricing: pricing,
        unavailableReason: unavailable,
        ctaLabel: payInApp && roomQuote?.payTotalUsdc != null
            ? 'Pay ${storeUsdcLabel(roomQuote!.payTotalUsdc!)}'
            : 'Request stay',
        note: payInApp
            ? 'Held until you check in'
                  '${roomQuote?.feeUsdc != null ? ' · fee ${storeUsdcLabel(roomQuote!.feeUsdc!)}' : ''}'
            : 'The hotel confirms · pay at the hotel',
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: colors.surface,
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.black.withValues(alpha: 0.35),
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('hotel-back'),
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _back,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _ShowcaseSlider(
                images: business?.showcaseUrls ?? const [],
                colors: colors,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          business?.businessName ?? '',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (business?.isVerified == true)
                        Icon(Icons.verified, color: colors.accent, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (business != null && business.averageRating > 0) ...[
                        RatingStars(rating: business.averageRating, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          business.averageRating.toStringAsFixed(1),
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        'Stay',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
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
          // 1. When, and how many.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        key: const ValueKey('hotel-pick-dates'),
                        tooltip: 'Pick exact dates',
                        onPressed: _selectDates,
                        icon: Icon(
                          Icons.calendar_month_outlined,
                          size: 20,
                          color: colors.textTertiary,
                        ),
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
                    onRangeChanged: (range) =>
                        _setDates(range.start, range.end),
                    onNightAdded: () => AzamanHaptics.threshold(),
                    colors: colors,
                  ),
                  const SizedBox(height: AzSpace.md),
                  _GuestsRow(
                    guests: _guests,
                    max: maxGuests,
                    colors: colors,
                    onChanged: (n) => _setGuests(n, maxGuests),
                  ),
                  if (penaltyText != null) ...[
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            penaltyText,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 2. Which room, among those free for those dates and that group.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a room',
                    style: AzText.title.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _nights == 0
                        ? 'Pick your dates first to see which rooms are free.'
                        : pricing
                        ? 'Checking which rooms are free…'
                        : 'Greyed rooms are taken, closed or too small for '
                              '$_guests ${_guests == 1 ? 'guest' : 'guests'}.',
                    key: const ValueKey('hotel-rooms-hint'),
                    style: AzText.caption.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AzSpace.sm),
                  BuildingCrossSection(
                    rooms: rooms,
                    selectedRoomId: _selectedRoomId,
                    onRoomTap: _openRoomDossier,
                    colors: colors,
                  ),
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
            SkeletonBlock(
              height: 220,
              width: double.infinity,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 18),
            SkeletonBlock(
              height: 24,
              width: 180,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 14),
            SkeletonBlock(
              height: 150,
              width: double.infinity,
              borderRadius: BorderRadius.circular(18),
            ),
            const SizedBox(height: 12),
            SkeletonBlock(
              height: 150,
              width: double.infinity,
              borderRadius: BorderRadius.circular(18),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestsRow extends StatelessWidget {
  const _GuestsRow({
    required this.guests,
    required this.max,
    required this.colors,
    required this.onChanged,
  });
  final int guests;
  final int max;
  final dynamic colors;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Guests',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('guests-minus'),
            tooltip: 'Fewer guests',
            onPressed: guests > 1 ? () => onChanged(guests - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$guests',
              key: const ValueKey('guests-count'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFeatures: AzText.tabular,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('guests-plus'),
            tooltip: 'More guests',
            onPressed: guests < max ? () => onChanged(guests + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
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
      return Container(
        height: 220,
        color: widget.colors.accent.withValues(alpha: 0.1),
        child: Center(
          child: Icon(Icons.hotel, size: 52, color: widget.colors.accent),
        ),
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
            children: widget.images
                .asMap()
                .entries
                .map(
                  (entry) => Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: entry.key == _index
                          ? Colors.white
                          : Colors.white54,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
