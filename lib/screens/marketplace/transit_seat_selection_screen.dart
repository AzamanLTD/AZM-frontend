// =============================================================================
// AZAMAN — TRANSIT SEAT SELECTION SCREEN
//
// Shows a visual seat map grid. Customer taps available seats to select/deselect.
// When done, taps "Book" to reserve the seats atomically.
//
// The DB-level @@unique([tripId, seatId]) constraint makes double-booking
// structurally impossible — if someone races you, you get a clean error.
//
// 2026-07-07: added tier-aware pricing (Economy/Standard/VIP — each seat can
//             carry its own fare) and pinch-zoom/pan via InteractiveViewer so
//             larger vehicle layouts are comfortable on small screens.
// 2026-07-11: replaced icon-based seat chips with premium SVG seat assets.
//             AVAILABLE → assets/icons/seats/seat_available.svg
//             SELECTED  → assets/icons/seats/seat_selected.svg  (pre-designed, no runtime tint)
//             OCCUPIED  → assets/icons/seats/seat_occupied.svg
//             BLOCKED   → assets/icons/seats/seat_blocked.svg
//             VIP badge → drawn procedurally (star from seat_vip.svg) as overlay
//             ColorFiltered wrapping removed entirely — icons are pre-designed per-state.
//             Haptic lightImpact on every valid tap.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:intl/intl.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';
import "package:azaman/widgets/seat_selector/seat_layout_models.dart" show VehicleLayout;

Color _tierColor(SeatTier tier) {
  switch (tier) {
    case SeatTier.vip:      return const Color(0xFFF59E0B);
    case SeatTier.standard: return const Color(0xFF3B82F6);
    case SeatTier.economy:  return const Color(0xFF22C55E);
  }
}

// ── SCREEN ───────────────────────────────────────────────────────────────────

class TransitSeatSelectionScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TransitSeatSelectionScreen({super.key, required this.tripId});

  @override
  ConsumerState<TransitSeatSelectionScreen> createState() =>
      _TransitSeatSelectionScreenState();
}

