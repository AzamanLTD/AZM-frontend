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

class _TripCard extends ConsumerWidget {
  final TransitTrip trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));

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

    final seatStatus = trip.availableSeats > 10
        ? colors.success
        : trip.availableSeats > 0
            ? colors.warning
            : colors.danger;
    final isFull = trip.availableSeats == 0;

    return GestureDetector(
      onTap: !isFull ? () => context.push('/marketplace/transit/${trip.id}/seats') : null,
      child: PremiumGlassContainer(
        blur: 12, opacity: 0.04, borderRadius: 18,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        enableShadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Route header ──
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(depStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.textPrimary)),
                const SizedBox(height: 3),
                Text(trip.origin, style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              // Route line with vehicle icon
              SizedBox(
                width: 70,
                child: Column(children: [
                  Icon((trip.vehicleType ?? '').toLowerCase() == 'bus'
                      ? Icons.directions_bus_rounded : Icons.directions_car_rounded,
                      size: 20, color: colors.accent),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: LayoutBuilder(builder: (context, constraints) => Row(
                      children: List.generate((constraints.maxWidth / 6).floor(), (i) =>
                          Expanded(child: Container(
                            height: 2, margin: const EdgeInsets.only(right: 2),
                            color: i < (constraints.maxWidth / 6).floor() * 0.7
                                ? colors.accent.withOpacity(0.4) : colors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(1),
                          ))),
                    )),
                  ),
                  Icon(Icons.location_on_rounded, size: 12, color: colors.accent),
                  const SizedBox(height: 2),
                  Text(durationStr, style: TextStyle(fontSize: 9, color: colors.textTertiary, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(arrStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colors.textPrimary)),
                const SizedBox(height: 3),
                Text(trip.destination, style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
              ])),
            ]),
            const SizedBox(height: 14),
            // ── Info bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text((trip.vehicleType ?? 'Vehicle').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: colors.accent, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Row(children: [
                  Icon(Icons.event_seat_rounded, size: 14, color: seatStatus),
                  const SizedBox(width: 4),
                  Text(isFull ? 'FULL' : '${trip.availableSeats} seats left',
                      style: TextStyle(fontSize: 11, color: seatStatus, fontWeight: FontWeight.w700)),
                ]),
                const Spacer(),
                Text('\$${trip.fareUsdc.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.accent)),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.calendar_today_rounded, size: 12, color: colors.textTertiary),
              const SizedBox(width: 5),
              Text(_formatDate(trip.departureAt),
                  style: TextStyle(fontSize: 11, color: colors.textTertiary, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideY(begin: 0.08, end: 0, delay: 100.ms, duration: 300.ms);
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}


