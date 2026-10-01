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
import 'package:azaman/marketplace/experiences/transit/demo_transit_hold_gateway.dart';
import 'package:azaman/marketplace/experiences/transit/transit_boarding.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/transit_boarding_pass.dart';
import 'package:azaman/widgets/seat_selector/transit_hold_ring.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/booking_success_sheet.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';

class TransitSeatSelectionScreen extends ConsumerStatefulWidget {
  final String tripId;

  /// Seat-hold gateway. Defaults to [DemoTransitHoldGateway]; inject a real
  /// gateway when the backend hold endpoint exists.
  final TransitHoldGateway? holdGateway;

  /// Injectable clock for the hold countdown ring (tests). Defaults to the
  /// wall clock.
  final DateTime Function()? holdClock;

  const TransitSeatSelectionScreen({
    super.key,
    required this.tripId,
    this.holdGateway,
    this.holdClock,
  });

  @override
  ConsumerState<TransitSeatSelectionScreen> createState() =>
      _TransitSeatSelectionScreenState();
}

class _TransitSeatSelectionScreenState
    extends ConsumerState<TransitSeatSelectionScreen> {
  late final SeatSelectorController _seatController;
  final _passengerNames = <String, TextEditingController>{};
  late final TransitHoldGateway _holdGateway;
  TransitHoldSuccess? _activeHold;

  /// Selection generation token (corrigendum §7): a hold result from an
  /// older selection must never replace the hold of a newer selection.
  int _holdGeneration = 0;

  /// The generation the currently displayed hold belongs to. The ring's
  /// expiry closure captures this, so a stale ring can never clear a
  /// newer selection.
  int? _activeHoldGeneration;

  /// §r42 (2026-10-01) — durable identity for THIS screen's booking intent:
  /// the ref binds the seat-booking operation to its journal instance, so
  /// a retry of the SAME seat selection after an ambiguous failure (lost
  /// response, 5xx, 408/425/429/409/401) reuses the SAME Idempotency-Key
  /// and the backend converges on the same booking (exact replay of the
  /// committed response) instead of turning into an indistinguishable
  /// 'Seats already booked'. A materially changed selection is a new
  /// economic intent — the registry gives it its own instance/key, and the
  /// old unfinished record stays recoverable in the journal. Same lifetime
  /// model as CartScreen's _checkoutRef.
  static const _bookingActionId = 'transit.book_seats';
  final _bookingRef = FinancialOperationRef();

  @override
  void initState() {
    super.initState();
    _seatController = SeatSelectorController();
    _holdGateway = widget.holdGateway ?? const DemoTransitHoldGateway();
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
        // §r42 failure presentation (deep-dive step 2 taxonomy, transit
        // variant): an UNPROVEN outcome (transport loss, 5xx, 408/425,
        // malformed success) must NOT be asserted as a failed booking —
        // the seats MAY be booked. The durable ref stays armed, so
        // retrying the SAME selection reuses the same key and converges
        // (the backend replays the committed booking exactly). Domain
        // conflicts (409 — key already used with a different selection)
        // and 401/429 get their own retry guidance; a definitive
        // pre-economic 4xx surfaces the backend's own message verbatim.
        final cls = state.failureClass;
        String message = error.replaceFirst('MarketplaceBookingException: ', '');
        if (cls == TransitBookingFailureClass.ambiguousOrUnknown) {
          message =
              'We couldn\'t confirm your booking. Check your bookings first — '
              'if the seats aren\'t there, booking the same seats again will '
              'safely reuse your request.';
        } else if (cls == TransitBookingFailureClass.domainConflict) {
          message =
              'This booking request conflicts with an earlier one. Check your '
              'bookings before booking again.';
        } else if (cls == TransitBookingFailureClass.authenticationRequired) {
          message =
              'Please sign in again, then book the same seats — your request '
              'will be safely reused.';
        } else if (cls == TransitBookingFailureClass.rateLimited) {
          message =
              'Too many attempts. Wait a moment, then book the same seats — '
              'your request will be safely reused.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: colors.danger,
          ),
        );
        return;
      }

      final result = state.result!;
      final trip = ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
      final total = result.totalFare;

      ref.invalidate(seatAvailabilityProvider(widget.tripId));
      // Invalidate every outstanding hold generation BEFORE clearing state,
      // so any in-flight hold result (and its expiry) is dead on arrival.
      ++_holdGeneration;
      _activeHoldGeneration = null;
      ref.read(selectedSeatsProvider.notifier).state = <String>{};
      _seatController.clearSelection();
      _activeHold = null;

      BookingSuccessSheet.show(
        context,
        bookingRef: result.bookingRef,
        seatCount: result.seatIds.length,
        totalFare: total,
        route: trip == null
            ? 'Trip ${widget.tripId}'
            : '${trip.origin} → ${trip.destination}',
        departureTime: trip?.departureAt ?? DateTime.now(),
        keepsake: trip == null
            ? null
            : TransitBoardingPassCard(
                pass: TransitBoardingPass(
                  bookingId: result.bookingId,
                  trip: transitExperienceTripFromBooking(trip),
                  seatIds: result.seatIds,
                  boardingTime: DateTime.now(),
                ),
                colors: colors,
              ),
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
        // Every selection transition — including clearing to empty —
        // invalidates the previous generation, and the currently
        // displayed hold drops immediately. A hold belongs to exactly
        // one selection generation (corrigendum §7).
        final generation = ++_holdGeneration;
        setState(() => _activeHold = null);
        _activeHoldGeneration = null;
        if (next.isNotEmpty) {
          _placeHold(next, generation);
        }
      }
      _passengerNames.removeWhere((id, controller) {
        if (next.contains(id)) return false;
        controller.dispose();
        return true;
      });
    });
  }

  /// Places a screen-local seat hold. Best-effort: a hold failure never
  /// blocks selection — the user retries by changing the selection.
  /// The generation token ensures a stale async result can never re-arm
  /// the ring for a selection the user has already replaced (§7).
  Future<void> _placeHold(Set<String> selected, int generation) async {
    final trip = ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
    if (trip == null) return;

    try {
      final controller = TransitHoldController(_holdGateway);
      final result = await controller.hold(
        TransitSeatSelection(
          trip: transitExperienceTripFromBooking(trip),
          seatIds: selected.toList(growable: false),
        ),
      );
      // Only the still-current generation may mutate the displayed hold:
      // the user has not changed anything since this hold was placed.
      if (!mounted || generation != _holdGeneration) return;
      setState(() {
        _activeHold = result is TransitHoldSuccess ? result : null;
        _activeHoldGeneration = result is TransitHoldSuccess
            ? generation
            : null;
      });
      if (result is TransitHoldFailure) {
        final colors = ref.read(themeProvider.select((t) => t.colors));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: colors.warning,
          ),
        );
      }
    } catch (e) {
      // Treated as a transient hold failure — selection is unaffected.
      // Do NOT fabricate a hold expiry; the selection stays retryable.
    }
  }

  /// The hold ring reached zero: warn, release the selection, explain.
  ///
  /// Generation-scoped: an old ring's expiry callback returns immediately
  /// unless its generation is still the active one — a stale expiry can
  /// never clear a newer selection (corrigendum §7).
  void _onHoldExpired(int expectedGeneration) {
    if (!mounted || expectedGeneration != _holdGeneration) return;
    if (_activeHold == null) return;
    AzamanHaptics.warning();
    setState(() => _activeHold = null);
    ref.read(selectedSeatsProvider.notifier).state = <String>{};
    _seatController.clearSelection();
    final colors = ref.read(themeProvider.select((t) => t.colors));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Seat hold expired — select your seats again.'),
        backgroundColor: colors.warning,
      ),
    );
  }

  Future<void> _editPassengerNames(
    Set<String> selected,
    AzamanColors colors,
  ) async {
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
    await ref
        .read(bookingActionProvider.notifier)
        .bookSeats(
          tripId: widget.tripId,
          seatIds: selected.toList(growable: false),
          passengerNames: names.any((name) => name.isNotEmpty) ? names : null,
          operationType: _bookingActionId,
          ref: _bookingRef,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final trip = ref.watch(tripDetailProvider(widget.tripId)).valueOrNull;
    final availabilityAsync = ref.watch(
      seatAvailabilityProvider(widget.tripId),
    );
    final selected = ref.watch(selectedSeatsProvider);
    final booking = ref.watch(bookingActionProvider);

    // Snapshot the hold generation for THIS build. The dock's expiry
    // closure must capture the generation of the hold it displays by
    // VALUE: reading the field at invocation time would let a stale
    // ring's callback clear a newer selection's hold (corrigendum §7).
    final holdGenerationAtBuild = _activeHoldGeneration;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          trip == null
              ? 'Choose seats'
              : '${trip.origin} → ${trip.destination}',
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
                    key: ValueKey(
                      '${widget.tripId}-${availability.tripStatus}-${availability.seats.length}',
                    ),
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
                    cabinLighting: const CabinLighting(),
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
                  holdExpiresAt: _activeHold?.expiresAt,
                  holdClock: widget.holdClock,
                  onHoldExpired: holdGenerationAtBuild == null
                      ? null
                      : () => _onHoldExpired(holdGenerationAtBuild),
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
            onPressed: () =>
                ref.invalidate(seatAvailabilityProvider(widget.tripId)),
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
  final DateTime? holdExpiresAt;
  final VoidCallback? onHoldExpired;
  final DateTime Function()? holdClock;

  const _BookingDock({
    required this.selected,
    required this.total,
    required this.colors,
    required this.busy,
    required this.onNames,
    required this.onBook,
    this.holdExpiresAt,
    this.onHoldExpired,
    this.holdClock,
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
                      children: selected
                          .map(
                            (id) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(id),
                              backgroundColor: colors.accentSurface,
                              side: BorderSide.none,
                              labelStyle: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Text(
                    '\$${total.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (holdExpiresAt != null) ...[
                Row(
                  children: [
                    TransitHoldRing(
                      expiresAt: holdExpiresAt,
                      window: transitHoldWindow,
                      accentColor: colors.accent,
                      warningColor: colors.warning,
                      dangerColor: colors.danger,
                      trackColor: colors.divider,
                      clock: holdClock,
                      onExpired: onHoldExpired,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Seats held for you',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: onNames,
                    icon: const Icon(Icons.person_outline_rounded, size: 18),
                    label: const Text('Names'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onBook,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(busy ? 'Booking…' : 'Continue to book'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 0.12, end: 0, duration: 220.ms);
  }
}
