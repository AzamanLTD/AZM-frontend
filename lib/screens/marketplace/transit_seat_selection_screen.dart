// =============================================================================
// AZAMAN — TRANSIT SEAT SELECTION SCREEN (2026-07-02)
//
// Shows a visual seat map grid. Customer taps available seats to select/deselect.
// When done, taps "Book" to reserve the seats atomically.
//
// The DB-level @@unique([tripId, seatId]) constraint makes double-booking
// structurally impossible — if someone races you, you get a clean error.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class TransitSeatSelectionScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TransitSeatSelectionScreen({super.key, required this.tripId});

  @override
  ConsumerState<TransitSeatSelectionScreen> createState() => _TransitSeatSelectionScreenState();
}

class _TransitSeatSelectionScreenState extends ConsumerState<TransitSeatSelectionScreen> {
  final _passengerNames = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _passengerNames.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final seatsAsync = ref.watch(seatAvailabilityProvider(widget.tripId));
    final selectedSeats = ref.watch(selectedSeatsProvider);
    final bookingState = ref.watch(bookingActionProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Select Seats', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      bottomNavigationBar: seatsAsync.valueOrNull != null ? PremiumGlassContainer(
        blur: 24, opacity: 0.08, borderRadius: 0,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), enableShadow: false,
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
        child: SafeArea(child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${selectedSeats.length} seat${selectedSeats.length == 1 ? "" : "s"}', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
            Text('\$${(selectedSeats.length * seatsAsync.valueOrNull!.fareUsdc).toStringAsFixed(0)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.accent)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: (selectedSeats.isNotEmpty && !bookingState.isLoading) ? () => _bookSeats(seatsAsync.valueOrNull!) : null,
            child: AnimatedContainer(
              duration: 200.ms, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: selectedSeats.isEmpty ? colors.card : colors.accent, borderRadius: BorderRadius.circular(14),
                boxShadow: selectedSeats.isNotEmpty ? [BoxShadow(color: colors.accent.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4))] : null,
              ),
              child: bookingState.isLoading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.background))
                  : Text('Book Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      color: selectedSeats.isEmpty ? colors.textTertiary : colors.background)),
            ),
          ),
        ])),
      ) : null,
      body: seatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(err.toString().replaceFirst('MarketplaceBookingException: ', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(seatAvailabilityProvider(widget.tripId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (availability) => Column(
          children: [
            // Trip info header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: colors.surface,
              child: Row(
                children: [
                  Icon(Icons.event_seat, color: colors.accent),
                  const SizedBox(width: 8),
                  Text('${availability.availableCount} of ${availability.totalSeats} available',
                      style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const Spacer(),
                  Text('\$${availability.fareUsdc.toStringAsFixed(2)}/seat',
                      style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // Seat map
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _SeatMapGrid(
                  seats: availability.seats,
                  selectedSeats: selectedSeats,
                  onSeatTap: _onSeatTap,
                ),
              ),
            ),

            // Selected seats + passenger names
            if (selectedSeats.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: colors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Passenger Names (optional)',
                        style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...selectedSeats.map((seatId) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(seatId, style: TextStyle(fontWeight: FontWeight.bold, color: colors.accent)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _passengerNames.putIfAbsent(seatId, () => TextEditingController()),
                              decoration: InputDecoration(
                                hintText: 'Passenger name for seat $seatId',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],

            // Removed bottom bar from here

            // Error message
            if (bookingState.error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: colors.danger.withOpacity(0.1),
                child: Text(bookingState.error!,
                    style: TextStyle(color: colors.danger, fontSize: 12)),
              ),

            // Success → navigate
            if (bookingState.result != null)
              _buildSuccessWidget(bookingState.result!, colors),
          ],
        ),
      ),
    );
  }

  void _onSeatTap(String seatId, SeatStatus status) {
    if (status == SeatStatus.occupied) return;
    AzamanHaptics.toggle();
    final current = ref.read(selectedSeatsProvider);
    final next = Set<String>.from(current);
    if (next.contains(seatId)) {
      next.remove(seatId);
      _passengerNames[seatId]?.dispose();
      _passengerNames.remove(seatId);
    } else {
      next.add(seatId);
    }
    ref.read(selectedSeatsProvider.notifier).state = next;
  }

  Future<void> _bookSeats(SeatAvailability availability) async {
    final selected = ref.read(selectedSeatsProvider);
    final names = selected.map((s) => _passengerNames[s]?.text ?? '').toList();

    await ref.read(bookingActionProvider.notifier).bookSeats(
      tripId: widget.tripId,
      seatIds: selected.toList(),
      passengerNames: names,
      businessProfileId: availability.tripId, // Note: BE uses tripId to look up biz
    );
  }

  Widget _buildSuccessWidget(BookSeatResult result, dynamic colors) {
    // Auto-navigate on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedSeatsProvider.notifier).state = {};
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booked ${result.seatIds.length} seat(s)! Ref: ${result.bookingRef}'),
            backgroundColor: colors.accent,
          ),
        );
        context.go('/marketplace/transit');
      }
    });
    return const SizedBox.shrink();
  }
}

