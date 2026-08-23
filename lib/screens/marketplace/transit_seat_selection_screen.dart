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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

// Azaman brand purple — used for selected seat label + glow accent
const _kSelectedPurple = Color(0xFF7C3AED);

Color _tierColor(SeatTier tier) {
  switch (tier) {
    case SeatTier.vip:      return const Color(0xFFF59E0B);
    case SeatTier.standard: return const Color(0xFF3B82F6);
    case SeatTier.economy:  return const Color(0xFF22C55E);
  }
}

String _tierLabel(SeatTier tier) {
  switch (tier) {
    case SeatTier.vip:      return 'VIP';
    case SeatTier.standard: return 'Standard';
    case SeatTier.economy:  return 'Economy';
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
  final _transformController = TransformationController();
  // ── Animated checkout total (enhanced 2026-08-23) ──
  // Tracks previous total for TweenAnimationBuilder digit-roll
  double _previousTotal = 0;

  @override
  void dispose() {
    for (final c in _passengerNames.values) {
      c.dispose();
    }
    _transformController.dispose();
    super.dispose();
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

  void _onSeatTap(String seatId, SeatStatus status) {
    if (status != SeatStatus.available) return;
    HapticFeedback.lightImpact();
    ref.read(selectedSeatsProvider.notifier).update((seats) {
      final next = Set<String>.from(seats);
      if (next.contains(seatId)) {
        next.remove(seatId);
      } else {
        next.add(seatId);
      }
      return next;
    });
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
                  tooltip: 'Reset zoom',
                  icon: Icon(Icons.center_focus_strong_rounded,
                      color: colors.textSecondary),
                  onPressed: () =>
                      _transformController.value = Matrix4.identity(),
                ),
              ]
            : null,
      ),
      bottomNavigationBar: seatsAsync.valueOrNull != null
          ? PremiumGlassContainer(
              blur: 24,
              opacity: 0.08,
              borderRadius: 0,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              enableShadow: false,
              border: Border(
                  top: BorderSide(color: colors.divider, width: 0.5)),
              child: SafeArea(
                child: Row(children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '${selectedSeats.length} seat${selectedSeats.length == 1 ? "" : "s"}',
                          style: TextStyle(
                              fontSize: 12, color: colors.textTertiary)),
                      // ── Animated total (enhanced 2026-08-23) ──
                      // TweenAnimationBuilder for smooth digit-roll, NOT a
                      // looping animation — triggers only on actual value change
                      Builder(builder: (context) {
                        final currentTotal = _totalFare(seatsAsync.valueOrNull!, selectedSeats);
                        final tween = Tween<double>(begin: _previousTotal, end: currentTotal);
                        if (_previousTotal != currentTotal) {
                          _previousTotal = currentTotal;
                        }
                        return TweenAnimationBuilder<double>(
                          tween: tween,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Text(
                              '\$${value.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: colors.accent,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: (selectedSeats.isNotEmpty &&
                            !bookingState.isLoading)
                        ? () => _bookSeats(seatsAsync.valueOrNull!)
                        : null,
                    child: AnimatedContainer(
                      duration: 200.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: selectedSeats.isEmpty
                            ? colors.card
                            : colors.accent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: selectedSeats.isNotEmpty
                            ? [
                                BoxShadow(
                                    color:
                                        colors.accent.withValues(alpha: 0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4))
                              ]
                            : null,
                      ),
                      child: bookingState.isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.background))
                          : Text('Book Now',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: selectedSeats.isEmpty
                                      ? colors.textTertiary
                                      : colors.background)),
                    ),
                  ),
                ]),
              ),
            )
          : null,
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
          return Column(
          children: [
            _bookingListener(availability),

            // ── Trip / vehicle header card ──────────────────────────────
            _TripVehicleHeader(
              trip: tripDetail,
              availability: availability,
              colors: colors,
            ),

            // ── Pinch-to-zoom seat map inside vehicle body ─────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  minScale: 0.8,
                  maxScale: 3.0,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _SeatMapGrid(
                        seats: availability.seats,
                        selectedSeats: selectedSeats,
                        onSeatTap: _onSeatTap,
                        colors: colors,
                      ),
                    ),
                  ),
                ),
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

// ── SEAT MAP GRID ─────────────────────────────────────────────────────────────

class _SeatMapGrid extends StatelessWidget {
  final List<TransitSeat> seats;
  final Set<String> selectedSeats;
  final void Function(String seatId, SeatStatus status) onSeatTap;
  final AzamanColors colors;

