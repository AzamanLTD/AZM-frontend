// =============================================================================
// SAVINGS SCREEN — Tabbed Savings Hub (Master Sprint v2, 2026-05-27)
//
// Three tabs all under one roof since they're all forms of saving:
//   • Goals   — classic goal-based savings with streaks
//   • Vaults  — locked Solo Vaults with maturity dates + AZM intensity rewards
//   • Susu    — group rotational savings (the user's susu memberships)
//
// Each tab is its own scrollable body. The tab-strip is slender + sticky.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/screens/group_chat/group_chat_screen.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/screens/vault/vault_detail_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/savings_goal_sheet.dart';
import 'package:azaman/widgets/vault/vault_progress_card.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _overview;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchOverview();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOverview() async {
    try {
      final response = await apiClient.get('/savings/overview');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _overview = body['data'];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[Savings] Fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    return Column(
      children: [
        // Slender pill-style tab strip
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.divider, width: 0.7),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: colors.isDark ? Colors.black : Colors.white,
              unselectedLabelColor: colors.textSecondary,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              tabs: const [
                Tab(height: 36, text: 'Goals'),
                Tab(height: 36, text: 'Vaults'),
                Tab(height: 36, text: 'Susu'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GoalsTab(state: this, colors: colors),
              _VaultsTab(colors: colors),
              _SusuTab(colors: colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalsBody(AzamanColors colors) {
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _fetchOverview,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Savings Card
            _buildTotalSavingsCard(colors),
            const SizedBox(height: 24),

            // Streak & Stats Row
            _buildStatsRow(colors),
            const SizedBox(height: 24),

            // Upcoming Deposits
            if (_overview != null && (_overview!['upcomingDues'] as List?)?.isNotEmpty == true) ...[
              _sectionTitle(colors, 'Upcoming Deposits'),
              const SizedBox(height: 12),
              _buildUpcomingDues(colors),
              const SizedBox(height: 24),
            ],

            // Active Goals
            _sectionTitle(colors, 'Your Savings Goals'),
            const SizedBox(height: 12),
            _buildGoalsList(colors),

            const SizedBox(height: 20),

            // Create New Goal Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateGoalSheet(colors),
                icon: const Icon(HugeIconsSolid.add01, size: 20),
                label: const Text('Create Savings Goal', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 100), // Bottom nav clearance
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSavingsCard(AzamanColors colors) {
    final totalGhs = (_overview?['totalSavedGhs'] as num?)?.toDouble() ?? 0;
    final totalUsdc = (_overview?['totalSavedUsdc'] as num?)?.toDouble() ?? 0;
    final progress = (_overview?['overallProgress'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withOpacity(0.15),
            colors.accentSecondary.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: colors.accent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Lock icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(HugeIconsSolid.lock, color: colors.accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Locked Savings',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'GH\u20B5 ${totalGhs.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '\u2248 \$${totalUsdc.toStringAsFixed(2)} USDC',
                      style: TextStyle(color: colors.success, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Overall Progress', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                  Text('${progress.toStringAsFixed(1)}%', style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (progress / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: colors.divider,
                  valueColor: AlwaysStoppedAnimation(colors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(AzamanColors colors) {
    final bestStreak = (_overview?['bestStreak'] as num?)?.toInt() ?? 0;
    final currentStreak = (_overview?['currentBestStreak'] as num?)?.toInt() ?? 0;
    final totalDeposits = (_overview?['totalDepositsAllTime'] as num?)?.toInt() ?? 0;
    final activeGoals = (_overview?['activeGoalCount'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        _statCard(colors, HugeIconsSolid.fire, colors.danger,
            '$currentStreak', 'Streak'),
        const SizedBox(width: 10),
        _statCard(colors, HugeIconsSolid.award01, colors.warning,
            '$bestStreak', 'Best'),
        const SizedBox(width: 10),
        _statCard(colors, HugeIconsSolid.savings, colors.success,
            '$totalDeposits', 'Deposits'),
        const SizedBox(width: 10),
        _statCard(colors, HugeIconsSolid.flag01, colors.accent,
            '$activeGoals', 'Goals'),
      ],
    );
  }

  Widget _statCard(AzamanColors colors, IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingDues(AzamanColors colors) {
    final dues = (_overview?['upcomingDues'] as List?) ?? [];

    return Column(
      children: dues.take(3).map<Widget>((due) {
        final dueDate = DateTime.tryParse(due['dueDate']?.toString() ?? '');
        final isToday = dueDate != null && _isToday(dueDate);
        final isTomorrow = dueDate != null && _isTomorrow(dueDate);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isToday ? colors.warning.withOpacity(0.08) : colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isToday ? colors.warning.withOpacity(0.3) : colors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isToday ? HugeIconsSolid.notification01 : HugeIconsSolid.clock01,
                color: isToday ? colors.warning : colors.textTertiary,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(due['name'] ?? 'Savings', style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      isToday ? 'Due today!' : isTomorrow ? 'Due tomorrow' : 'Due ${_formatDate(dueDate!)}',
                      style: TextStyle(color: isToday ? colors.warning : colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                'GH\u20B5 ${(due['amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                style: TextStyle(color: colors.accent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGoalsList(AzamanColors colors) {
    final goals = (_overview?['goals'] as List?) ?? [];

    if (goals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          children: [
            Icon(HugeIconsSolid.savings, size: 48, color: colors.textTertiary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('No savings goals yet', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Create your first goal to start building wealth!',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textTertiary, fontSize: 11)),
          ],
        ),
      );
    }

    return Column(
      children: goals.map<Widget>((rawGoal) {
        // Defensive copy — `_overview['goals']` is freshly decoded each
        // refresh so the map is fine to pass by reference, but the sheet
        // mutates a local copy of it for optimistic UI; we want the parent
        // list to keep its own snapshot until the next overview fetch.
        final goal = Map<String, dynamic>.from(rawGoal as Map);

        final current = (goal['currentAmountGhs'] as num?)?.toDouble() ?? 0;
        final target = (goal['targetAmountGhs'] as num?)?.toDouble() ?? 1;
        final progress = (current / target).clamp(0.0, 1.0);
        final streak = (goal['streakCount'] as num?)?.toInt() ?? 0;
        final status = goal['status'] ?? 'ACTIVE';
        final statusColor = switch (status) {
          'ACTIVE' => colors.success,
          'PAUSED' => colors.warning,
          'COMPLETED' => colors.accent,
          'CANCELLED' => colors.textTertiary,
          _ => colors.textTertiary,
        };

        // Phase E: tap on a goal opens the management sheet (Fund /
        // Withdraw / Pause / Resume). The sheet calls back into
        // _fetchOverview() so the screen rebuilds with fresh balances
        // and streaks after any successful action.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            SavingsGoalSheet.show(
              context,
              goal: goal,
              onChanged: _fetchOverview,
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goal['name'] ?? 'Savings Goal',
                        style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (streak > 0) ...[
                      Icon(HugeIconsSolid.fire, color: colors.danger, size: 16),
                      const SizedBox(width: 3),
                      Text('$streak', style: TextStyle(color: colors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      HugeIconsSolid.arrowRight01,
                      color: colors.textTertiary,
                      size: 11,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: colors.divider,
                          valueColor: AlwaysStoppedAnimation(colors.accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'GH\u20B5 ${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    Text(
                      '${goal['frequency'] ?? 'WEEKLY'} | GH\u20B5 ${(goal['frequencyAmount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      style: TextStyle(color: colors.textTertiary, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(AzamanColors colors, String title) {
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _showCreateGoalSheet(AzamanColors colors) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateGoalSheet(onCreated: _fetchOverview),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}

// =============================================================================
// CREATE GOAL BOTTOM SHEET
// =============================================================================
class _CreateGoalSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateGoalSheet({required this.onCreated});

  @override
  ConsumerState<_CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends ConsumerState<_CreateGoalSheet> {
  final _nameController = TextEditingController(text: 'My Savings');
  final _targetController = TextEditingController();
  final _amountController = TextEditingController();
  String _frequency = 'WEEKLY';
  bool _isLocked = true;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_targetController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await apiClient.post('/savings/goals', {
        'name': _nameController.text,
        'targetAmountGhs': double.tryParse(_targetController.text) ?? 0,
        'frequencyAmount': double.tryParse(_amountController.text) ?? 0,
        'frequency': _frequency,
        'isLocked': _isLocked,
      });

      if (response.statusCode == 201) {
        widget.onCreated();
        if (mounted) Navigator.pop(context);
        HapticFeedback.heavyImpact();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Create Savings Goal', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),

          TextField(
            controller: _nameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Goal Name',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Target Amount (GHS)',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Amount per deposit (GHS)',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
          ),
          const SizedBox(height: 12),

          // Frequency selector
          DropdownButtonFormField<String>(
            value: _frequency,
            dropdownColor: colors.card,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Frequency',
              labelStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
            ),
            items: ['DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _frequency = v!),
          ),
          const SizedBox(height: 12),

          // Lock toggle
          SwitchListTile(
            title: Text('Lock funds until target reached', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
            subtitle: Text('2% penalty for early withdrawal', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            value: _isLocked,
            activeColor: colors.accent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _isLocked = v),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.isDark ? Colors.black : Colors.white))
                  : const Text('Create Goal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}


// =============================================================================
// SAVINGS TABS — Master Sprint v2 (2026-05-27)
// Goals / Vaults / Susu under one umbrella since they're all forms of saving.
// =============================================================================

class _GoalsTab extends StatelessWidget {
  final _SavingsScreenState state;
  final AzamanColors colors;
  const _GoalsTab({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) => state._buildGoalsBody(colors);
}

class _VaultsTab extends ConsumerWidget {
  final AzamanColors colors;
  const _VaultsTab({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultsAsync = ref.watch(vaultsProvider);
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => ref.read(vaultsProvider.notifier).refresh(),
      child: vaultsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (vaults) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.accent.withOpacity(0.20)),
                ),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.lock, color: colors.accent, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lock funds toward a goal. Auto-deposits earn AZM intensity rewards. Maturity sweeps automatically.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (vaults.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(HugeIconsSolid.lock, size: 48, color: colors.textTertiary),
                        const SizedBox(height: 12),
                        Text('No vaults yet',
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Create Vault" below to lock your first goal.',
                          style: TextStyle(color: colors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...vaults.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: VaultProgressCard(
                          vault: e.value,
                          colors: colors,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VaultDetailScreen(vaultId: e.value.id),
                              ),
                            );
                          },
                        )
                            .animate()
                            .fadeIn(delay: (e.key * 50).ms, duration: 280.ms)
                            .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
                      ),
                    ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VaultCreateScreen()),
                    );
                  },
                  icon: const Icon(HugeIconsSolid.add01, size: 18),
                  label: const Text('Create Vault',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SusuTab extends ConsumerWidget {
  final AzamanColors colors;
  const _SusuTab({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);
    return RefreshIndicator(
      color: colors.accent,
      onRefresh: () => ref.read(groupListProvider.notifier).refresh(),
      child: groupsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (groups) {
          // Susu-enabled groups go to the top, casual groups below.
          final susuGroups = groups.where((g) => g.isSusuEnabled).toList();
          final casualGroups = groups.where((g) => !g.isSusuEnabled).toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.warning.withOpacity(0.30)),
                ),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.bank, color: colors.warning, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Susu — group rotational savings. Each member contributes per cycle, the pool rotates to a new winner each cycle. Vouching is mandatory.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Phase 4 (Susu Sprint, 2026-05-31): Susu Hub entry point.
              // The new invite-channel Susus (FRIEND / PHONE / LINK) live
              // under /susu and are surfaced here alongside the legacy
              // GroupChat-based ones. Both flows coexist during rollout.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    context.push('/susu');
                  },
                  icon: Icon(HugeIconsSolid.savings,
                      size: 16, color: colors.warning),
                  label: Text(
                    'Open Private Susu Hub',
                    style: TextStyle(
                      color: colors.warning,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: colors.warning.withOpacity(0.40), width: 0.7),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (susuGroups.isNotEmpty) ...[
                Text(
                  'ACTIVE SUSU GROUPS',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ...susuGroups.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GroupRow(
                      group: g,
                      colors: colors,
                      onTap: () {
                        // Master Sprint v2: tapping a Susu-enabled group
                        // opens the group chat directly (the chat is
                        // where members coordinate). The chat screen has
                        // a header banner that deep-links into the Susu
                        // dashboard for cycle status and contracts.
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatScreen(groupId: g.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (casualGroups.isNotEmpty) ...[
                Text(
                  'GROUPS WITHOUT SUSU',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ...casualGroups.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GroupRow(
                      group: g,
                      colors: colors,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatScreen(groupId: g.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(HugeIconsSolid.userGroup, size: 48, color: colors.textTertiary),
                        const SizedBox(height: 12),
                        Text('No groups yet',
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Start a group in the Chat tab, then tap "Initiate Susu" inside it.',
                          style: TextStyle(color: colors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              // Phase 5 (2026-06-01): group creation moved to the Chat tab.
              // A Susu is now started from inside a group chat via
              // "Initiate Susu", so this page only surfaces existing Susu
              // groups (read-only) and points users to the Chat tab.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.accent.withOpacity(0.20)),
                ),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.informationCircle, color: colors.accent, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'To start a new Susu: open the Chat tab, create or open a group, then tap "Initiate Susu" from the group profile.',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _GroupRow({required this.group, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 0.7),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  colors.accent.withOpacity(0.30),
                  colors.accent.withOpacity(0.10),
                ]),
              ),
              alignment: Alignment.center,
              child: Text(
                group.name.isEmpty ? 'G' : group.name[0].toUpperCase(),
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (group.isSusuEnabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.warning.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: colors.warning.withOpacity(0.30), width: 0.7),
                          ),
                          child: Text(
                            'SUSU',
                            style: TextStyle(
                              color: colors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.members.length} members',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(HugeIconsSolid.arrowRight01, color: colors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }
}
