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
          Icon(
            Icons.directions_bus_outlined,
            size: 38,
            color: colors.textTertiary,
          ),
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
        _TripJourneySummary(trip: trip, colors: colors),
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
}

class _TripJourneySummary extends StatelessWidget {
  final TransitTrip trip;
  final AzamanColors colors;

  const _TripJourneySummary({
    required this.trip,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final duration = _durationLabel();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  trip.routeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _MetaPill(
                label: '${trip.availableSeats} seats',
                icon: Icons.event_seat_outlined,
                colors: colors,
                accent: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _MetaPill(
                label: _date(trip.departureAt),
                icon: Icons.calendar_today_outlined,
                colors: colors,
              ),
              _MetaPill(
                label: _time(trip.departureAt),
                icon: Icons.schedule_outlined,
                colors: colors,
              ),
              if (duration != null)
                _MetaPill(
                  label: duration,
                  icon: Icons.timelapse_outlined,
                  colors: colors,
                ),
              _MetaPill(
                label: '${trip.fareUsdc.toStringAsFixed(2)} USDC',
                icon: Icons.payments_outlined,
                colors: colors,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.directions_bus_outlined,
                  size: 15, color: colors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _vehicleLine(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _vehicleLine() {
    final details = <String>[trip.vehicleLabel];
    if (trip.plateNumber != null && trip.plateNumber!.isNotEmpty) {
      details.add(trip.plateNumber!);
    }
    if (trip.driverName != null && trip.driverName!.isNotEmpty) {
      details.add('Driver: ${trip.driverName!}');
    }
    return details.join(' · ');
  }

  String _date(DateTime value) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
  }

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String? _durationLabel() {
    final arrival = trip.arrivalAt;
    if (arrival == null || !arrival.isAfter(trip.departureAt)) return null;
    final minutes = arrival.difference(trip.departureAt).inMinutes;
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '${remainder}m';
    if (remainder == 0) return '${hours}h';
    return '${hours}h ${remainder}m';
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final AzamanColors colors;
  final bool accent;

  const _MetaPill({
    required this.label,
    required this.icon,
    required this.colors,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? colors.accentSurface : colors.softSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: accent ? colors.accent : colors.textTertiary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent ? colors.accent : colors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