  const _SeatMapGrid({
    required this.seats,
    required this.selectedSeats,
    required this.onSeatTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = this.colors;

    // Group seats by row
    final rowMap = <int, List<TransitSeat>>{};
    for (final seat in seats) {
      rowMap.putIfAbsent(seat.row, () => []).add(seat);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    final hasTiers = seats.any((s) => s.tier != SeatTier.economy);

    return Container(
      // ── Vehicle body outline ────────────────────────────────────────
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.divider.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Windshield / front of vehicle
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_bus_rounded,
                    color: colors.accent, size: 18),
                const SizedBox(width: 6),
                Text('Front of Vehicle',
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Seat rows
          ...sortedRows.map((rowNum) {
            final rowSeats = rowMap[rowNum]!
              ..sort((a, b) => a.col.compareTo(b.col));
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:
                    _buildRowWithAisle(rowSeats, selectedSeats),
              ),
            );
          }),

          const SizedBox(height: 24),

          // Legend — uses mini seat images instead of colour chips
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 8,
            children: [
              _legendItem(
                  svg: 'assets/icons/seats/seat_available.svg',
                  label: hasTiers ? 'Economy' : 'Available',
                  colors: colors),
              _legendItem(
                  svg: 'assets/icons/seats/seat_selected.svg',
                  label: 'Selected',
                  colors: colors),
              _legendItem(
                  svg: 'assets/icons/seats/seat_occupied.svg',
                  label: 'Occupied',
                  colors: colors),
              if (seats.any((s) => s.status == SeatStatus.blocked))
                _legendItem(
                    svg: 'assets/icons/seats/seat_blocked.svg',
                    label: 'Blocked',
                    colors: colors),
              if (hasTiers)
                _legendItem(
                    svg: 'assets/icons/seats/seat_vip.svg',
                    label: 'VIP',
                    colors: colors),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRowWithAisle(
      List<TransitSeat> rowSeats, Set<String> selectedSeats) {
    final widgets = <Widget>[];
    for (int i = 0; i < rowSeats.length; i++) {
      widgets.add(_SeatWidget(
        seat: rowSeats[i],
        isSelected: selectedSeats.contains(rowSeats[i].seatId),
        onTap: () => onSeatTap(rowSeats[i].seatId, rowSeats[i].status),
      ));
      if (i == 0 && rowSeats.length > 2) {
        // Aisle gap after the first seat
        widgets.add(const SizedBox(width: 28));
      } else if (i < rowSeats.length - 1) {
        widgets.add(const SizedBox(width: 6));
      }
    }
    return widgets;
  }

  Widget _legendItem({
    String? svg,
    Color? color,
    required String label,
    required dynamic colors,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (svg != null)
          SvgPicture.asset(svg, width: 18, height: 18)
        else
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4)),
          ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: colors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ── INDIVIDUAL SEAT WIDGET ────────────────────────────────────────────────────

class _SeatWidget extends StatelessWidget {
  final TransitSeat seat;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeatWidget({
    required this.seat,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = seat.status == SeatStatus.occupied;
    final isBlocked = seat.status == SeatStatus.blocked;
    final isDisabled = isOccupied || isBlocked;

    // ── Base seat SVG (pre-designed per-state, no runtime tinting) ──────
    Widget seatImage;

    if (isOccupied) {
      seatImage = SvgPicture.asset(
        'assets/icons/seats/seat_occupied.svg',
        width: 50,
        height: 50,
        fit: BoxFit.contain,
      );
    } else if (isSelected) {
      seatImage = SvgPicture.asset(
        'assets/icons/seats/seat_selected.svg',
        width: 50,
        height: 50,
        fit: BoxFit.contain,
      );
    } else if (isBlocked) {
      seatImage = SvgPicture.asset(
        'assets/icons/seats/seat_blocked.svg',
        width: 50,
        height: 50,
        fit: BoxFit.contain,
      );
    } else {
      seatImage = SvgPicture.asset(
        'assets/icons/seats/seat_available.svg',
        width: 50,
        height: 50,
        fit: BoxFit.contain,
      );
    }

    // ── Seat label (id) overlaid below the image ──────────────────────
    final seatLabel = Text(
      seat.seatId,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        color: isSelected
            ? _kSelectedPurple
            : isDisabled
                ? Colors.grey
                : _tierColor(seat.tier),
        letterSpacing: 0.3,
      ),
    );

    // ── Animate scale on selection ────────────────────────────────────
    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        seatImage,
        const SizedBox(height: 2),
        seatLabel,
      ],
    );

    child = child
        .animate(target: isSelected ? 1.0 : 0.0)
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.12, 1.12),
          duration: 140.ms,
          curve: Curves.easeOutBack,
        );

    // ── Glow effect behind selected seat ─────────────────────────────
    if (isSelected) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _kSelectedPurple.withValues(alpha: 0.40),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: child,
      );
    }

    return Tooltip(
      message: isOccupied
          ? '${seat.seatId} — Occupied'
          : isBlocked
              ? '${seat.seatId} — Blocked'
              : '${seat.seatId} — ${_tierLabel(seat.tier)} · \$${seat.fare.toStringAsFixed(0)}',
      child: GestureDetector(
        onTap: isDisabled ? null : onTap,
        child: child,
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
