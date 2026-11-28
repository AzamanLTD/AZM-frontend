// lib/screens/marketplace/transit_boarding_qr_screen.dart
// =============================================================================
// THE BOARDING QR — the passenger's signed code for one transit booking.
//
// The operator scans it to board the passenger (POST /transit/boarding), and
// that QR boarding is what releases the passenger's paid fare to the operator
// when the trip completes: a paid booking cannot be boarded any other way.
//
// The code exists only inside the boarding window (an hour either side of
// departure) and each one lives at most 30 minutes; outside the window the
// backend says when it opens or that it closed, and this screen says so.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/checkin_qr_screen.dart';
import 'package:azaman/services/api_client.dart';

class TransitBoardingQrScreen extends ConsumerWidget {
  const TransitBoardingQrScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final code = ref.watch(transitBoardingCodeProvider(bookingId));
    String time(DateTime d) => MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(d.toLocal()));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Boarding pass',
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Center(
        child: code.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 48,
                  color: colors.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  // The backend's own words: when the window opens, or that it
                  // closed. Nothing is invented here.
                  e is ApiException
                      ? e.message
                      : e.toString().replaceFirst(
                          'MarketplaceBookingException: ',
                          '',
                        ),
                  key: const ValueKey('boarding-qr-unavailable'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textPrimary, fontSize: 15),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(transitBoardingCodeProvider(bookingId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (c) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Show this to the driver or mate',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scanning it boards you and pays the operator your fare.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 22),
                CheckInCode(payload: c.qrPayload),
                const SizedBox(height: 16),
                if (c.expiresAt != null)
                  Text(
                    'This code works until ${time(c.expiresAt!)}. Tap New code after that.',
                    key: const ValueKey('boarding-qr-expiry'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(transitBoardingCodeProvider(bookingId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('New code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
