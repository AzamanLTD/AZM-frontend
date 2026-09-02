// =============================================================================
// AZAMAN — TRANSIT SEAT SELECTION
//
// One canonical seat interaction model for marketplace discovery and booking.
// The screen owns journey context and booking; BusSeatSelector owns geometry,
// occupancy, accessibility and viewport interaction.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';

class TransitSeatSelectionScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TransitSeatSelectionScreen({super.key, required this.tripId});

  @override
  ConsumerState<TransitSeatSelectionScreen> createState() =>
      _TransitSeatSelectionScreenState();
}

class _TransitSeatSelectionScreenState
    extends ConsumerState<TransitSeatSelectionScreen> {
  late final SeatSelectorController _seatController;
  final _passengerNames = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _seatController = SeatSelectorController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedSeatsProvider.notifier).state = <String>{};
      }
    });
    ref.listenManual<BookingActionState>(bookingActionProvider, (_, state) {
      if (!mounted || (state.error == null && state.result == null)) return;
      final colors = ref.read(themeProvider.select((t) => t.colors));
      final error = state.error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.replaceFirst('MarketplaceBookingException: ', '')),
            backgroundColor: colors.danger,
          ),
        );
        return;
      }

      final result = state.result!;
      final trip = ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
      final selected = ref.read(selectedSeatsProvider);
      final total = result.totalFare;

      ref.invalidate(seatAvailabilityProvider(widget.tripId));
      ref.read(selectedSeatsProvider.notifier).state = <String>{};
      _seatController.clearSelection();

      BookingSuccessSheet.show(
        context,
        bookingRef: result.bookingRef,
        seatCount: result.seatIds.length,
        totalFare: total,
        route: trip == null ? 'Trip ${widget.tripId}' : '${trip.origin} → ${trip.destination}',
        departureTime: trip?.departureAt ?? DateTime.now(),
      );
    });
  }

  @override
  void dispose() {
    for (final controller in _passengerNames.values) {
      controller.dispose();
    }
    _seatController.dispose();
    super.dispose();
  }

  double _totalFare(SeatAvailability? availability, Set<String> selected) {
    if (availability == null) return 0;
    return selected.fold<double>(0, (total, id) {
      final seat = availability.seats.where((s) => s.seatId == id).firstOrNull;
      return total + (seat?.fare ?? availability.fareUsdc);
    });
  }

  void _syncSelection(Set<String> selected) {
    // Selection callbacks can arrive while the selector rebuilds its layout.
    // Always cross the frame boundary before writing shared Riverpod state.
    final next = Set<String>.from(selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(selectedSeatsProvider);
      if (current.length != next.length || !current.every(next.contains)) {
        ref.read(selectedSeatsProvider.notifier).state = next;
      }
      _passengerNames.removeWhere((id, controller) {
        if (next.contains(id)) return false;
        controller.dispose();
        return true;
      });
    });
  }

  Future<void> _editPassengerNames(Set<String> selected, AzamanColors colors) async {
    for (final id in selected) {
      _passengerNames.putIfAbsent(id, TextEditingController.new);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Passenger details',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: Icon(Icons.close, color: colors.textSecondary),
                    ),
                  ],
                ),
                Text(
                  'Optional. Add a name only when the ticket needs passenger identification.',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                for (final id in selected) ...[
                  TextField(
                    controller: _passengerNames[id],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Seat $id · passenger name',
                      filled: true,
                      fillColor: colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.divider),
                      ),
                    ),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bookSeats() async {
    final selected = ref.read(selectedSeatsProvider);
    if (selected.isEmpty) return;
    final names = selected
        .map((id) => _passengerNames[id]?.text.trim() ?? '')
        .toList(growable: false);
    await ref.read(bookingActionProvider.notifier).bookSeats(
          tripId: widget.tripId,
          seatIds: selected.toList(growable: false),
          passengerNames: names.any((name) => name.isNotEmpty) ? names : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final trip = ref.watch(tripDetailProvider(widget.tripId)).valueOrNull;
    final availabilityAsync = ref.watch(seatAvailabilityProvider(widget.tripId));
    final selected = ref.watch(selectedSeatsProvider);
    final booking = ref.watch(bookingActionProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          trip == null ? 'Choose seats' : '${trip.origin} → ${trip.destination}',
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: availabilityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _errorState(colors, error),
        data: (availability) {
          final layout = vehicleLayoutFromSeats(
            layoutId: trip?.vehicleId ?? widget.tripId,
            seats: availability.seats,
            vehicleType: trip?.vehicleType,
            vehicleMake: trip?.vehicleMake,
            vehicleModel: trip?.vehicleModel,
          );

          return Column(
            children: [
              _JourneyStrip(
                trip: trip,
                availability: availability,
                colors: colors,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: BusSeatSelector(
                    key: ValueKey('${widget.tripId}-${availability.tripStatus}-${availability.seats.length}'),
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
                    showCheckoutDock: false,
                    onSelectionChanged: _syncSelection,
                  ),
                ),
              ),
              if (selected.isNotEmpty)
                _BookingDock(
                  selected: selected,
                  total: _totalFare(availability, selected),
                  colors: colors,
                  busy: booking.isLoading,
                  onNames: () => _editPassengerNames(selected, colors),
                  onBook: _bookSeats,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _errorState(AzamanColors colors, Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_seat_outlined, size: 44, color: colors.textTertiary),
              const SizedBox(height: 12),
              Text(
                'We could not load the seat map.',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString().replaceFirst('MarketplaceBookingException: ', ''),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(seatAvailabilityProvider(widget.tripId)),
                child: const Text('Retry seat availability'),
              ),
            ],
          ),
        ),
      );
}

class _JourneyStrip extends StatelessWidget {
  final TransitTrip? trip;
  final SeatAvailability availability;
  final AzamanColors colors;

  const _JourneyStrip({
    required this.trip,
    required this.availability,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final route = trip == null
        ? 'Select your seats'
        : '${trip!.origin} → ${trip!.destination}';
    final detail = trip == null
        ? '${availability.availableCount} of ${availability.totalSeats} open'
        : '${trip!.vehicleType} · ${MaterialLocalizations.of(context).formatMediumDate(trip!.departureAt)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(trip!.departureAt))}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
      color: colors.surface,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(Icons.directions_bus_rounded, color: colors.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '\$${availability.fareUsdc.toStringAsFixed(0)}',
            style: TextStyle(
              color: colors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingDock extends StatelessWidget {
  final Set<String> selected;
  final double total;
  final AzamanColors colors;
  final bool busy;
  final VoidCallback onNames;
  final VoidCallback onBook;

  const _BookingDock({
    required this.selected,
    required this.total,
    required this.colors,
    required this.busy,
    required this.onNames,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 5,
