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
import 'package:go_router/go_router.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/marketplace/experiences/transit/demo_transit_hold_gateway.dart';
import 'package:azaman/marketplace/experiences/transit/transit_boarding.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/transit_boarding_pass.dart';
import 'package:azaman/widgets/marketplace/transit/journey_thread.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';
import 'package:azaman/widgets/seat_selector/transit_hold_ring.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/security/second_factor.dart';
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

  /// Answers the second-factor prompt in tests; null shows the real sheet.
  final Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  secondFactorPrompt;

  const TransitSeatSelectionScreen({
    super.key,
    required this.tripId,
    this.holdGateway,
    this.holdClock,
    this.secondFactorPrompt,
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
        String message = error.replaceFirst(
          'MarketplaceBookingException: ',
          '',
        );
        final code = state.errorCode;
        if (code == 'INSUFFICIENT_BALANCE') {
          // Nothing was booked or charged (the whole transaction rolled
          // back). Refresh the quote so the dock offers Add money.
          ref.invalidate(transitPaymentQuoteProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Your wallet does not cover this yet. Nothing was charged.',
              ),
              backgroundColor: colors.warning,
              action: SnackBarAction(label: 'Add money', onPressed: _addMoney),
            ),
          );
          return;
        }
        if (code == 'PRICE_CHANGED') {
          // The fare or the fee moved since the quote: nothing was charged.
          // Show the new total and let the passenger approve it.
          ref.invalidate(transitPaymentQuoteProvider);
          message =
              'The price changed. Check the new total. Nothing was charged.';
        } else if (code != null && code.startsWith('KYC_')) {
          message =
              'Verify your identity to pay for seats. Nothing was charged.';
        } else if (code != null &&
            const {
              'TRIP_UNAVAILABLE',
              'TRIP_DEPARTED',
              'SELF_PAYMENT',
              'DUPLICATE_SEATS',
              'PAYEE_UNAVAILABLE',
            }.contains(code)) {
          // A definitive refusal before anything was charged: the server's
          // own words.
          message = '$message Nothing was charged.';
        } else if (cls == TransitBookingFailureClass.ambiguousOrUnknown) {
          message =
              'We couldn\'t confirm your payment. Check your bookings first — '
              'if the seats aren\'t there, paying for the same seats again '
              'safely reuses your request and never charges twice.';
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
          SnackBar(content: Text(message), backgroundColor: colors.danger),
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

      // The backend creates the booking PENDING and charges nothing; only an
      // operator-confirmed booking gets the boarding pass.
      final confirmed = result.status.toUpperCase() == 'CONFIRMED';
      BookingSuccessSheet.show(
        context,
        bookingRef: result.bookingRef,
        seatCount: result.seatIds.length,
        totalFare: total,
        route: trip == null
            ? 'Trip ${widget.tripId}'
            : '${trip.origin} → ${trip.destination}',
        departureTime: trip?.departureAt ?? DateTime.now(),
        pending: !confirmed,
        paidTotalUsdc: result.paidTotalUsdc,
        keepsake: trip == null || !confirmed
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  JourneyThread(
                    model: JourneyThreadModel.fromTrip(
                      trip,
                      stage: JourneyStage.boarded,
                      seatLabel: journeySeatLabel(result.seatIds),
                    ),
                  ),
                  TransitBoardingPassCard(
                    pass: TransitBoardingPass(
                      bookingId: result.bookingId,
                      trip: transitExperienceTripFromBooking(trip),
                      seatIds: result.seatIds,
                      boardingTime: DateTime.now(),
                    ),
                    colors: colors,
                  ),
                ],
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

  /// Books AND pays for the selection from the wallet. The second factor is
  /// asked once ([withSecondFactor] follows the server if the account needs
  /// the other one); the result or the failure lands in the booking state.
  Future<void> _pay(TransitPaymentQuote quote) async {
    final selected = ref.read(selectedSeatsProvider);
    if (selected.isEmpty) return;
    final names = selected
        .map((id) => _passengerNames[id]?.text.trim() ?? '')
        .toList(growable: false);
    final total = usdcExactLabel(quote.totalUsdc);
    await withSecondFactor<void>(
      context,
      initial: secondFactorKindFor(ref.read(authProvider).user),
      title: 'Pay $total',
      actionLabel: 'Pay $total',
      ask: widget.secondFactorPrompt,
      attempt: (factor) => ref
          .read(bookingActionProvider.notifier)
          .payForSeats(
            tripId: widget.tripId,
            seatIds: selected.toList(growable: false),
            passengerNames: names.any((name) => name.isNotEmpty) ? names : null,
            secondFactor: factor,
            expectedTotalUsdc: quote.totalUsdc,
            operationType: _bookingActionId,
            ref: _bookingRef,
          ),
    );
  }

  void _addMoney() {
    if (!mounted) return;
    context.push('/deposit');
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
    final quote = selected.isEmpty
        ? null
        : ref.watch(
            transitPaymentQuoteProvider(
              transitQuoteKey(widget.tripId, selected),
            ),
          );

    // Snapshot the hold generation for THIS build. The dock's expiry
    // closure must capture the generation of the hold it displays by
    // VALUE: reading the field at invocation time would let a stale
    // ring's callback clear a newer selection's hold (corrigendum §7).
    final holdGenerationAtBuild = _activeHoldGeneration;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        // The strip under the bar carries the route; the bar says what
        // this screen is for.
        title: Text(
          'Choose your seat',
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
              // Journey thread (Overhaul 03 §5.1): derived from the trip and
              // the live selection; never read back to make a decision.
              if (trip != null)
                JourneyThread(
                  model: JourneyThreadModel.fromTrip(
                    trip,
                    stage: selected.isEmpty
                        ? JourneyStage.seat
                        : JourneyStage.booking,
                    seatLabel: journeySeatLabel(selected),
                  ),
                ),
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
                  fare: _totalFare(availability, selected),
                  quote: quote,
                  colors: colors,
                  busy: booking.isLoading,
                  onNames: () => _editPassengerNames(selected, colors),
                  onPay: _pay,
                  onAddMoney: _addMoney,
                  onRetryQuote: () => ref.invalidate(
                    transitPaymentQuoteProvider(
                      transitQuoteKey(widget.tripId, selected),
                    ),
                  ),
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
            transitFareLabel(availability.fareUsdc),
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

/// A fare as the trip states it: whole amounts without cents ("$18"),
/// anything else to the cent ("$0.60") — never rounded up to a whole unit.
String transitFareLabel(double v) => v == v.roundToDouble()
    ? '\$${v.toStringAsFixed(0)}'
    : '\$${v.toStringAsFixed(2)}';

/// A USDC amount exactly as it is charged: at least two decimals, up to six,
/// trailing zeros trimmed ("$0.60", "$0.603", "$7.035"). A booking fee of a
/// fraction of a cent is shown as charged, never rounded to "$0.00".
String usdcExactLabel(double v) {
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  final dot = s.indexOf('.');
  if (dot < 0) {
    s = '$s.00';
  } else if (s.length - dot - 1 == 1) {
    s = '${s}0';
  }
  return '\$$s';
}

/// The booking dock: your seats, how long they are held, what paying from the
/// wallet charges (fare + Azaman fee, from the server's quote) and the one
/// commitment, "Pay".
///
/// It says what the backend does. Pay books AND pays in one transaction
/// (payWith: WALLET): the fare is debited from the wallet with the fee,
/// held for the operator and released to them when the trip completes. A
/// wallet that cannot cover it offers Add money instead of a failing Pay.
class _BookingDock extends StatelessWidget {
  final Set<String> selected;
  final double fare;
  final AsyncValue<TransitPaymentQuote>? quote;
  final AzamanColors colors;
  final bool busy;
  final VoidCallback onNames;
  final void Function(TransitPaymentQuote quote) onPay;
  final VoidCallback onAddMoney;
  final VoidCallback onRetryQuote;
  final DateTime? holdExpiresAt;
  final VoidCallback? onHoldExpired;
  final DateTime Function()? holdClock;

  const _BookingDock({
    required this.selected,
    required this.fare,
    required this.quote,
    required this.colors,
    required this.busy,
    required this.onNames,
    required this.onPay,
    required this.onAddMoney,
    required this.onRetryQuote,
    this.holdExpiresAt,
    this.onHoldExpired,
    this.holdClock,
  });

  @override
  Widget build(BuildContext context) {
    final count = selected.length;
    final seats = (selected.toList()..sort());
    final q = quote?.valueOrNull;
    final quoteFailed = quote?.hasError == true && q == null;
    final onAccent = colors.accent.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    TextStyle line(
      Color c, {
      FontWeight w = FontWeight.w500,
      double size = 13,
    }) => TextStyle(
      color: c,
      fontSize: size,
      fontWeight: w,
      fontFeatures: AzText.tabular,
    );

    // The commitment, by what the wallet can do.
    final String ctaLabel;
    final VoidCallback? ctaAction;
    final IconData? ctaIcon;
    if (busy) {
      ctaLabel = 'Paying…';
      ctaAction = null;
      ctaIcon = null;
    } else if (quoteFailed) {
      ctaLabel = 'Try again';
      ctaAction = onRetryQuote;
      ctaIcon = Icons.refresh_rounded;
    } else if (q == null) {
      ctaLabel = 'Working out the total…';
      ctaAction = null;
      ctaIcon = null;
    } else if (q.canPay) {
      ctaLabel = 'Pay ${usdcExactLabel(q.totalUsdc)}';
      ctaAction = () => onPay(q);
      ctaIcon = null;
    } else if (q.shortfallUsdc > 0) {
      ctaLabel = 'Add money';
      ctaAction = onAddMoney;
      ctaIcon = Icons.add_rounded;
    } else {
      ctaLabel = 'This trip cannot be paid';
      ctaAction = null;
      ctaIcon = null;
    }

    final walletLine = q == null
        ? (quoteFailed
              ? 'We could not work out the total. Nothing was charged.'
              : 'Paid from your Azaman wallet.')
        : q.shortfallUsdc > 0
        ? 'Your wallet has ${usdcExactLabel(q.availableUsdc)}. Add ${usdcExactLabel(q.shortfallUsdc)} to pay.'
        : 'From your wallet · ${usdcExactLabel(q.availableUsdc)} available. Held for the operator until the trip.';

    return Container(
      key: const ValueKey('transit-booking-dock'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: colors.divider, width: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in seats)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              id,
                              style: line(
                                onAccent,
                                w: FontWeight.w700,
                                size: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (holdExpiresAt != null) ...[
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 6),
                    Text(
                      'Held for you',
                      style: line(colors.textTertiary, size: 11.5),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              // Fare and fee share a line when they fit and wrap when they
              // don't (large text, narrow phones).
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                'Fare · $count seat${count == 1 ? '' : 's'}  ',
                            style: line(colors.textSecondary),
                          ),
                          TextSpan(
                            text: usdcExactLabel(q?.fareUsdc ?? fare),
                            style: line(colors.textPrimary, w: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Text.rich(
                      key: const ValueKey('transit-dock-fee'),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Azaman fee  ',
                            style: line(colors.textSecondary),
                          ),
                          TextSpan(
                            text: q == null ? '…' : usdcExactLabel(q.feeUsdc),
                            style: line(colors.textPrimary, w: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  thickness: 0.6,
                  color: colors.divider,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Total',
                    style: line(
                      colors.textPrimary,
                      w: FontWeight.w700,
                      size: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    q == null ? '…' : '${usdcExactLabel(q.totalUsdc)} USDC',
                    key: const ValueKey('transit-dock-total'),
                    style: line(
                      colors.textPrimary,
                      w: FontWeight.w800,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  walletLine,
                  key: const ValueKey('transit-dock-wallet'),
                  style: line(
                    q != null && q.shortfallUsdc > 0
                        ? colors.warning
                        : colors.textTertiary,
                    size: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Tooltip(
                    message: 'Passenger names',
                    child: Material(
                      color: colors.surface,
                      shape: CircleBorder(
                        side: BorderSide(color: colors.divider),
                      ),
                      child: InkWell(
                        key: const ValueKey('transit-dock-names'),
                        customBorder: const CircleBorder(),
                        onTap: onNames,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.badge_outlined,
                            size: 21,
                            color: colors.textSecondary,
                            semanticLabel: 'Names',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Owner decision 2026-10-31: the seat map, the fare and the
                  // selection stay browsable while money is locked, because
                  // they are catalogue. Paying is not, so only the commitment
                  // is gated. The guard replaces the button, so a locked tap
                  // cannot pay or hold a seat.
                  Expanded(
                    child: MoneyLockGate(
                      compact: true,
                      message: 'Unlock to pay',
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          key: const ValueKey('transit-dock-pay'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: onAccent,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: ctaAction,
                          child: busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: onAccent,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (ctaIcon != null) ...[
                                      Icon(ctaIcon, size: 18),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        ctaLabel,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
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
