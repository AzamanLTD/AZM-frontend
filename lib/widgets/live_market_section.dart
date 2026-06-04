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
                'LIVE MARKET',
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

          const SizedBox(height: 10),

          // ── Stable-peg trio. We display them as "Stable" rather than
          //    inventing fake price movement — the hologram model is
          //    1:1 USDC for everything that isn't local fiat.
          _PegTile(
            colors: colors,
            symbol: 'USDC',
            name: 'USD Coin',
            badge: 'STABLE',
            badgeColor: colors.success,
            accent: colors.success,
            valueLabel: r'$1.00',
          ),
          _PegTile(
            colors: colors,
            symbol: 'USDT',
            name: 'Tether USD',
            badge: 'STABLE',
            badgeColor: colors.success,
            accent: colors.success,
            valueLabel: r'$1.00',
          ),
          _PegTile(
            colors: colors,
            symbol: 'AZM',
            name: 'Azaman Token',
            badge: 'NATIVE',
            badgeColor: colors.accent,
            accent: colors.accent,
            valueLabel: r'$1.00',
          ),
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
    // Cold-load: rates haven't been fetched yet AND no error has been
    // recorded. Show a skeleton instead of "—" so the user knows
    // something is happening rather than something is wrong.
    final coldLoad = !available && error == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colors.accent.withOpacity(0.30)),
                ),
                child: Text(
                  'GH\u20B5',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'USD \u2192 GHS',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live oracle rate',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (coldLoad)
                const SkeletonBlock(width: 80, height: 28)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      unavailable
                          ? '\u2014'
                          : rates.usdToGhs.toStringAsFixed(2),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      unavailable ? 'unavailable' : 'GHS per 1 USD',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (history.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: _Sparkline(
                colors: colors,
                points: history.map((o) => o.rate).toList(growable: false),
              ),
            ),
          ] else if (coldLoad) ...[
            const SizedBox(height: 12),
            const SkeletonBlock(
              height: 36,
              width: double.infinity,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stable-peg row tile ────────────────────────────────────────────────────

class _PegTile extends StatelessWidget {
  final AzamanColors colors;
  final String symbol;
  final String name;
  final String badge;
  final Color badgeColor;
  final Color accent;
  final String valueLabel;

  const _PegTile({
    required this.colors,
    required this.symbol,
    required this.name,
    required this.badge,
    required this.badgeColor,
    required this.accent,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Text(
              symbol[0],
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valueLabel,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Set Alert" button
        GestureDetector(
          onTap: () => RateAlertSheet.show(context, ref, currentRate: currentRate),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.accent.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_active_rounded,
                    size: 14, color: colors.accent),
                const SizedBox(width: 6),
                Text(
                  'Set Rate Alert',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
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
            isAbove ? Icons.trending_up_rounded : Icons.trending_down_rounded,
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
