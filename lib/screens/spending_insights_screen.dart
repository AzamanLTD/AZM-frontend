// =============================================================================
// AZAMAN — Spending Insights & Budgeting
//
// A Revolut/Cleo-style spending analytics screen that:
//   • Aggregates spending by category from real transaction history
//   • Shows a donut chart of spending breakdown
//   • Displays weekly spending bar chart
//   • Lets users set monthly budget goals per category
//   • Tracks progress toward budget limits with visual indicators
//
// Reference: Revolut (Spending Analytics), Cleo (Budgeting),
//            Monzo (Spending Breakdown), YNAB (Budget Goals)
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

// ── Spending category model ──────────────────────────────────────────────────

class SpendingCategory {
  final String key;
  final String label;
  final IconData icon;
  final int colorValue;

  const SpendingCategory({
    required this.key,
    required this.label,
    required this.icon,
    required this.colorValue,
  });

  Color get color => Color(colorValue);
}

// Map backend transaction types to spending categories
const _categoryMap = <String, SpendingCategory>{
  'WITHDRAWAL_FIAT': SpendingCategory(key: 'cash', label: 'Cash Withdrawals', icon: HugeIconsSolid.moneySend01, colorValue: 0xFFEF4444),
  'WITHDRAWAL_CRYPTO': SpendingCategory(key: 'crypto', label: 'Crypto Withdrawals', icon: HugeIconsSolid.bitcoinSend, colorValue: 0xFFF59E0B),
  'SUSU_CONTRIBUTION': SpendingCategory(key: 'susu', label: 'Susu Contributions', icon: HugeIconsSolid.group01, colorValue: 0xFF8B5CF6),
  'VAULT_DEPOSIT': SpendingCategory(key: 'vault', label: 'Vault Savings', icon: HugeIconsSolid.safeBox, colorValue: 0xFF3B82F6),
  'INTERNAL_TRANSFER': SpendingCategory(key: 'transfer', label: 'Transfers', icon: HugeIconsSolid.exchange01, colorValue: 0xFF06B6D4),
  'P2P_TRADE': SpendingCategory(key: 'trade', label: 'P2P Trades', icon: HugeIconsSolid.moneyReceiveFlow01, colorValue: 0xFF10B981),
  'TICKET_ESCROW_FUND': SpendingCategory(key: 'escrow', label: 'Escrow Funding', icon: HugeIconsSolid.lockKey, colorValue: 0xFF6366F1),
  'TICKET_ESCROW_FEE': SpendingCategory(key: 'fees', label: 'Fees', icon: HugeIconsSolid.flash, colorValue: 0xFFEC4899),
  'BUSINESS_INVOICE_PAYMENT': SpendingCategory(key: 'business', label: 'Business Payments', icon: HugeIconsSolid.store01, colorValue: 0xFF14B8A6),
  'EWA_WITHDRAWAL': SpendingCategory(key: 'ewa', label: 'Earned Wage Access', icon: HugeIconsSolid.wallet01, colorValue: 0xFFA855F7),
};

const _uncategorized = SpendingCategory(
  key: 'other',
  label: 'Other',
  icon: HugeIconsSolid.note01,
  colorValue: 0xFF64748B,
);

// ── Budget model ─────────────────────────────────────────────────────────────

class BudgetGoal {
  final String categoryKey;
  final double monthlyLimit;

  const BudgetGoal({required this.categoryKey, required this.monthlyLimit});
}

// ── Spending Insights Screen ─────────────────────────────────────────────────

class SpendingInsightsScreen extends ConsumerStatefulWidget {
  const SpendingInsightsScreen({super.key});

  @override
  ConsumerState<SpendingInsightsScreen> createState() => _SpendingInsightsScreenState();
}

class _SpendingInsightsScreenState extends ConsumerState<SpendingInsightsScreen> {
  bool _isLoading = true;
  List<TransactionRecord> _allTxns = [];
  Map<String, double> _categorySpending = {};
  Map<String, double> _weeklySpending = {};
  double _totalSpentThisMonth = 0;
  double _totalSpentLastMonth = 0;
  double _totalIncomeThisMonth = 0;
  List<String> _weekLabels = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load all transactions (up to a reasonable limit)
    final notifier = ref.read(transactionHistoryProvider.notifier);
    await notifier.refresh();

