// lib/screens/marketplace/my_transit_trips_screen.dart
// =============================================================================
// YOUR TRIPS — the passenger's transit bookings (GET /transit/bookings), and
// the way back to each booking's boarding QR on the day.
//
// A paid fare reaches the operator only when the passenger boards by their
// own QR, so the QR must be one tap away when it matters: every CONFIRMED
// booking offers it. Before, nothing in the app listed a passenger's
// bookings at all; "View My Trips" opened the trip catalogue.
//
// Staff can also board a passenger after checking their ID. The trip then
// asks "Was this you?": "Yes, it was me" lets the operator be paid when the
// trip ends; "Not me" reports it and the fare stays held for review. With no
// answer, the fare is paid out 24 hours after departure.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/theme/az_text.dart';

class MyTransitTripsScreen extends ConsumerStatefulWidget {
  const MyTransitTripsScreen({super.key});

  @override
  ConsumerState<MyTransitTripsScreen> createState() =>
      _MyTransitTripsScreenState();
}

class _MyTransitTripsScreenState extends ConsumerState<MyTransitTripsScreen> {
  String? _busyId;

  String _messageOf(Object e, String fallback) => e is ApiException
      ? e.message
      : (e is MarketplaceBookingException ? e.message : fallback);

  Future<void> _confirm(TransitBookingSummary t) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = t.id);
    try {
      await ref
          .read(marketplaceBookingServiceProvider)
          .confirmIdCheckBoarding(t.id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks for confirming. The operator is paid when the trip ends.',
          ),
        ),
      );
      ref.invalidate(myTransitBookingsProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_messageOf(e, 'Could not confirm. Try again.'))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _report(TransitBookingSummary t) async {
    final colors = ref.read(themeProvider).colors;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      builder: (_) => _ReportSheet(colors: colors),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = t.id);
    try {
      final already = await ref
          .read(marketplaceBookingServiceProvider)
          .reportIdCheckBoarding(t.id, reason: reason);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            already
                ? 'Already reported. We are looking into it.'
                : 'Reported. The fare stays held while we look into it.',
          ),
        ),
      );
      ref.invalidate(myTransitBookingsProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_messageOf(e, 'Could not report. Try again.'))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final trips = ref.watch(myTransitBookingsProvider);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Your trips', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          colors: colors,
          title: 'We could not load your trips.',
          action: 'Try again',
          onAction: () => ref.invalidate(myTransitBookingsProvider),
        ),
        data: (items) => items.isEmpty
            ? _Message(colors: colors, title: 'No trips yet.')
            : RefreshIndicator(
                onRefresh: () => ref.refresh(myTransitBookingsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _TripCard(
                    trip: items[i],
                    colors: colors,
                    busy: _busyId == items[i].id,
                    onBoardingQr: () => context.push(
                      '/marketplace/transit/boarding/${items[i].id}',
                    ),
                    onConfirmBoarding: () => _confirm(items[i]),
                    onReportBoarding: () => _report(items[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.colors,
    required this.onBoardingQr,
    required this.onConfirmBoarding,
    required this.onReportBoarding,
    this.busy = false,
  });

  final TransitBookingSummary trip;
  final AzamanColors colors;
  final VoidCallback onBoardingQr;
  final VoidCallback onConfirmBoarding;
  final VoidCallback onReportBoarding;
  final bool busy;

  String get _statusLabel => switch (trip.status.toUpperCase()) {
    'CONFIRMED' => 'Paid · ready to board',
    'PENDING' => 'Reserved · not paid',
    'IN_PROGRESS' =>
      trip.boardedByIdCheck ? 'On board · ID checked' : 'On board',
    'COMPLETED' => 'Completed',
    'CANCELLED' => 'Cancelled',
    'NO_SHOW' => 'Missed',
    _ => trip.status,
  };

  @override
  Widget build(BuildContext context) {
    final when = trip.departureAt == null
        ? null
        : '${MaterialLocalizations.of(context).formatMediumDate(trip.departureAt!.toLocal())} · '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(trip.departureAt!.toLocal()))}';
    return Container(
      key: ValueKey('my-trip-${trip.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${trip.origin} → ${trip.destination}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (when != null) when,
              if (trip.operatorName != null) trip.operatorName!,
            ].join(' · '),
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_statusLabel · ${trip.bookingRef}',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                    fontFeatures: AzText.tabular,
                  ),
                ),
              ),
              if (trip.canShowBoardingQr)
                FilledButton.icon(
                  key: ValueKey('my-trip-qr-${trip.id}'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onBoardingQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Boarding QR'),
                ),
            ],
          ),
          if (trip.awaitsBoardingAnswer) _answerPanel(context),
          if (trip.isReported)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Reported · the fare is held while we look into it.',
                key: ValueKey('boarding-reported-${trip.id}'),
                style: TextStyle(color: colors.warning, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  // Staff boarded this passenger by ID check: was it them?
  Widget _answerPanel(BuildContext context) {
    final at = trip.boardedAt == null
        ? ''
        : ' at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(trip.boardedAt!.toLocal()))}';
    return Container(
      key: ValueKey('boarding-answer-${trip.id}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boarded by ID check$at',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${trip.operatorName ?? 'The operator'} boarded you after checking your ID. Was this you?',
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonal(
                key: ValueKey('boarding-yes-${trip.id}'),
                onPressed: busy ? null : onConfirmBoarding,
                child: const Text('Yes, it was me'),
              ),
              TextButton(
                key: ValueKey('boarding-not-me-${trip.id}'),
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                onPressed: busy ? null : onReportBoarding,
                child: const Text('Not me'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Not me": what happened, optional. Returns the text, or null if closed.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.colors});
  final AzamanColors colors;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not you?',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We hold the fare and look into it. The operator is not paid while we do.',
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('boarding-report-reason'),
            controller: _reason,
            maxLength: 500,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'What happened? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('boarding-report-send'),
              style: FilledButton.styleFrom(backgroundColor: c.danger),
              onPressed: () => Navigator.of(context).pop(_reason.text),
              child: const Text('Report this boarding'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.colors,
    required this.title,
    this.action,
    this.onAction,
  });

  final AzamanColors colors;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_bus_outlined,
            size: 44,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}