class _TransitSeatSelectionScreenState
    extends ConsumerState<TransitSeatSelectionScreen> {
  final _passengerNames = <String, TextEditingController>{};
  SeatSelectorController? _seatController;

  // Cached VehicleLayout — prevents rebuilding the layout object on every
  // build() cycle, which would cause BusSeatSelector to think the entire
  // vehicle changed and reload from scratch on every seat tap.
  VehicleLayout? _cachedLayout;
  String? _cachedLayoutKey;

  /// Build (or return cached) VehicleLayout from seat availability data.
  /// The cache key includes trip ID, seat count, and every seat's ID + status,
  /// so the layout is only rebuilt when the actual seat data changes.
  VehicleLayout _layoutFor(
    SeatAvailability availability,
    TransitTrip? trip,
  ) {
    final key = '${widget.tripId}-${availability.seats.length}-'
        '${availability.seats.map((s) => '${s.seatId}:${s.status}').join(',')}';
    if (_cachedLayout != null && _cachedLayoutKey == key) {
      return _cachedLayout!;
    }
    final layout = vehicleLayoutFromSeats(
      layoutId: 'trip-${widget.tripId}',
      seats: availability.seats,
      vehicleMake: trip?.vehicleMake,
      vehicleModel: trip?.vehicleModel,
    );
    _cachedLayout = layout;
    _cachedLayoutKey = key;
    return layout;
  }

  @override
  void dispose() {
    for (final c in _passengerNames.values) {
      c.dispose();
    }
    _seatController?.dispose();
    super.dispose();
  }

  /// Sync seat selection from BusSeatSelector → Riverpod + passenger names
  void _onSelectionChanged(Set<String> selected) {
    // Access the controller's selected seats (it's the source of truth)
    ref.read(selectedSeatsProvider.notifier).update((_) => selected);

    // Add TextEditingControllers for new seats, remove for deselected
    final existing = _passengerNames.keys.toSet();
    for (final id in selected) {
      _passengerNames.putIfAbsent(id, () => TextEditingController());
    }
    for (final id in existing.difference(selected)) {
      _passengerNames[id]?.dispose();
      _passengerNames.remove(id);
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  double _totalFare(SeatAvailability a, Set<String> selected) {
    double total = 0;
    for (final id in selected) {
      final seat = a.seats.where((s) => s.seatId == id).firstOrNull;
      total += seat?.fare ?? a.fareUsdc;
    }
    return total;
  }

  Widget _bookingListener(SeatAvailability availability) {
    ref.listen(bookingActionProvider, (_, state) {
      if (!mounted) return;
      final colors = ref.read(themeProvider.select((t) => t.colors));
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error!
                .replaceFirst('MarketplaceBookingException: ', '')),
            backgroundColor: colors.danger,
          ),
        );
      } else if (state.result != null) {
        final result = state.result!;
        final total = _totalFare(availability, ref.read(selectedSeatsProvider));

        // Try to get trip details for the success sheet
        final tripDetail = ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
        final route = tripDetail != null
            ? '${tripDetail.origin} → ${tripDetail.destination}'
            : 'Trip ${widget.tripId}';
        final departureTime = tripDetail?.departureAt ?? DateTime.now();

        // Invalidate the seats provider so they refresh on next visit
        ref.invalidate(seatAvailabilityProvider(widget.tripId));

        // Show the celebration sheet instead of a plain SnackBar
        BookingSuccessSheet.show(
          context,
          bookingRef: result.bookingRef,
          seatCount: result.seatIds.length,
          totalFare: total,
          route: route,
          departureTime: departureTime,
        );
      }
    });
    return const SizedBox.shrink();
  }

  Future<void> _bookSeats(SeatAvailability availability) async {
    final selected = ref.read(selectedSeatsProvider);
    final seatIds = selected.toList();
    final names = seatIds
        .map((id) => _passengerNames[id]?.text.trim() ?? '')
        .toList();
    final hasNames = names.any((name) => name.isNotEmpty);
    await ref.read(bookingActionProvider.notifier).bookSeats(
          tripId: widget.tripId,
          seatIds: seatIds,
          passengerNames: hasNames ? names : null,
        );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final seatsAsync = ref.watch(seatAvailabilityProvider(widget.tripId));
    final selectedSeats = ref.watch(selectedSeatsProvider);
    final bookingState = ref.watch(bookingActionProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Select Seats',
            style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actions: seatsAsync.valueOrNull != null
            ? [
                IconButton(
                  tooltip: 'Reset view',
                  icon: Icon(Icons.center_focus_strong_rounded,
                      color: colors.textSecondary),
                  onPressed: () => _seatController?.resetView(),
                ),
              ]
            : null,
      ),
      body: seatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                  err
                      .toString()
                      .replaceFirst('MarketplaceBookingException: ', ''),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref
                    .invalidate(seatAvailabilityProvider(widget.tripId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (availability) {
          final tripDetail = ref.watch(tripDetailProvider(widget.tripId)).valueOrNull;

          // Empty-seats guard: show a clean empty state rather than feeding
          // a degenerate layout into the geometry solver.
          if (availability.seats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_seat_outlined, size: 48, color: colors.textTertiary),
                    const SizedBox(height: 16),
                    Text(
                      'No seats available for this trip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This trip may be fully booked or not yet configured.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          // Initialize the seat controller with the vehicle layout on first build
          final layout = _layoutFor(availability, tripDetail);
          _seatController ??= SeatSelectorController()..loadLayout(layout);
          return Column(
          children: [
            _bookingListener(availability),

            // ── Trip / vehicle header card ──────────────────────────────
            _TripVehicleHeader(
              trip: tripDetail,
              availability: availability,
              colors: colors,
            ),

            // ── High-performance seat selector (Canvas + CustomPaint) ──────
            Expanded(
              child: BusSeatSelector(
                layout: layout,
                controller: _seatController,
                accentColor: colors.accent,
                surfaceColor: colors.surface,
                cardColor: colors.card,
                dividerColor: colors.divider,
                textPrimary: colors.textPrimary,
                textSecondary: colors.textSecondary,
                textTertiary: colors.textTertiary,
                successColor: colors.success,
                dangerColor: colors.danger,
                backgroundColor: colors.background,
                showMinimap: true,
                showLegend: true,
                showCheckoutDock: true,
                isBooking: bookingState.isLoading,
                onSelectionChanged: _onSelectionChanged,
                onBook: (seats, total) => _bookSeats(availability),
              ),
            ),

            // ── Selected seats summary (enhanced 2026-08-23) ──────────────
            // Card-style rows with tier pills, filled TextField, running subtotal
            if (selectedSeats.isNotEmpty) ...[
              Container(
                width: double.infinity,
                // Dynamic height: ~56px per row + 80px header/subtotal, capped at 320
                constraints: BoxConstraints(
                  maxHeight: (selectedSeats.length * 56 + 80).clamp(120, 320).toDouble(),
                ),
                padding: const EdgeInsets.all(16),
                color: colors.surface,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Passenger Names (optional)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                              fontSize: 13)),
                      const SizedBox(height: 10),
                      // ── Seat rows as cards with tier-colored pills ──
                      ...selectedSeats.map((seatId) {
                        final seat = availability.seats
                            .where((s) => s.seatId == seatId)
                            .firstOrNull;
                        final tierColor = seat != null ? _tierColor(seat.tier) : colors.accent;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: colors.divider, width: 0.8),
                            ),
                            child: Row(children: [
                              // ── Tier-colored seat pill ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: tierColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  seatId,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: tierColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // ── Fare with tabular figures ──
                              if (seat != null)
                                Text(
                                  '\$${seat.fare.toStringAsFixed(0)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textTertiary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ]),
                                ),
                              const SizedBox(width: 10),
                              // ── Borderless filled TextField ──
                              Expanded(
                                child: TextField(
                                  controller: _passengerNames.putIfAbsent(
                                      seatId,
                                      () => TextEditingController()),
                                  decoration: InputDecoration(
                                    hintText: 'Name for seat $seatId',
                                    isDense: true,
                                    filled: true,
                                    fillColor: colors.softSurface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: colors.accent,
                                          width: 1.5),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                  ),
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                            ]),
                          ),
                        );
                      }),
                      // ── Subtotal line ──
                      const SizedBox(height: 6),
                      Divider(color: colors.divider, height: 1, thickness: 0.5),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Subtotal',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary)),
                          const Spacer(),
                          Text(
                            '\$${_totalFare(availability, selectedSeats).toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: colors.accent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          );
        },
      ),
    );
  }
}

