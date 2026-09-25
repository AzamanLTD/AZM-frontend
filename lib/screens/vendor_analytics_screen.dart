import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:azaman/providers/vendor_analytics_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


// =============================================================================
// AZAMAN — VENDOR ANALYTICS SCREEN (Phase Q16-FE)
//
// Reachable from vendor dashboard → "Analytics" button.
// Shows:
//   - Period selector tabs (7D / 30D / 90D)
//   - Summary cards row (trades, volume, revenue, avg time, dispute rate)
//   - Volume chart (fl_chart line chart)
//   - Payment method breakdown list
//   - Pull-to-refresh + skeleton loading
// =============================================================================

class VendorAnalyticsScreen extends ConsumerStatefulWidget {
  const VendorAnalyticsScreen({super.key});

  @override
  ConsumerState<VendorAnalyticsScreen> createState() =>
      _VendorAnalyticsScreenState();
}

class _VendorAnalyticsScreenState extends ConsumerState<VendorAnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vendorAnalyticsProvider).fetchAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final analytics = ref.watch(vendorAnalyticsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'Analytics',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: AzPullToRefresh(
        color: colors.accent,
        onRefresh: () => analytics.refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Period Selector ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: _PeriodSelector(colors: colors),
            ),

            // ── Content ─────────────────────────────────────────────────
            if (analytics.isLoading && !analytics.hasFetched)
              SliverToBoxAdapter(child: _SkeletonContent(colors: colors))
            else if (analytics.error != null && analytics.data == null)
              SliverToBoxAdapter(
                child: _ErrorState(
                  colors: colors,
                  error: analytics.error!,
                  onRetry: () => analytics.fetchAnalytics(force: true),
                ),
              )
            else ...[
              // Summary cards
              SliverToBoxAdapter(
                child: _SummaryCardsRow(colors: colors),
              ),

              // Volume chart
              SliverToBoxAdapter(
                child: _VolumeChart(colors: colors),
              ),

              // Method breakdown header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Payment Methods',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Method breakdown list
              SliverToBoxAdapter(
                child: _MethodBreakdownList(colors: colors),
              ),

              // Bottom padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 40),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PERIOD SELECTOR
// =============================================================================

class _PeriodSelector extends ConsumerWidget {
  final AzamanColors colors;
  const _PeriodSelector({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(vendorAnalyticsProvider);
    final activePeriod = analytics.activePeriod;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: AnalyticsPeriod.values.map((period) {
          final isActive = period == activePeriod;
          return Expanded(
            child: GestureDetector(
              onTap: () => ref
                  .read(vendorAnalyticsProvider)
                  .switchPeriod(period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    period.displayLabel,
                    style: TextStyle(
                      color: isActive
                          ? (colors.isDark ? Colors.black : Colors.white)
                          : colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// SUMMARY CARDS ROW
// =============================================================================

class _SummaryCardsRow extends ConsumerWidget {
  final AzamanColors colors;
  const _SummaryCardsRow({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(vendorAnalyticsProvider).summary;
    if (summary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          // Top row: 3 cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  colors: colors,
                  label: 'Trades',
                  value: summary.totalTrades.toString(),
                  icon: Icons.swap_horiz,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  colors: colors,
                  label: 'Volume',
                  value: _formatCurrency(summary.totalVolume),
                  icon: Icons.bar_chart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  colors: colors,
                  label: 'Revenue',
                  value: _formatCurrency(summary.totalRevenue),
                  icon: Icons.analytics_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bottom row: 2 cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  colors: colors,
                  label: 'Avg Time',
                  value: '${summary.avgCompletionMinutes.toStringAsFixed(1)}m',
                  icon: Icons.access_time,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  colors: colors,
                  label: 'Dispute Rate',
                  value: '${summary.disputeRate.toStringAsFixed(1)}%',
                  icon: Icons.gavel,
                  valueColor: summary.disputeRate > 5
                      ? colors.danger
                      : summary.disputeRate > 2
                          ? colors.warning
                          : colors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000) {
      return '\$${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }
}

class _StatCard extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatCard({
    required this.colors,
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.accent, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// VOLUME CHART
// =============================================================================

class _VolumeChart extends ConsumerWidget {
  final AzamanColors colors;
  const _VolumeChart({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(vendorAnalyticsProvider).volumeTimeline;

    if (timeline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Center(
            child: Text(
              'No volume data yet',
              style: TextStyle(color: colors.textTertiary, fontSize: 14),
            ),
          ),
        ),
      );
    }

    // Build spots from timeline
    final spots = <FlSpot>[];
    double maxVolume = 0;
    for (int i = 0; i < timeline.length; i++) {
      final v = timeline[i].volume;
      if (v > maxVolume) maxVolume = v;
      spots.add(FlSpot(i.toDouble(), v));
    }

    // Avoid maxY == 0 (flat line)
    if (maxVolume == 0) maxVolume = 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Volume Over Time',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 180,
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVolume / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.divider,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        String label;
                        if (value >= 1000) {
                          label = '${(value / 1000).toStringAsFixed(1)}K';
                        } else {
                          label = value.toStringAsFixed(0);
                        }
                        return Text(
                          label,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: _getBottomInterval(timeline.length),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= timeline.length) {
                          return const SizedBox.shrink();
                        }
                        final date = timeline[idx].date;
                        // Show day/month (e.g. "12/5")
                        final parts = date.split('-');
                        if (parts.length == 3) {
                          return Text(
                            '${int.parse(parts[2])}/${int.parse(parts[1])}',
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 9,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (timeline.length - 1).toDouble(),
                minY: 0,
                maxY: maxVolume * 1.15,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: colors.accent,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: colors.accent.withValues(alpha: 0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => colors.surface,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final idx = spot.x.toInt();
                      final point = timeline[idx];
                      return LineTooltipItem(
                        '\$${point.volume.toStringAsFixed(2)}\n${point.trades} trades',
                        TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getBottomInterval(int length) {
    if (length <= 7) return 1;
    if (length <= 30) return 5;
    return 15;
  }
}

// =============================================================================
// METHOD BREAKDOWN LIST
// =============================================================================

class _MethodBreakdownList extends ConsumerWidget {
  final AzamanColors colors;
  const _MethodBreakdownList({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(vendorAnalyticsProvider).methodBreakdown;

    if (methods.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.divider),
          ),
          child: Center(
            child: Text(
              'No payment method data yet',
              style: TextStyle(color: colors.textTertiary, fontSize: 14),
            ),
          ),
        ),
      );
    }

    // Find max volume for bar normalization
    final maxVol = methods.fold<double>(
      0,
      (prev, e) => e.volume > prev ? e.volume : prev,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          children: methods.asMap().entries.map((entry) {
            final idx = entry.key;
            final method = entry.value;
            final barWidth = maxVol > 0 ? method.volume / maxVol : 0.0;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _formatMethodName(method.method),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '\$${method.volume.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Volume bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: barWidth,
                          minHeight: 6,
                          backgroundColor: colors.divider,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(colors.accent),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${method.trades} trades · \$${method.revenue.toStringAsFixed(2)} revenue',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (idx < methods.length - 1)
                  Divider(
                    height: 1,
                    color: colors.divider,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatMethodName(String method) {
    // Convert SCREAMING_CASE to Title Case
    return method
        .split('_')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}

// =============================================================================
// SKELETON LOADING
// =============================================================================

class _SkeletonContent extends StatelessWidget {
  final AzamanColors colors;
  const _SkeletonContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Summary cards skeleton
          Row(
            children: [
              Expanded(child: _SkeletonBox(colors: colors, height: 90)),
              const SizedBox(width: 10),
              Expanded(child: _SkeletonBox(colors: colors, height: 90)),
              const SizedBox(width: 10),
              Expanded(child: _SkeletonBox(colors: colors, height: 90)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SkeletonBox(colors: colors, height: 90)),
              const SizedBox(width: 10),
              Expanded(child: _SkeletonBox(colors: colors, height: 90)),
            ],
          ),
          const SizedBox(height: 24),
          // Chart skeleton
          _SkeletonBox(colors: colors, height: 200),
          const SizedBox(height: 24),
          // Method list skeleton
          _SkeletonBox(colors: colors, height: 60),
          const SizedBox(height: 8),
          _SkeletonBox(colors: colors, height: 60),
          const SizedBox(height: 8),
          _SkeletonBox(colors: colors, height: 60),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final AzamanColors colors;
  final double height;

  const _SkeletonBox({required this.colors, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
    );
  }
}

// =============================================================================
// ERROR STATE
// =============================================================================

class _ErrorState extends StatelessWidget {
  final AzamanColors colors;
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.colors,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.analytics_outlined, size: 56, color: colors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Failed to Load Analytics',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
