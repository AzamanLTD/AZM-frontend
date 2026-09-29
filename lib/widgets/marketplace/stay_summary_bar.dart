// =============================================================================
// STAY SUMMARY BAR — the hotel vertical's persistent slot (TASK-015)
//
// The blueprint sets persistentTray: false for hotels — there is no cart. The
// persistent bottom slot instead carries the stay arithmetic: selected room,
// nights × rate = total (tabular money figures, 180ms tick-up), and the
// Reserve CTA. "Same slot, different semantics."
//
// The total is driven by the caller's state, so it updates live on every
// scrubber frame. The tick-up is a TweenAnimationBuilder — finite, timer-free,
// test-safe.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/stay_date_ribbon.dart';

class StaySummaryBar extends StatelessWidget {
  final HotelRoom? room;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final bool isBooking;
  final VoidCallback onReserve;
  final AzamanColors colors;

  const StaySummaryBar({
    super.key,
    required this.room,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.isBooking,
    required this.onReserve,
    required this.colors,
  });

  @override
 Widget build(BuildContext context) {
    final canBook = room != null &&
        room!.isBookable &&
        checkIn != null &&
        checkOut != null &&
        nights > 0 &&
        !isBooking;
    final total =
        room == null ? 0.0 : stayTotalFor(room!.basePriceUsdc, nights);

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AzSpace.lg, AzSpace.sm, AzSpace.lg, AzSpace.lg),
      padding: const EdgeInsets.symmetric(
          horizontal: AzSpace.lg, vertical: AzSpace.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AzRadius.brXxl,
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room == null
                      ? 'Choose a room and dates'
                      : '${room!.displayType} · Room ${room!.roomNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AzText.bodyS.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AzSpace.xxs),
                Semantics(
                  liveRegion: true,
                  label:
                      'Stay total \$${total.toStringAsFixed(2)} USDC for $nights nights',
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: total),
                    duration: MotionTokens.control,
                    curve: MotionTokens.enter,
                    builder: (context, value, _) => Text(
                      nights == 0
                          ? '—'
                          : '\$${value.toStringAsFixed(2)} USDC · '
                              '$nights night${nights == 1 ? '' : 's'}',
                      style: AzText.money(
                        colors.accent,
                        size: AzText.sizeTitleL,
                        weight: FontWeight.w800,
                        tracking: -0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AzSpace.md),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: canBook
                  ? () {
                      AzamanHaptics.confirm();
                      onReserve();
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colors.softSurface,
                disabledForegroundColor: colors.textTertiary,
                shape: const RoundedRectangleBorder(
                    borderRadius: AzRadius.brMd),
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
              ),
              child: isBooking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Reserve', style: AzText.button),
            ),
          ),
        ],
      ),
    );
  }
}