// ── TRIP / VEHICLE HEADER ─────────────────────────────────────────────────────

class _TripVehicleHeader extends StatelessWidget {
  final TransitTrip? trip;
  final SeatAvailability availability;
  final AzamanColors colors;

  const _TripVehicleHeader({
    required this.trip,
    required this.availability,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final hasTiers = availability.tierFares.isNotEmpty;
    final dateFormat = DateFormat('EEE, MMM d · h:mm a');
    final departure = trip?.departureAt ?? DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route + vehicle
          Row(
            children: [
              // Vehicle image
              if (trip?.vehicleImageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AzamanNetworkImage(
                    imageUrl: trip!.vehicleImageUrl!,
                    width: 52, height: 52, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 52, height: 52,
                      color: colors.card,
                      child: Icon(Icons.directions_bus, color: colors.accent, size: 24),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 52, height: 52,
                      color: colors.card,
                      child: Icon(Icons.directions_bus, color: colors.accent, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.directions_bus_rounded, color: colors.accent, size: 24),
                ),
                const SizedBox(width: 12),
              ],
              // Route info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (trip != null)
                      Text(
                        '${trip!.origin} → ${trip!.destination}',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      )
                    else
                      Text('Select Your Seats',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    if (trip?.vehicleMake != null && trip?.vehicleModel != null)
                      Text(
                        '${trip!.vehicleMake} ${trip!.vehicleModel}',
                        style: TextStyle(fontSize: 11, color: colors.textSecondary),
                      )
                    else
                      Text(
                        '${availability.availableCount} of ${availability.totalSeats} seats available',
                        style: TextStyle(fontSize: 11, color: colors.textSecondary),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      dateFormat.format(departure),
                      style: TextStyle(fontSize: 11, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              // Fare
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasTiers
                        ? 'from \$${_minFareStr(availability)}/seat'
                        : '\$${availability.fareUsdc.toStringAsFixed(0)}/seat',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${availability.availableCount} avail',
                    style: TextStyle(fontSize: 11, color: colors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
          // ── Vehicle & Crew strip (enhanced 2026-08-23) ───────────────
          // Single compact row: plate chip + grouped avatar(s) + name + verified
          if (trip?.driverName != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // ── License plate chip (only if plateNumber != null) ──
                  if (trip?.plateNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.softSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.divider, width: 1.5),
                      ),
                      child: Text(
                        trip!.plateNumber!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // ── Grouped driver + co-driver avatars ──
                  SizedBox(
                    width: trip?.coDriverName != null ? 46 : 28,
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Co-driver avatar (behind, shifted right for overlap)
                        if (trip?.coDriverName != null)
                          Positioned(
                            left: 18,
                            child: _crewAvatar(
                              trip?.coDriverPhotoUrl,
                              colors,
                              size: 28,
                            ),
                          ),
                        // Driver avatar (in front, z-index higher)
                        Positioned(
                          left: 0,
                          child: _crewAvatar(
                            trip?.driverPhotoUrl,
                            colors,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ── Name + role label ──
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            trip!.driverName!,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trip?.coDriverName != null ? '· Driver & Co-driver' : '· Driver',
                          style: TextStyle(fontSize: 11, color: colors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.verified_rounded, size: 14, color: colors.accent),
                  const SizedBox(width: 4),
                  Text('Verified',
                    style: TextStyle(fontSize: 10, color: colors.accent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _minFareStr(SeatAvailability a) {
    if (a.tierFares.isEmpty) return a.fareUsdc.toStringAsFixed(0);
    final fares = a.tierFares.values.toList()..sort();
    return fares.first.toStringAsFixed(0);
  }

  // ── Helper: build a crew avatar (driver or co-driver) ──────────────
  Widget _crewAvatar(String? photoUrl, AzamanColors colors, {double size = 28}) {
    if (photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: AzamanNetworkImage(
          imageUrl: photoUrl,
          width: size, height: size, fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: size, height: size,
            color: colors.surface,
            child: Icon(Icons.person, size: size * 0.55, color: colors.textSecondary),
          ),
          errorWidget: (_, __, ___) => Container(
            width: size, height: size,
            color: colors.surface,
            child: Icon(Icons.person, size: size * 0.55, color: colors.textSecondary),
          ),
        ),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: Icon(Icons.person, size: size * 0.55, color: colors.textSecondary),
    );
  }
}