// ── SEAT MAP GRID WIDGET ─────────────────────────────────────────────────────

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

    return Column(
      children: [
        // Driver indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.airline_seat_recline_normal, color: colors.textSecondary, size: 20),
              const SizedBox(width: 4),
              Text('Driver', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Seat rows
        ...sortedRows.map((rowNum) {
          final rowSeats = rowMap[rowNum]!..sort((a, b) => a.col.compareTo(b.col));
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildRowWithAisle(rowSeats, colors),
            ),
          );
        }),

        const SizedBox(height: 24),

        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _legendItem(Colors.green, 'Available', colors),
            _legendItem(colors.accent, 'Selected', colors),
            _legendItem(Colors.grey, 'Occupied', colors),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildRowWithAisle(List<TransitSeat> rowSeats, dynamic colors) {
    final widgets = <Widget>[];
    for (int i = 0; i < rowSeats.length; i++) {
      widgets.add(_SeatWidget(
        seat: rowSeats[i],
        isSelected: selectedSeats.contains(rowSeats[i].seatId),
        onTap: () => onSeatTap(rowSeats[i].seatId, rowSeats[i].status),
        colors: colors,
      ));
      // Add aisle gap between col 1 and 2 (or middle)
      if (i == 0 && rowSeats.length > 2) {
        widgets.add(const SizedBox(width: 24));
      } else if (i < rowSeats.length - 1) {
        widgets.add(const SizedBox(width: 8));
      }
    }
    return widgets;
  }

  Widget _legendItem(Color color, String label, dynamic colors) {
    return Row(
      children: [
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ── INDIVIDUAL SEAT WIDGET ───────────────────────────────────────────────────

class _SeatWidget extends StatelessWidget {
  final TransitSeat seat;
  final bool isSelected;
  final VoidCallback onTap;
  final dynamic colors;

  const _SeatWidget({
    required this.seat,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = seat.status == SeatStatus.occupied;
    
    return GestureDetector(
      onTap: isOccupied ? null : onTap,
      child: AnimatedContainer(
        duration: 250.ms, curve: Curves.easeOutCubic, width: 40, height: 40,
        decoration: BoxDecoration(
          color: isOccupied ? colors.divider : isSelected ? colors.accent : colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isOccupied ? Colors.transparent : isSelected ? colors.accent : colors.divider, width: isSelected ? 1.5 : 0.5),
          boxShadow: isSelected ? [BoxShadow(color: colors.accent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))] : null,
        ),
        child: Icon(isOccupied ? Icons.close_rounded : Icons.event_seat_rounded, size: 18,
          color: isOccupied ? colors.textTertiary : isSelected ? colors.background : colors.textSecondary),
      ).animate(target: isSelected ? 1 : 0)
        .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 150.ms, curve: Curves.easeOutBack)
        .then().scale(begin: const Offset(1.15, 1.15), end: const Offset(1, 1), duration: 100.ms),
    );
  }
}


