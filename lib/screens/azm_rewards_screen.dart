// =============================================================================
// AZAMAN — AZM REWARDS SCREEN (Phase E1-FE)
//
// Full-page screen for viewing AZM loyalty-point earn history and stats.
// Accessible from:
//   - Home screen AZM balance tap (hologram card)
//   - Profile screen "AZM Rewards" row
//
// Layout:
//   1. Summary card — current balance + total earned + streak info
//   2. Earn rates card — collapsible "How to earn" guide
//   3. History list — paginated, grouped by date, infinite scroll
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/azm_reward_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/azm_reward_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

class AzmRewardsScreen extends ConsumerStatefulWidget {
  const AzmRewardsScreen({super.key});

  @override
  ConsumerState<AzmRewardsScreen> createState() => _AzmRewardsScreenState();
}

class _AzmRewardsScreenState extends ConsumerState<AzmRewardsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(azmRewardProvider.notifier).primeIfNeeded();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(azmRewardProvider.notifier).loadMore();
    }
  }

  Future<void> _onRefresh() async {
    AzamanHaptics.nav();
    await ref.read(azmRewardProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(azmRewardProvider);
    final azmBalance = ref.watch(azmBalanceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AZM Rewards',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: _onRefresh,
        child: state.loading && state.rewards.isEmpty
            ? _buildSkeleton(colors)
            : CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. Summary card
                  SliverToBoxAdapter(
                    child: _buildSummaryCard(colors, azmBalance, state.summary),
                  ),

                  // 2. How to earn (collapsible)
                  SliverToBoxAdapter(
                    child: _buildEarnRatesCard(colors, state.rates),
                  ),

                  // 3. History header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        'Earn History',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // 4. History list
                  if (state.rewards.isEmpty && !state.loading)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(colors),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= state.rewards.length) {
                            return state.loadingMore
                                ? _buildLoadingMoreIndicator(colors)
                                : const SizedBox.shrink();
                          }
                          return _buildRewardTile(colors, state.rewards[index]);
                        },
                        childCount: state.rewards.length + (state.hasMore ? 1 : 0),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
      ),
    );
  }

  // ─── Summary Card ──────────────────────────────────────────────────────────

  Widget _buildSummaryCard(AzamanColors colors, double azmBalance, AzmSummary? summary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withOpacity(0.15),
            colors.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Big balance display
          Text(
            '💎',
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(height: 8),
          Text(
            '${azmBalance.toStringAsFixed(1)} AZM',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current Balance',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),

          if (summary != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.accent.withOpacity(0.2)),
            const SizedBox(height: 12),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn(colors, '${summary.totalEarned.toStringAsFixed(0)}', 'Total Earned'),
                _statColumn(colors, '${summary.bySource.length}', 'Sources'),
                _statColumn(
                  colors,
                  '${summary.bySource.values.fold<int>(0, (sum, s) => sum + s.count)}',
                  'Transactions',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statColumn(AzamanColors colors, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.accent,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ─── Earn Rates Card ───────────────────────────────────────────────────────

  Widget _buildEarnRatesCard(AzamanColors colors, AzmRates? rates) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            '✨ How to Earn AZM',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconColor: colors.textSecondary,
          collapsedIconColor: colors.textSecondary,
          children: [
            if (rates != null) ...[
              _earnRateRow(colors, '🤝', 'Complete a trade', '+${rates.tradeComplete.toStringAsFixed(0)} AZM'),
              _earnRateRow(colors, '🔥', 'Daily login streak', '+${rates.loginStreakDaily.toStringAsFixed(0)} AZM/day'),
              _earnRateRow(colors, '🎉', '7-day streak bonus', '+${rates.loginStreak7Day.toStringAsFixed(0)} AZM'),
              _earnRateRow(colors, '🚀', '30-day streak bonus', '+${rates.loginStreak30Day.toStringAsFixed(0)} AZM'),
              _earnRateRow(colors, '👥', 'Refer a friend', '+${rates.referral.toStringAsFixed(0)} AZM'),
              _earnRateRow(colors, '🏆', 'Unlock achievement', '+2–25 AZM'),
              _earnRateRow(colors, '🎯', 'Volume milestone', '+50–500 AZM'),
            ] else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Loading rates...',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _earnRateRow(AzamanColors colors, String emoji, String action, String reward) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              action,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ),
          Text(
            reward,
            style: TextStyle(
              color: colors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── History Tile ──────────────────────────────────────────────────────────

  Widget _buildRewardTile(AzamanColors colors, AzmRewardEntry entry) {
    final dt = entry.createdAt.toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '${months[dt.month - 1]} ${dt.day}, $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          // Icon
          Text(entry.sourceIcon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.reason,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${entry.amount.toStringAsFixed(1)}',
                style: TextStyle(
                  color: colors.success,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'AZM',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Empty & Loading States ────────────────────────────────────────────────

  Widget _buildEmptyState(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          const Text('💎', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'No AZM earned yet',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete trades, maintain login streaks, and unlock achievements to earn AZM loyalty points!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton(AzamanColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SkeletonBlock(height: 180, borderRadius: BorderRadius.circular(16)),
          const SizedBox(height: 16),
          SkeletonBlock(height: 60, borderRadius: BorderRadius.circular(12)),
          const SizedBox(height: 24),
          ...List.generate(5, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SkeletonBlock(height: 72, borderRadius: BorderRadius.circular(10)),
          )),
        ],
      ),
    );
  }
}
