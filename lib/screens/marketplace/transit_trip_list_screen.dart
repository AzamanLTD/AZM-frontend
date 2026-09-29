// =============================================================================
// AZAMAN — TRANSIT TRIP LIST SCREEN (2026-07-02)
//
// Shows available transit trips. Customer taps a trip → seat selection.
//
// Part of the marketplace booking lifecycle overhaul.
//
// TASK-014 (§7.3): the stack of near-identical glass cards is retired.
// Trips now sit as nodes on the TransitRouteRibbon — the curve is the
// route, the nodes are departures, and tapping a node expands its detail
// card inline. The card widget itself is deleted, not parked.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/transit_route_ribbon.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

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
        title: Text(
          'Available Trips',
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: tripsAsync.when(
        loading: () => const SkeletonList(itemHeight: 80, count: 5),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                'Failed to load trips',
                style: TextStyle(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                err.toString().replaceFirst(
                  'MarketplaceBookingException: ',
                  '',
                ),
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(transitTripsProvider(businessProfileId)),
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
                  Icon(
                    Icons.directions_bus_outlined,
                    size: 64,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No trips available',
                    style: TextStyle(color: colors.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: TransitRouteRibbon(
              trips: trips,
              colors: colors,
              onTripTap: (trip) =>
                  context.push('/marketplace/transit/${trip.id}/seats'),
            ),
          );
        },
      ),
    );
  }
}
