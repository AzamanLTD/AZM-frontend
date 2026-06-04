import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// PROFIT DASHBOARD — Real API Integration
//
// Fetches data from GET /api/admin/profit-breakdown and renders:
//  • Top summary cards (Total Profit 30d, Avg Daily Revenue, Total Transactions)
//  • PnL line chart (fl_chart LineChart)
//  • Revenue by source (horizontal bars)
//  • Pool balance cards
// =============================================================================

class ProfitDashboard extends ConsumerStatefulWidget {
  const ProfitDashboard({super.key});

  @override
  ConsumerState<ProfitDashboard> createState() => _ProfitDashboardState();
}

class _ProfitDashboardState extends ConsumerState<ProfitDashboard> {
  bool _isLoading = true;
  String? _error;

  // Parsed data
  double _totalProfitLast30Days = 0;
  int _totalTransactionsLast30Days = 0;
  List<_DailyPnl> _dailyPnl = [];
  Map<String, _SourceEntry> _sourceBreakdown = {};
  _PoolBalances _pools = _PoolBalances.empty();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API FETCH
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await apiClient.get('/admin/profit-breakdown');

      if (response.statusCode != 200) {
        throw Exception('Server responded with status ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['success'] != true) {
        throw Exception(body['message'] ?? 'Unknown error from server');
      }

      final data = body['data'] as Map<String, dynamic>;

      // Parse pools
      final poolsJson = data['pools'] as Map<String, dynamic>? ?? {};
      _pools = _PoolBalances(
        profitFees: (poolsJson['profitFees'] as num?)?.toDouble() ?? 0,
        fiatPool: (poolsJson['fiatPool'] as num?)?.toDouble() ?? 0,
        hotWallet: (poolsJson['hotWallet'] as num?)?.toDouble() ?? 0,
        masterCrypto: (poolsJson['masterCrypto'] as num?)?.toDouble() ?? 0,
      );

      // Parse source breakdown
      final sourceJson = data['sourceBreakdown'] as Map<String, dynamic>? ?? {};
      _sourceBreakdown = sourceJson.map((key, value) {
        final entry = value as Map<String, dynamic>;
        return MapEntry(
          key,
          _SourceEntry(
            totalUsdc: (entry['totalUsdc'] as num?)?.toDouble() ?? 0,
            count: (entry['count'] as num?)?.toInt() ?? 0,
          ),
        );
      });

      // Parse daily PnL
      final dailyJson = data['dailyPnl'] as List<dynamic>? ?? [];
      _dailyPnl = dailyJson.map((item) {
        final entry = item as Map<String, dynamic>;
        return _DailyPnl(
          date: entry['date'] as String? ?? '',
          profit: (entry['profit'] as num?)?.toDouble() ?? 0,
          volume: (entry['volume'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      // Parse totals
      _totalProfitLast30Days =
          (data['totalProfitLast30Days'] as num?)?.toDouble() ?? 0;
      _totalTransactionsLast30Days =
          (data['totalTransactionsLast30Days'] as num?)?.toInt() ?? 0;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.trending_up, color: colors.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'PROFIT & REVENUE',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textTertiary),
            onPressed: _fetchData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        color: colors.accent,
        backgroundColor: colors.surface,
        child: _buildBody(colors),
      ),
    );
  }

  Widget _buildBody(AzamanColors colors) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 16),
            Text(
              'Loading profit data...',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState(colors);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCards(colors),
        const SizedBox(height: 24),
        _buildSectionHeader('PNL LINE CHART (30 DAYS)', Icons.show_chart, colors),
        const SizedBox(height: 12),
        _buildPnlChart(colors),
        const SizedBox(height: 28),
        _buildSectionHeader('REVENUE BY SOURCE', Icons.pie_chart, colors),
        const SizedBox(height: 12),
        _buildSourceBars(colors),
        const SizedBox(height: 28),
        _buildSectionHeader('POOL BALANCES', Icons.account_balance_wallet, colors),
        const SizedBox(height: 12),
        _buildPoolCards(colors),
        const SizedBox(height: 32),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ERROR STATE
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildErrorState(AzamanColors colors) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.cloud_off_rounded, size: 56, color: colors.danger.withOpacity(0.6)),
        const SizedBox(height: 16),
        Text(
          'Failed to load data',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textTertiary, fontSize: 12),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: _fetchData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TOP SUMMARY CARDS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSummaryCards(AzamanColors colors) {
    final avgDailyRevenue = _dailyPnl.isNotEmpty
        ? _totalProfitLast30Days / _dailyPnl.length
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            label: 'Total Profit (30d)',
            value: '\$${_totalProfitLast30Days.toStringAsFixed(2)}',
            icon: Icons.attach_money,
            color: colors.success,
            colors: colors,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            label: 'Avg Daily Revenue',
            value: '\$${avgDailyRevenue.toStringAsFixed(2)}',
            icon: Icons.insights,
            color: colors.accent,
            colors: colors,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            label: 'Total Transactions',
            value: '$_totalTransactionsLast30Days',
            icon: Icons.receipt_long,
            color: colors.warning,
            colors: colors,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required AzamanColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withOpacity(0.8), size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: colors.textTertiary, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SECTION HEADER
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon, AzamanColors colors) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PNL LINE CHART
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPnlChart(AzamanColors colors) {
    if (_dailyPnl.isEmpty) {
      return _emptyPlaceholder('No PnL data available', colors);
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < _dailyPnl.length; i++) {
      spots.add(FlSpot((i + 1).toDouble(), _dailyPnl[i].profit));
    }

    final allY = spots.map((s) => s.y);
    final maxY = allY.reduce(max);
    final minY = allY.reduce(min);
    final padding = (maxY - minY) * 0.15;
    final chartMinY = minY - padding;
    final chartMaxY = maxY + padding;

    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: _dailyPnl.length.toDouble(),
          minY: chartMinY,
          maxY: chartMaxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (chartMaxY - chartMinY) / 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colors.divider,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final intVal = value.toInt();
                  if (intVal == 1 || intVal == _dailyPnl.length || intVal % 5 == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'D$intVal',
                        style: TextStyle(color: colors.textTertiary, fontSize: 9),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '\$${value.toStringAsFixed(0)}',
                      style: TextStyle(color: colors.textTertiary, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => colors.surface,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final dayIndex = spot.x.toInt() - 1;
                  final dateLabel = dayIndex >= 0 && dayIndex < _dailyPnl.length
                      ? _dailyPnl[dayIndex].date
                      : 'Day ${spot.x.toInt()}';
                  return LineTooltipItem(
                    '$dateLabel\n',
                    TextStyle(color: colors.textTertiary, fontSize: 10),
                    children: [
                      TextSpan(
                        text: '\$${spot.y.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: spot.y >= 0 ? colors.success : colors.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
            handleBuiltInTouches: true,
            getTouchedSpotIndicator: (data, spots) {
              return spots.map((spot) {
                return TouchedSpotIndicatorData(
                  FlLine(color: colors.accent.withOpacity(0.3), strokeWidth: 1),
                  FlDotData(
                    show: true,
                    getDotPainter: (s, percent, bar, index) {
                      return FlDotCirclePainter(
                        radius: 5,
                        color: colors.accent,
                        strokeWidth: 2,
                        strokeColor: colors.background,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: colors.accent,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.accent.withOpacity(0.20),
                    colors.accent.withOpacity(0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REVENUE BY SOURCE — Horizontal Bars
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSourceBars(AzamanColors colors) {
    if (_sourceBreakdown.isEmpty) {
      return _emptyPlaceholder('No source data available', colors);
    }

    final maxUsdc = _sourceBreakdown.values
        .map((e) => e.totalUsdc)
        .reduce(max);

    final sourceColors = <String, Color>{
      'EXIT_FEE': const Color(0xFFF6465D),
      'P2P_MARGIN': const Color(0xFF02C076),
      'ARBITRAGE_SPREAD': const Color(0xFFD4AF37),
      'WITHDRAWAL_FEE': const Color(0xFFF0B90B),
      'DISPUTE_RESOLUTION': const Color(0xFF8B5CF6),
      'SWAP_FEE': const Color(0xFF06B6D4),
      'SAVINGS_FEE': const Color(0xFFEC4899),
    };

    final entries = _sourceBreakdown.entries.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((entry) {
          final label = _formatSourceLabel(entry.key);
          final source = entry.value;
          final fraction = maxUsdc > 0 ? source.totalUsdc / maxUsdc : 0.0;
          final barColor = sourceColors[entry.key] ?? colors.accent;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '\$${source.totalUsdc.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: barColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${source.count}',
                            style: TextStyle(
                              color: barColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: colors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POOL BALANCES
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPoolCards(AzamanColors colors) {
    final poolEntries = [
      _PoolCardData(
        label: 'Profit Fees',
        value: _pools.profitFees,
        color: colors.success,
        icon: Icons.monetization_on,
      ),
      _PoolCardData(
        label: 'Fiat Pool',
        value: _pools.fiatPool,
        color: colors.accent,
        icon: Icons.account_balance,
      ),
      _PoolCardData(
        label: 'Hot Wallet',
        value: _pools.hotWallet,
        color: colors.warning,
        icon: Icons.wallet,
      ),
      _PoolCardData(
        label: 'Master Crypto',
        value: _pools.masterCrypto,
        color: const Color(0xFF8B5CF6),
        icon: Icons.currency_bitcoin,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: poolEntries.map((pool) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pool.color.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: pool.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(pool.icon, color: pool.color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pool.label,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '\$${_formatAmount(pool.value)}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _emptyPlaceholder(String message, AzamanColors colors) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.textTertiary, fontSize: 13),
      ),
    );
  }

  String _formatSourceLabel(String key) {
    // Convert SNAKE_CASE to Title Case
    return key
        .split('_')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  String _formatAmount(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    }
    return value.toStringAsFixed(2);
  }
}

// =============================================================================
// DATA MODELS
// =============================================================================

class _DailyPnl {
  final String date;
  final double profit;
  final double volume;

  const _DailyPnl({
    required this.date,
    required this.profit,
    required this.volume,
  });
}

class _SourceEntry {
  final double totalUsdc;
  final int count;

  const _SourceEntry({required this.totalUsdc, required this.count});
}

class _PoolBalances {
  final double profitFees;
  final double fiatPool;
  final double hotWallet;
  final double masterCrypto;

  const _PoolBalances({
    required this.profitFees,
    required this.fiatPool,
    required this.hotWallet,
    required this.masterCrypto,
  });

  factory _PoolBalances.empty() => const _PoolBalances(
        profitFees: 0,
        fiatPool: 0,
        hotWallet: 0,
        masterCrypto: 0,
      );
}

class _PoolCardData {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _PoolCardData({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}
