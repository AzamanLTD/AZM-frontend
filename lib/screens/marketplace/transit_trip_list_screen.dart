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
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

    final depTime = TimeOfDay.fromDateTime(trip.departureAt);
    final depStr = '${depTime.hour.toString().padLeft(2, '0')}:${depTime.minute.toString().padLeft(2, '0')}';
    
    String arrStr = '--:--';
    String durationStr = '--';
    if (trip.arrivalAt != null) {
      final arrTime = TimeOfDay.fromDateTime(trip.arrivalAt!);
      arrStr = '${arrTime.hour.toString().padLeft(2, '0')}:${arrTime.minute.toString().padLeft(2, '0')}';
      final diff = trip.arrivalAt!.difference(trip.departureAt);
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    }

    return GestureDetector(
      onTap: trip.availableSeats > 0 ? () => context.push('/marketplace/transit/${trip.id}/seats') : null,
      child: PremiumGlassContainer(
        blur: 12, opacity: 0.04, borderRadius: 16, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(depStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(trip.origin, style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              SizedBox(width: 60, child: Column(children: [
                Icon(Icons.circle, size: 8, color: colors.accent),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LayoutBuilder(builder: (context, constraints) => Row(
                    children: List.generate((constraints.maxWidth / 6).floor(), (i) =>
                      Expanded(child: Container(height: 1.5, margin: const EdgeInsets.only(right: 2), color: colors.accent.withOpacity(0.3)))),
                  )),
                ),
                Icon(Icons.location_on_rounded, size: 10, color: colors.accent),
                const SizedBox(height: 2),
                Text(durationStr, style: TextStyle(fontSize: 9, color: colors.textTertiary, fontWeight: FontWeight.w600)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(arrStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(trip.destination, style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
              ])),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon((trip.vehicleType ?? '').toLowerCase() == 'bus' ? Icons.directions_bus_rounded : Icons.directions_car_rounded, size: 16, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text((trip.vehicleType ?? 'Vehicle').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.textSecondary)),
                const SizedBox(width: 12),
                Icon(Icons.event_seat_rounded, size: 14, color: colors.textTertiary), const SizedBox(width: 4),
                Text('${trip.availableSeats} seats', style: TextStyle(fontSize: 11, color: trip.availableSeats > 5 ? colors.success : colors.warning, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('\$${trip.fareUsdc.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.accent)),
              ]),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideY(begin: 0.1, end: 0, delay: 100.ms, duration: 300.ms);
  }
}


