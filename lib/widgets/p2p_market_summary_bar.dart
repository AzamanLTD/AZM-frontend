// lib/widgets/p2p_market_summary_bar.dart
// =============================================================================
// P2P MARKET SUMMARY BAR — P2P Premium Sprint (2026-06-21)
//
// Sticky widget rendered above the P2P ad list (inside the SliverList,
// before the first VendorAdCard). Shows:
//
//   [Total USDC available]  [Active vendors]  [Mini method chart]
//
// The mini chart is a horizontal BarChart (fl_chart) with one bar per
// payment method, height = total available USDC for that method.
// Tapping a bar applies that payment method as a single-select filter.
//
// No network call. Computed from filteredAdsProvider.
// =============================================================================
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class P2PMarketSummaryBar extends ConsumerWidget {
  const P2PMarketSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final adState = ref.watch(filteredAdsProvider);

    return adState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (ads) {
        if (ads.isEmpty) return const SizedBox.shrink();
        // Aggregate
        final totalUsdc = ads.fold<double>(0, (s, a) => s + a.availableUsdc);
        final onlineCount = ads.where((a) => a.isOnline).length;
        final byMethod = <String, double>{};
        for (final a in ads) {
          final m = a.paymentMethod.toUpperCase();
          byMethod[m] = (byMethod[m] ?? 0) + a.availableUsdc;
        }
        final sorted = byMethod.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topMethods = sorted.take(6).toList();
        final maxVal = topMethods.isEmpty ? 1.0 : topMethods.first.value;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Row(
                children: [
                  _Stat(
                    colors: colors,
                    icon: HugeIconsSolid.wallet01,
                    label: 'Total Liquidity',
                    value: '\$${_fmt(totalUsdc)}',
                    valueColor: colors.accent,
                  ),
                  const SizedBox(width: 20),
                  _Stat(
                    colors: colors,
                    icon: HugeIconsSolid.userGroup,
                    label: 'Online Now',
                    value: '$onlineCount vendor${onlineCount == 1 ? '' : 's'}',
                    valueColor: colors.success,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.softSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Live',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (topMethods.length >= 2) ...[
                const SizedBox(height: 14),
                Text(
                  'LIQUIDITY BY PAYMENT METHOD',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: BarChart(
                    BarChartData(
                      maxY: maxVal * 1.25,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: topMethods.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.value,
                              color: colors.accent.withValues(
                                  alpha: 0.7 +
                                      0.3 * (1 - e.key / topMethods.length)),
                              width: 22,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxVal * 1.25,
                                color: colors.softSurface,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= topMethods.length) {
                                return const SizedBox.shrink();
                              }
                              final m = topMethods[i].key;
                              final label =
                                  m.length > 7 ? m.substring(0, 7) : m;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchCallback: (event, response) {
                          if (event is! FlTapUpEvent) return;
                          final idx = response?.spot?.touchedBarGroupIndex;
                          if (idx == null || idx >= topMethods.length) return;
                          final method = topMethods[idx].key;
                          AzamanHaptics.toggle();
                          // Apply as single-method filter (toggle)
                          final current = ref.read(p2pFiltersProvider);
                          final already =
                              current.paymentMethods.contains(method);
                          ref.read(p2pFiltersProvider.notifier).state =
                              current.copyWith(
                            paymentMethods: already ? {} : {method},
                          );
                        },
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (_, __, rod, ___) => BarTooltipItem(
                            '\$${_fmt(rod.toY)}',
                            TextStyle(
                              color: colors.isDark
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _Stat extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _Stat({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: colors.textTertiary),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
