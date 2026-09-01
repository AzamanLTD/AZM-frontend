import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/seat_selector/bus_seat_selector.dart';

/// Read-only preview of the next scheduled trip and its real seat map.
///
/// Selection is intentionally disabled here. The full transit booking screen
/// remains responsible for authoritative seat selection and booking.
class TransitSeatPreview extends ConsumerWidget {
  final String businessProfileId;
  final AzamanColors colors;
  final VoidCallback onOpenTrips;

  const TransitSeatPreview({
    super.key,
    required this.businessProfileId,
    required this.colors,
    required this.onOpenTrips,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(transitTripsProvider(businessProfileId));

    return trips.when(
      loading: () => _loading(),
      error: (error, stack) => _fallback(),
      data: (items) {
        final scheduled = items.where((trip) => trip.status == TripStatus.scheduled).toList()
          ..sort((a, b) => a.departureAt.compareTo(b.departureAt));
        if (scheduled.isEmpty) return _fallback();
        return _TripPreview(
          trip: scheduled.first,
          colors: colors,
          onOpenTrips: onOpenTrips,
        );
      },
    );
  }

  Widget _loading() {
    return Container(
      height: 310,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: colors.accent),
    );
  }

  Widget _fallback() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_outlined,
              size: 38, color: colors.textTertiary),
          const SizedBox(height: 10),
          Text(
            'No upcoming trips yet',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Open the transit schedule to see routes and seats.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TripPreview extends ConsumerWidget {
  final TransitTrip trip;
  final AzamanColors colors;
  final VoidCallback onOpenTrips;

  const _TripPreview({
    required this.trip,
    required this.colors,
    required this.onOpenTrips,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seats = ref.watch(seatAvailabilityProvider(trip.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Choose your ride',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenTrips,
                child: const Text('View trips'),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.routeLabel,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_time(trip.departureAt)} · ${trip.vehicleLabel}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${trip.availableSeats} seats',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 280,
          child: seats.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: colors.accent),
            ),
            error: (error, stack) => Center(
              child: Text(
                'Seat map unavailable right now.',
                style: TextStyle(color: colors.textTertiary),
              ),
            ),
            data: (availability) {
              final layout = vehicleLayoutFromSeats(
                layoutId: trip.vehicleId,
                seats: availability.seats,
                vehicleType: trip.vehicleType,
                vehicleMake: trip.vehicleMake,
                vehicleModel: trip.vehicleModel,
              );
              return IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BusSeatSelector(
                      layout: layout,
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
                      showMinimap: false,
                      showLegend: false,
                      showCheckoutDock: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenTrips,
              icon: const Icon(Icons.event_seat_outlined),
              label: const Text('Open seat map'),
            ),
          ),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
