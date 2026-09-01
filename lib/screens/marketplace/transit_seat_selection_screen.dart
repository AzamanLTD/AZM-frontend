// =============================================================================
// AZAMAN — TRANSIT SEAT SELECTION SCREEN
//
// The booking screen deliberately uses the canonical BusSeatSelector so there
// is one authoritative seat interaction model across the marketplace preview
// and the full booking flow. Booking remains owned by marketplace_booking_provider.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
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
    ref.read(selectedSeatsProvider.notifier).state = <String>{};
    ref.listenManual<BookingActionState>(
      bookingActionProvider,
      (_, state) {
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
          return;
        }

        final result = state.result;
        if (result == null) return;

        final tripDetail =
            ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
        final route = tripDetail != null
            ? '${tripDetail.origin} → ${tripDetail.destination}'
            : 'Trip ${widget.tripId}';
        final departureTime = tripDetail?.departureAt ?? DateTime.now();
        final total = _totalFare(
          ref.read(seatAvailabilityProvider(widget.tripId)).valueOrNull,
          ref.read(selectedSeatsProvider),
        );

        ref.invalidate(seatAvailabilityProvider(widget.tripId));
        ref.read(selectedSeatsProvider.notifier).state = <String>{};
        _seatController.clearSelection();

        BookingSuccessSheet.show(
          context,
          bookingRef: result.bookingRef,
          seatCount: result.seatIds.length,
          totalFare: total,
          route: route,
          departureTime: departureTime,
        );
      },
    );
  }

  @override
  void dispose() {
    for (final controller in _passengerNames.values) {
      controller.dispose();
    }
    _seatController.dispose();
    if (ref.read(selectedSeatsProvider).isNotEmpty) {
      ref.read(selectedSeatsProvider.notifier).state = <String>{};
    }
    super.dispose();
  }

  double _totalFare(SeatAvailability? availability, Set<String> selected) {
    if (availability == null) return 0;
    var total = 0.0;
    for (final id in selected) {
      final seat = availability.seats.where((s) => s.seatId == id).firstOrNull;
      total += seat?.fare ?? availability.fareUsdc;
    }
    return total;
  }

  Future<void> _bookSeats() async {
    final selected = ref.read(selectedSeatsProvider);
    if (selected.isEmpty) return;

    final seatIds = selected.toList();
    final names = seatIds
        .map((id) => _passengerNames[id]?.text.trim() ?? '')
        .toList(growable: false);
    final hasNames = names.any((name) => name.isNotEmpty);

    await ref.read(bookingActionProvider.notifier).bookSeats(
          tripId: widget.tripId,
          seatIds: seatIds,
          passengerNames: hasNames ? names : null,
        );
  }

  void _syncSelection(Set<String> selected) {
    final next = Set<String>.from(selected);
    ref.read(selectedSeatsProvider.notifier).state = next;
    final selectedIds = next;

    _passengerNames.removeWhere((id, controller) {
      if (selectedIds.contains(id)) return false;
      controller.dispose();
      return true;
    });
  }

  Future<void> _editPassengerNames(
    BuildContext context,
    SeatAvailability availability,
    Set<String> selected,
    AzamanColors colors,
  ) async {
    for (final seatId in selected) {
      _passengerNames.putIfAbsent(
        seatId,
        () => TextEditingController(),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
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
                    'Optional — add a name only when the ticket needs to identify a passenger.',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  for (final seatId in selected) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            seatId,
                            style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _passengerNames[seatId],
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Passenger name',
                              hintText: 'Optional',
                              isDense: true,
                              filled: true,
                              fillColor: colors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colors.divider),
                              ),
                            ),
                            style: TextStyle(color: colors.textPrimary),
                          ),
                        ),
                      ],
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
        );
      },
    );
  }

  Widget _tripHeader(
    TransitTrip? trip,
    SeatAvailability availability,
    AzamanColors colors,
  ) {
    final route = trip == null
        ? 'Select your seats'
        : '${trip.origin} → ${trip.destination}';
    final departure = trip?.departureAt;
    final detail = departure == null
        ? '${availability.availableCount} of ${availability.totalSeats} seats available'
        : '${MaterialLocalizations.of(context).formatMediumDate(departure)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(departure))}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider, width: .5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.directions_bus_rounded, color: colors.accent),
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
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
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
            '\$${availability.fareUsdc.toStringAsFixed(0)}/seat',
            style: TextStyle(
              color: colors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final seatsAsync = ref.watch(seatAvailabilityProvider(widget.tripId));
    final selectedSeats = ref.watch(selectedSeatsProvider);
    final bookingState = ref.watch(bookingActionProvider);
    final trip = ref.watch(tripDetailProvider(widget.tripId)).valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          trip == null ? 'Choose your seats' : trip.routeLabel,
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: seatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _errorState(error, colors),
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
              _tripHeader(trip, availability, colors),
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
              if (selectedSeats.isNotEmpty)
                _selectionSummary(
                  context,
                  availability,
                  selectedSeats,
                  bookingState.isLoading,
                  colors,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _selectionSummary(
    BuildContext context,
    SeatAvailability availability,
    Set<String> selectedSeats,
    bool isBooking,
    AzamanColors colors,
  ) {
    final total = _totalFare(availability, selectedSeats);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider, width: .5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final seatId in selectedSeats)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(seatId),
                          backgroundColor: colors.accentSurface,
                          labelStyle: TextStyle(
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editPassengerNames(
                    context,
                    availability,
                    selectedSeats,
                    colors,
                  ),
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('Passenger names'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBooking ? null : _bookSeats,
                    icon: isBooking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline_rounded, size: 18),
                    label: Text(isBooking ? 'Booking…' : 'Continue to book'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 0.15, end: 0, duration: 220.ms, curve: Curves.easeOutCubic);
  }

  Widget _errorState(Object error, AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_seat_outlined, size: 44, color: colors.danger),
            const SizedBox(height: 10),
            Text(
              error.toString().replaceFirst('MarketplaceBookingException: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () =>
                  ref.invalidate(seatAvailabilityProvider(widget.tripId)),
              child: const Text('Retry seat availability'),
            ),
          ],
        ),
      ),
    );
  }
}
