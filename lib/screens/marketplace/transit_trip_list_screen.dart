// =============================================================================
// AZAMAN — TRANSIT TRIP LIST SCREEN (2026-07-02)
//
// Shows available transit trips. Customer taps a trip → seat selection.
//
// Part of the marketplace booking lifecycle overhaul.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';

class TransitTripListScreen extends ConsumerWidget {
  final String? businessProfileId;

  const TransitTripListScreen({super.key, this.businessProfileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final tripsAsync = ref.watch(transitTripsProvider(businessProfileId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Available Trips', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: tripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text('Failed to load trips', style: TextStyle(color: colors.textPrimary)),
              const SizedBox(height: 8),
              Text(err.toString().replaceFirst('MarketplaceBookingException: ', ''),
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(transitTripsProvider(businessProfileId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (trips) {
          if (trips.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_bus_outlined, size: 64, color: colors.textSecondary),
                  const SizedBox(height: 16),
                  Text('No trips available', style: TextStyle(color: colors.textSecondary, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            itemBuilder: (context, index) => _TripCard(trip: trips[index]),
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TransitTrip trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    final colors = ref.read(themeProvider.select((t) => t.colors));

    final departureTime = TimeOfDay.fromDateTime(trip.departureAt);
    final timeStr = '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colors.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: trip.availableSeats > 0
            ? () => context.push('/marketplace/transit/${trip.id}/seats')
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route name
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.routeLabel,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: trip.availableSeats > 0
                          ? colors.accent.withOpacity(0.1)
                          : colors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      trip.availableSeats > 0
                          ? '${trip.availableSeats} seats left'
                          : 'Full',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: trip.availableSeats > 0 ? colors.accent : colors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Departure + arrival times
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text('Departs at $timeStr',
                      style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),

              // Vehicle info
              Row(
                children: [
                  Icon(Icons.directions_bus, size: 16, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      trip.vehicleLabel + (trip.driverName != null ? ' \u00b7 ${trip.driverName}' : ''),
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Fare + book button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '\$${trip.fareUsdc.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.accent),
                  ),
                  FilledButton(
                    onPressed: trip.availableSeats > 0
                        ? () => context.push('/marketplace/transit/${trip.id}/seats')
                        : null,
                    child: const Text('Select Seats'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


