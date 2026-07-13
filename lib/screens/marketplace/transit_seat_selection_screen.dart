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
// 2026-07-11: replaced icon-based seat chips with premium PNG seat assets.
//             BOOKED  → assets/images/booked.png  (occupied silhouette)
//             AVAILABLE → assets/images/unbooked.png  (empty dark seat)
//             SELECTED  → unbooked.png + ColorFiltered purple tint (0.5 opacity)
//             Haptic lightImpact on every valid tap.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// Azaman brand purple — used for SELECTED tint overlay
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

  @override
  void dispose() {
    for (final c in _passengerNames.values) c.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  double _minFare(SeatAvailability a) =>
      a.tierFares.values.isNotEmpty ? a.tierFares.values.reduce((x, y) => x < y ? x : y) : a.fareUsdc;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Booked ${result.seatIds.length} seat(s)! Ref: ${result.bookingRef}'),
            backgroundColor: colors.accent,
          ),
        );
        context.go('/marketplace/transit');
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
                      Text(
                          '\$${_totalFare(seatsAsync.valueOrNull!, selectedSeats).toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: colors.accent)),
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
                                        colors.accent.withOpacity(0.25),
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
        data: (availability) => Column(
          children: [
            _bookingListener(availability),

            // Trip info header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: colors.surface,
              child: Row(children: [
                Icon(Icons.event_seat, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                    '${availability.availableCount} of ${availability.totalSeats} available',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary)),
                const Spacer(),
                Text(
                  availability.tierFares.isEmpty
                      ? '\$${availability.fareUsdc.toStringAsFixed(2)}/seat'
                      : 'from \$${_minFare(availability).toStringAsFixed(2)}/seat',
                  style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),

            // ── Pinch-to-zoom seat map ──────────────────────────────────
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
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Selected seats + passenger names
            if (selectedSeats.isNotEmpty) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
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
                      const SizedBox(height: 8),
                      ...selectedSeats.map((seatId) {
                        final seat = availability.seats
                            .where((s) => s.seatId == seatId)
                            .firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(
                              width: 56,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(seatId,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colors.accent)),
                                  if (seat != null)
                                    Text(
                                        '\$${seat.fare.toStringAsFixed(0)}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: _tierColor(seat.tier))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _passengerNames.putIfAbsent(
                                    seatId,
                                    () => TextEditingController()),
                                decoration: InputDecoration(
                                  hintText:
                                      'Passenger name for seat $seatId',
                                  isDense: true,
                                  border:
                                      const OutlineInputBorder(),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                ),
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 13),
                              ),
                            ),
                          ]),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── SEAT MAP GRID ─────────────────────────────────────────────────────────────

class _SeatMapGrid extends StatelessWidget {
  final List<TransitSeat> seats;
  final Set<String> selectedSeats;
  final void Function(String seatId, SeatStatus status) onSeatTap;

  const _SeatMapGrid({
    required this.seats,
    required this.selectedSeats,
    required this.onSeatTap,
  });

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final colors = ref.read(themeProvider.select((t) => t.colors));

    // Group seats by row
    final rowMap = <int, List<TransitSeat>>{};
    for (final seat in seats) {
      rowMap.putIfAbsent(seat.row, () => []).add(seat);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    final hasTiers = seats.any((s) => s.tier != SeatTier.economy);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Driver indicator
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.airline_seat_recline_normal,
                  color: colors.textSecondary, size: 20),
              const SizedBox(width: 4),
              Text('Driver',
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 12)),
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
                image: 'assets/images/unbooked.png',
                label: hasTiers ? 'Economy' : 'Available',
                colors: colors),
            _legendItem(
                color: _kSelectedPurple.withOpacity(0.8),
                label: 'Selected',
                colors: colors),
            _legendItem(
                image: 'assets/images/booked.png',
                label: 'Occupied',
                colors: colors),
            if (seats.any((s) => s.status == SeatStatus.blocked))
              _legendItem(
                  color: colors.danger,
                  label: 'Blocked',
                  colors: colors),
          ],
        ),
      ],
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
    String? image,
    Color? color,
    required String label,
    required dynamic colors,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (image != null)
          Image.asset(image, width: 18, height: 18)
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

    // ── Base seat image ───────────────────────────────────────────────
    Widget seatImage;

    if (isOccupied) {
      // Booked: show occupied silhouette, dimmed slightly
      seatImage = Opacity(
        opacity: 0.75,
        child: Image.asset(
          'assets/images/booked.png',
          width: 50,
          height: 50,
          fit: BoxFit.contain,
        ),
      );
    } else if (isSelected) {
      // Selected: unbooked seat + purple tint overlay
      seatImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          _kSelectedPurple.withOpacity(0.50),
          BlendMode.srcATop,
        ),
        child: Image.asset(
          'assets/images/unbooked.png',
          width: 50,
          height: 50,
          fit: BoxFit.contain,
        ),
      );
    } else if (isBlocked) {
      // Blocked: unbooked seat, heavily dimmed + red tint
      seatImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.red.withOpacity(0.55),
          BlendMode.srcATop,
        ),
        child: Opacity(
          opacity: 0.5,
          child: Image.asset(
            'assets/images/unbooked.png',
            width: 50,
            height: 50,
            fit: BoxFit.contain,
          ),
        ),
      );
    } else {
      // Available: clean unbooked seat
      seatImage = Image.asset(
        'assets/images/unbooked.png',
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
              color: _kSelectedPurple.withOpacity(0.40),
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
