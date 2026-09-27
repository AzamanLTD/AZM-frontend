// =============================================================================
// AZAMAN — BOOKING SUCCESS SHEET
// Phase 11.1.2 — booking confirmation celebration bottom sheet.
// Shows after a successful transit seat booking with route info, seat count,
// departure time, and total fare. Reusable for hotel bookings too.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

class BookingSuccessSheet extends ConsumerWidget {
  final String bookingRef;
  final int seatCount;
  final double totalFare;
  final String route;
  final DateTime departureTime;

  const BookingSuccessSheet({
    super.key,
    required this.bookingRef,
    required this.seatCount,
    required this.totalFare,
    required this.route,
    required this.departureTime,
  });

  /// Convenience method to show the sheet.
  // NEW-B: Whisper weight. classify() says so — a celebration confirmation with
  // a fixed four-row receipt and two actions. It is not scrollable and it is
  // comfortably under the 45% ceiling, so it gets no detent and no handle: a
  // receipt the user must drag open is a receipt they never read.
  static Future<void> show(
    BuildContext context, {
    required String bookingRef,
    required int seatCount,
    required double totalFare,
    required String route,
    required DateTime departureTime,
  }) {
    return AzamanSheet.showWhisper<void>(
      context,
      builder: (_) => BookingSuccessSheet(
        bookingRef: bookingRef,
        seatCount: seatCount,
        totalFare: totalFare,
        route: route,
        departureTime: departureTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    // NEW-B: the weight owns surface, whisper radius and bottom safe-area, so
    // the old Container and SafeArea are deleted rather than ported. The
    // stagger is where the removed sheet-level fade-in used to live.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: AzStaggeredColumn(
        children: [
          // Success icon with bounce animation
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: colors.success,
              size: 40,
            ),
          ).animate().scale(
            delay: 100.ms,
            duration: 400.ms,
            curve: Curves.easeOutBack,
          ),

          const SizedBox(height: 20),
          Text(
            'Booking Confirmed!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reference: $bookingRef',
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          // Detail rows
          _detailRow(colors, Icons.route_rounded, 'Route', route),
          _detailRow(
            colors,
            Icons.event_seat_rounded,
            'Seats',
            '$seatCount seat${seatCount == 1 ? '' : 's'}',
          ),
          _detailRow(
            colors,
            Icons.calendar_today_rounded,
            'Departure',
            '${departureTime.day}/${departureTime.month} · '
                '${TimeOfDay.fromDateTime(departureTime).format(context)}',
          ),
          _detailRow(
            colors,
            Icons.payments_rounded,
            'Total Paid',
            '\$${totalFare.toStringAsFixed(2)} USDC',
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    AzamanHaptics.confirm();
                    Navigator.pop(context);
                    context.go('/marketplace/transit');
                  },
                  child: const Text(
                    'View My Trips',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    AzamanColors colors,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.textTertiary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
