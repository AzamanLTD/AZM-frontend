// =============================================================================
// AZAMAN — LIVE MARKET SECTION  (Phase G)
//
// Replaces the home screen's hardcoded "Core Assets" trio (AZM/USDT/GHS all
// at $1.00 forever) with real market data sourced from `homeSummaryProvider`
// (which itself reads GET /api/oracle/rates).
//
// The hologram model is single-currency-USDC: every user balance is stored
// in USDC and the local-fiat value is a UI computation. Therefore the
// "Live Market" surface communicates two things:
//
//   1. The peg row — USDC-pegged assets the user holds (USDC, USDT, AZM).
//      These are stable by definition; we don't fake price movement.
//   2. The cedi row — live USD->GHS rate from the oracle, with a small
//      in-memory sparkline of the last few rate observations so the user
//      can see the rate "breathing" without committing the backend to a
//      historical-rate endpoint we don't have yet.
//
// The sparkline only renders once we have >= 2 distinct observations.
// `_RateHistory` stores up to 24 samples in-memory; the home screen pull-
// to-refresh appends new ones each fetch. On cold-start we render a flat
// line at the live rate.
// =============================================================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/rate_alert_provider.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/services/rate_alert_service.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/rate_alert_sheet.dart';


// ── In-memory rate history (Phase G + Phase H review pass) ─────────────────
//
// Backend has no historical-rate endpoint today, so we keep a short rolling
// window of observed rates in a Riverpod state provider. Phase H moved the
// append-on-fresh-rate logic out of LiveMarketSection.build (where it
// mutated state mid-build, which trips Riverpod's debug asserts) and into
// HomeSummaryNotifier.refresh — the notifier appends after every successful
// fetch. This widget just reads.
//
// `RateObservation` is exposed (was previously `_RateObservation`) so the
// notifier in lib/providers/home_summary_provider.dart can construct one.
// When BE ships /api/oracle/history (Phase L+), swap this provider for
// the fetched series.

class RateObservation {
  final DateTime at;
  final double rate;
  const RateObservation(this.at, this.rate);
}

final rateHistoryProvider =
    StateProvider<List<RateObservation>>((ref) => const []);

// ── The section ────────────────────────────────────────────────────────────

class LiveMarketSection extends ConsumerWidget {
  const LiveMarketSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final summary = ref.watch(homeSummaryProvider);
    final rates = summary.rates;
    final history = ref.watch(rateHistoryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'TODAY\u2019S RATE',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              if (rates.isAvailable)
                Text(
                  _sourceLabel(rates),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ── USD->GHS hero row with sparkline ────────────────────────────
          _GhsHeroCard(
            colors: colors,
            rates: rates,
            history: history,
            error: summary.ratesError,
          ),

          // ── Phase Q12: Set Alert button + active alert chips ────────────
          if (rates.isAvailable) ...[
            const SizedBox(height: 8),
            _RateAlertRow(colors: colors, currentRate: rates.usdToGhs),
          ],
        ],
      ),
    );
  }

  String _sourceLabel(OracleRates rates) {
    final src = rates.source.replaceAll('_', ' ').toLowerCase();
    final ts = rates.lastSync;
    if (ts == null) return 'via $src';
    final diff = DateTime.now().difference(ts);
    String agoText;
    if (diff.inMinutes < 1) {
      agoText = 'updated just now';
    } else if (diff.inHours < 1) {
      agoText = 'updated ${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      agoText = 'updated ${diff.inHours}h ago';
    } else {
      agoText = 'updated ${diff.inDays}d ago';
    }
    return '$agoText  via $src';
  }
}

// ── USD->GHS hero card (with sparkline + error fallback) ───────────────────

class _GhsHeroCard extends StatelessWidget {
  final AzamanColors colors;
  final OracleRates rates;
  final List<RateObservation> history;
  final String? error;

  const _GhsHeroCard({
    required this.colors,
    required this.rates,
    required this.history,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final available = rates.isAvailable;
    final unavailable = !available || error != null;
    final coldLoad = !available && error == null;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                _CurrencyBadge(
                  flag: '\u{1F1FA}\u{1F1F8}',
                  label: 'USD',
                  colors: colors,
                ),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.divider),
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                ),
                const Spacer(),
                _CurrencyBadge(
                  flag: '\u{1F1EC}\u{1F1ED}',
                  label: 'GHS',
                  colors: colors,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              children: [
                if (coldLoad)
                  const SkeletonBlock(width: 160, height: 36)
                else
                  Text(
                    unavailable
                        ? '\u2014'
                        : 'GH\u20B5${rates.usdToGhs.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                const SizedBox(height: 6),
                if (coldLoad)
                  const SkeletonBlock(width: 120, height: 14)
                else
                  Text(
                    unavailable
                        ? 'Rate unavailable'
                        : '1 USD = ${rates.usdToGhs.toStringAsFixed(2)} GHS',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),

          if (history.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SizedBox(
                height: 36,
                child: _Sparkline(
                  colors: colors,
                  points: history.map((o) => o.rate).toList(growable: false),
                ),
              ),
            ),
          ] else if (coldLoad) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: const SkeletonBlock(
                height: 36,
                width: double.infinity,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final String flag;
  final String label;
  final AzamanColors colors;

  const _CurrencyBadge({
    required this.flag,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.divider.withOpacity(0.3),
          ),
          child: Text(
            flag,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Sparkline ──────────────────────────────────────────────────────────────
//
// fl_chart is already a dependency. We render a minimal single-series line
// with no axes, no grid, no titles — just the breath of the rate.

class _Sparkline extends StatelessWidget {
  final AzamanColors colors;
  final List<double> points;

  const _Sparkline({required this.colors, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i]),
    ];

    final minY = points.reduce((a, b) => a < b ? a : b);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() < 0.001) ? 0.05 : (maxY - minY) * 0.1;

    final isUpTrend = points.last >= points.first;
    final lineColor = isUpTrend ? colors.success : colors.danger;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.32,
            isStrokeCapRound: true,
            barWidth: 2.0,
            color: lineColor,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Phase Q12: Rate Alert Row (button + active alert chips) ────────────────

class _RateAlertRow extends ConsumerWidget {
  final AzamanColors colors;
  final double currentRate;

  const _RateAlertRow({required this.colors, required this.currentRate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertState = ref.watch(rateAlertProvider);
    final activeAlerts = alertState.activeAlerts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // "Set Alert" button
        GestureDetector(
          onTap: () => RateAlertSheet.show(context, ref, currentRate: currentRate),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: colors.softSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_outlined,
                    size: 17, color: colors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Set Rate Alert',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (activeAlerts.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${activeAlerts.length}',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Active alert chips (max 3 shown)
        if (activeAlerts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...activeAlerts.take(3).map((alert) => _AlertChip(
                    alert: alert,
                    colors: colors,
                  )),
              if (activeAlerts.length > 3)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Text(
                    '+${activeAlerts.length - 3} more',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AlertChip extends StatelessWidget {
  final RateAlert alert;
  final AzamanColors colors;

  const _AlertChip({required this.alert, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isAbove = alert.direction == 'ABOVE';
    final chipColor = isAbove ? colors.success : colors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAbove ? Icons.analytics_outlined : Icons.analytics_outlined,
            size: 12,
            color: chipColor,
          ),
          const SizedBox(width: 4),
          Text(
            alert.targetRate.toStringAsFixed(2),
            style: TextStyle(
              color: chipColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