    final txns = ref.read(transactionHistoryProvider).items;

    // Also try loading more pages if available
    int pages = 0;
    while (ref.read(transactionHistoryProvider).hasMore && pages < 5) {
      await notifier.loadMore();
      pages++;
    }

    final allTxns = ref.read(transactionHistoryProvider).items;
    _computeInsights(allTxns);

    setState(() => _isLoading = false);
  }

  void _computeInsights(List<TransactionRecord> txns) {
    _allTxns = txns;
    _categorySpending = {};
    _weeklySpending = {};

    final now = DateTime.now();
    final thisMonth = now.month;
    final thisYear = now.year;
    final lastMonth = now.month == 1 ? 12 : now.month - 1;
    final lastMonthYear = now.month == 1 ? now.year - 1 : now.year;

    _totalSpentThisMonth = 0;
    _totalSpentLastMonth = 0;
    _totalIncomeThisMonth = 0;

    // Compute weekly spending for the last 8 weeks
    final weekStarts = <DateTime>[];
    for (int i = 7; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + i * 7));
      weekStarts.add(DateTime(weekStart.year, weekStart.month, weekStart.day));
    }
    _weekLabels = weekStarts.map((d) => DateFormat('M/d').format(d)).toList();

    for (final txn in txns) {
      final isDebit = txn.category == 'WITHDRAWAL';
      final amount = txn.amountUsdc + txn.feeUsdc;

      // This month's spending
      if (txn.createdAt.month == thisMonth && txn.createdAt.year == thisYear) {
        if (isDebit) {
          _totalSpentThisMonth += amount;
        } else {
          _totalIncomeThisMonth += amount;
        }

        // Category breakdown
        if (isDebit) {
          final cat = _categoryMap[txn.rawType.toUpperCase()] ?? _uncategorized;
          _categorySpending[cat.key] = (_categorySpending[cat.key] ?? 0) + amount;
        }
      }

      // Last month's spending for comparison
      if (txn.createdAt.month == lastMonth && txn.createdAt.year == lastMonthYear && isDebit) {
        _totalSpentLastMonth += amount;
      }

      // Weekly spending (last 8 weeks)
      if (isDebit) {
        for (int i = 0; i < weekStarts.length; i++) {
          final weekStart = weekStarts[i];
          final weekEnd = weekStart.add(const Duration(days: 7));
          if (txn.createdAt.isAfter(weekStart) && txn.createdAt.isBefore(weekEnd)) {
            final label = _weekLabels[i];
            _weeklySpending[label] = (_weeklySpending[label] ?? 0) + amount;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── App Bar ───────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: colors.surface,
              expandedHeight: 56,
              leading: IconButton(
                icon: Icon(HugeIconsSolid.arrowLeft01, size: 20, color: colors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Spending Insights',
                style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),

            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // ── Summary Cards ───────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildSummaryCards(colors)),

              // ── Donut Chart ─────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildCategoryDonut(colors)),

              // ── Weekly Bar Chart ────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildWeeklyChart(colors)),

              // ── Category Breakdown List ────────────────────────────────────
              SliverToBoxAdapter(child: _buildCategoryList(colors)),

              // ── Budget Goals (placeholder) ──────────────────────────────────
              SliverToBoxAdapter(child: _buildBudgetGoals(colors)),

              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Summary cards ──────────────────────────────────────────────────────────

  Widget _buildSummaryCards(AzamanColors colors) {
    final delta = _totalSpentLastMonth > 0
        ? ((_totalSpentThisMonth - _totalSpentLastMonth) / _totalSpentLastMonth * 100)
        : 0.0;
    final isIncrease = delta > 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              colors: colors,
              label: 'Spent This Month',
              amount: '\$${_totalSpentThisMonth.toStringAsFixed(2)}',
              delta: isIncrease ? '+${delta.toStringAsFixed(1)}%' : '${delta.toStringAsFixed(1)}%',
              isPositive: !isIncrease,
              icon: HugeIconsSolid.moneySendSquare,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SummaryCard(
              colors: colors,
              label: 'Income This Month',
              amount: '\$${_totalIncomeThisMonth.toStringAsFixed(2)}',
              delta: '',
              isPositive: true,
              icon: HugeIconsSolid.moneyReceiveFlow01,
            ),
          ),
        ],
      ),
    );
  }

  // ── Donut chart ────────────────────────────────────────────────────────────

  Widget _buildCategoryDonut(AzamanColors colors) {
    if (_categorySpending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(HugeIconsSolid.note01, size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text('No spending data yet', style: TextStyle(color: colors.textTertiary, fontSize: 15)),
          ],
        ),
      );
    }

    final sortedEntries = _categorySpending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sortedEntries.fold(0.0, (sum, e) => sum + e.value);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending Breakdown',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Total: \$${total.toStringAsFixed(2)}',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                // Donut chart
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 48,
                      sections: sortedEntries.map((entry) {
                        final cat = _categoryMap.values.firstWhere(
                          (c) => c.key == entry.key,
                          orElse: () => _uncategorized,
                        );
                        final percentage = total > 0 ? (entry.value / total * 100) : 0;
                        return PieChartSectionData(
                          color: cat.color,
                          value: entry.value,
                          title: percentage > 8 ? '${percentage.toStringAsFixed(0)}%' : '',
                          titleStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          radius: 28,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Legend
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sortedEntries.take(5).map((entry) {
                      final cat = _categoryMap.values.firstWhere(
                        (c) => c.key == entry.key,
                        orElse: () => _uncategorized,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat.label,
                                style: TextStyle(color: colors.textSecondary, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '\$${entry.value.toStringAsFixed(0)}',
                              style: TextStyle(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }

  // ── Weekly bar chart ────────────────────────────────────────────────────────

  Widget _buildWeeklyChart(AzamanColors colors) {
    final maxY = _weeklySpending.values.fold(0.0, (a, b) => math.max(a, b));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Spending',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Last 8 weeks',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.2,
                barGroups: _weekLabels.asMap().entries.map((e) {
                  final spent = _weeklySpending[e.value] ?? 0;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: spent,
                        color: colors.accent,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          toY: maxY * 1.2,
                          color: colors.softSurface,
                        ),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _weekLabels.length) return const SizedBox();
                        return Text(
                          _weekLabels[idx],
                          style: TextStyle(color: colors.textTertiary, fontSize: 9),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideY(begin: 0.05, end: 0);
  }

  // ── Category list ──────────────────────────────────────────────────────────

  Widget _buildCategoryList(AzamanColors colors) {
    if (_categorySpending.isEmpty) return const SizedBox();

    final sortedEntries = _categorySpending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sortedEntries.fold(0.0, (sum, e) => sum + e.value);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Details',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ...sortedEntries.map((entry) {
            final cat = _categoryMap.values.firstWhere(
              (c) => c.key == entry.key,
              orElse: () => _uncategorized,
            );
            final percentage = total > 0 ? (entry.value / total * 100) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(cat.icon, size: 18, color: cat.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.label,
                          style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            backgroundColor: colors.softSurface,
                            valueColor: AlwaysStoppedAnimation(cat.color),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${entry.value.toStringAsFixed(2)}',
                        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideY(begin: 0.05, end: 0);
  }

  // ── Budget goals (coming soon) ──────────────────────────────────────────────

  Widget _buildBudgetGoals(AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accent.withValues(alpha: 0.08), colors.accentSecondary.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        children: [
          Icon(HugeIconsSolid.dashboardSquare01, size: 32, color: colors.accent),
          const SizedBox(height: 12),
          Text(
            'Budget Goals — Coming Soon',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Set monthly spending limits per category and get alerts when you approach them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 300.ms);
  }
}

// ── Summary card widget ──────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final String amount;
  final String delta;
  final bool isPositive;
  final IconData icon;

  const _SummaryCard({
    required this.colors,
    required this.label,
    required this.amount,
    required this.delta,
    required this.isPositive,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            amount,
            style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (delta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              delta,
              style: TextStyle(
                color: isPositive ? colors.success : colors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
