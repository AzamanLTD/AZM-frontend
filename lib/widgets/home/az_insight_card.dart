// =============================================================================
// AZ INSIGHT CARD  (NEW-D)
//
// One insight, one number, seven bars. Renders NOTHING when the data is not
// verifiable (F.5) — never a placeholder statistic.
//
// §H.7 tone rules:
//   * spending more is a neutral fact, not a failure state — no red, no
//     destructive color, no "you overspent";
//   * no motivational or pressure language — "Down from last week." is a
//     fact, not a pat on the head.
//
// The card is dumb: Home prepares the data (amountText / category /
// changeFraction / sparkline) from authoritative, already-loaded sources.
// If Home cannot verify the data, it does not mount the card at all, and
// even if it did, the honesty gate below collapses it to nothing.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// The verifiable insight payload Home prepares. Null fields degrade the
/// card honestly: without an amount AND a category there is no insight.
class AzInsightData {
  /// Already-formatted amount from `AzMoney` (e.g. "240.00 USDC").
  final String amountText;

  /// Human-readable spending category label from the insights category map.
  final String category;

  /// Fractional change vs the previous 7 days. Null when either period is
  /// not real — the comparison then simply does not render.
  final double? changeFraction;

  /// Up to 7 daily debit totals, oldest first. Empty → no sparkline.
  final List<double> daily;

  const AzInsightData({
    required this.amountText,
    required this.category,
    this.changeFraction,
    this.daily = const [],
  });
}

class AzInsightCard extends ConsumerWidget {
  final AzInsightData? insight;

  /// Where the card goes when tapped (Home pushes SpendingInsightsScreen).
  final VoidCallback? onTap;

  const AzInsightCard({super.key, this.insight, this.onTap});

  /// Maximum bars the sparkline may show (§G.8 contract).
  static const int maxBars = 7;

  /// Keeps at most [maxBars] values, taking the MOST RECENT — a series is
  /// oldest-first, so the tail is what "this week" means.
  static List<double> normalizeSparkline(List<double> values) =>
      values.length <= maxBars ? values : values.sublist(values.length - maxBars);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The honesty gate: without an amount and a category there is no insight.
    final data = insight;
    if (data == null ||
        data.amountText.isEmpty ||
        data.category.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final change = data.changeFraction;
    final less = change != null && change < 0;
    // §H.7: down is a plain fact in the success color; up is neutral —
    // NEVER the destructive/red treatment.
    final deltaColor = change == null
        ? colors.textTertiary
        : (less ? colors.success : colors.textTertiary);

    final bars = normalizeSparkline(data.daily);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'This week',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (change != null)
                  Text(
                    '${less ? '↓' : '↑'} ${(change.abs() * 100).round()}%',
                    style: TextStyle(
                      color: deltaColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${data.amountText} on ${data.category}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              change == null
                  ? 'Not enough history yet to compare.'
                  : (less ? 'Down from last week.' : 'Up from last week.'),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (bars.length >= 2) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 26,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: AnimatedContainer(
                            key: ValueKey('az-insight-bar-$i'),
                            duration: reduceMotion
                                ? Duration.zero
                                : MotionTokens.standard,
                            curve: MotionTokens.enter,
                            height: 6 + (20 * _norm(bars, i)),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(
                                alpha: i == bars.length - 1 ? 1.0 : 0.35,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Normalises bar [i] against the series max, with a floor so an all-zero
  /// week renders flat bars instead of dividing by zero.
  static double _norm(List<double> values, int i) {
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return 0;
    return (values[i] / max).clamp(0.0, 1.0);
  }
}
