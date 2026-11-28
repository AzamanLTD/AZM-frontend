// lib/screens/marketplace/my_transit_trips_screen.dart
// =============================================================================
// YOUR TRIPS — the passenger's transit bookings (GET /transit/bookings), and
// the way back to each booking's boarding QR on the day.
//
// A paid fare reaches the operator only when the passenger boards by their
// own QR, so the QR must be one tap away when it matters: every CONFIRMED
// booking offers it. Before, nothing in the app listed a passenger's
// bookings at all; "View My Trips" opened the trip catalogue.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';

class MyTransitTripsScreen extends ConsumerWidget {
  const MyTransitTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    onBoardingQr: () => context.push(
                      '/marketplace/transit/boarding/${items[i].id}',
                    ),
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
  });

  final TransitBookingSummary trip;
  final AzamanColors colors;
  final VoidCallback onBoardingQr;

  String get _statusLabel => switch (trip.status.toUpperCase()) {
    'CONFIRMED' => 'Paid · ready to board',
    'PENDING' => 'Reserved · not paid',
    'IN_PROGRESS' => 'On board',
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
