// =============================================================================
// STAY SUMMARY BAR — the hotel vertical's persistent slot (TASK-015)
//
// The blueprint sets persistentTray: false for hotels — there is no cart. The
// persistent bottom slot instead carries the stay arithmetic: selected room,
// nights × rate = total (tabular money figures, 180ms tick-up), and the
// Reserve CTA. "Same slot, different semantics."
//
// The total is the server's quote for the room and dates when the caller has
// one (per-night pricing: weekend rates and overrides), never nights x base
// rate passed off as exact. The CTA requests the stay: the hotel confirms it
// and it is paid at the hotel ([note]).
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

  /// The server's exact total for the room and dates (stay quote).
  final double? quotedTotalUsdc;

  /// The quote is loading: no total shown, the CTA waits.
  final bool pricing;

  /// The room cannot be booked for these dates (quote said so).
  final String? unavailableReason;

  final String ctaLabel;

  /// One line under the total, e.g. where the stay is paid.
  final String? note;

  const StaySummaryBar({
    super.key,
    required this.room,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.isBooking,
    required this.onReserve,
    required this.colors,
    this.quotedTotalUsdc,
    this.pricing = false,
    this.unavailableReason,
    this.ctaLabel = 'Request stay',
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final canBook =
        room != null &&
        room!.isBookable &&
        checkIn != null &&
        checkOut != null &&
        nights > 0 &&
        !isBooking &&
        !pricing &&
        unavailableReason == null;
    final total =
        quotedTotalUsdc ??
        (room == null ? 0.0 : stayTotalFor(room!.basePriceUsdc, nights));

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AzSpace.lg,
        AzSpace.sm,
        AzSpace.lg,
        AzSpace.lg,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AzSpace.lg,
        vertical: AzSpace.md,
      ),
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
                  style: AzText.bodyS.copyWith(color: colors.textSecondary),
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
                    // One line: a long total shrinks rather than wraps.
                    builder: (context, value, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        nights == 0
                            ? '—'
                            : pricing
                            ? 'Pricing…'
                            : '\$${value.toStringAsFixed(2)} USDC · '
                                  '$nights night${nights == 1 ? '' : 's'}',
                        maxLines: 1,
                        style: AzText.money(
                          colors.accent,
                          size: AzText.sizeTitleL,
                          weight: FontWeight.w800,
                          tracking: -0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                if (unavailableReason != null || note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    unavailableReason ?? note!,
                    key: const ValueKey('stay-summary-note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AzText.caption.copyWith(
                      color: unavailableReason != null
                          ? colors.warning
                          : colors.textTertiary,
                    ),
                  ),
                ],
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
                  borderRadius: AzRadius.brMd,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
              ),
              child: isBooking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(ctaLabel, style: AzText.button),
            ),
          ),
        ],
      ),
    );
  }
}
