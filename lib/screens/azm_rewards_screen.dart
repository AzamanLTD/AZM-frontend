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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/azm_reward_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/azm_reward_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:hugeicons_pro/hugeicons.dart';


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
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 20),
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
                  // 0. Auction entry card
                  SliverToBoxAdapter(
                    child: GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); context.push("/azm-auction"); },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            colors.accent.withValues(alpha: 0.15),
                            colors.accentSecondary.withValues(alpha: 0.08)]),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.accent.withValues(alpha: 0.3))),
                        child: Row(children: [
                          Container(width: 44, height: 44,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent.withValues(alpha: 0.15)),
                            child: Icon(Icons.campaign_outlined, color: colors.accent, size: 22)),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("AZM Auction", style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                            Text("Bid with AZM to boost your ads", style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                          ])),
                          Icon(Icons.arrow_forward, color: colors.textTertiary, size: 18),
                        ]),
                      ),
                    ),
                  ),
                  // 1. Summary card
                  SliverToBoxAdapter(
                    child: _buildSummaryCard(colors, azmBalance, state.summary),
                  ),

                  // 1b. Friends leaderboard (2026-07-06)
                  if (state.leaderboard.entries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildFriendsLeaderboardCard(colors, state.leaderboard),
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
            colors.accent.withValues(alpha: 0.15),
            colors.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Big balance display
          Icon(HugeIconsSolid.diamond, color: colors.accent, size: 32),
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

          // Login streak (2026-07-06) — the backend has tracked this
          // correctly since the /auth/refresh recording fix, but nothing on
          // this page ever showed it. Only rendered once we have a summary
          // with an actual streak so a fresh/never-set account doesn't show
          // a hollow "0 day streak" chip.
          if (summary != null && summary.loginStreak > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HugeIconsSolid.fire, color: colors.accent, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${summary.loginStreak}-day login streak',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (summary != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.accent.withValues(alpha: 0.2)),
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

  // ─── Friends Leaderboard Card (2026-07-06) ─────────────────────────────────

  Widget _buildFriendsLeaderboardCard(AzamanColors colors, AzmFriendsLeaderboard board) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(HugeIconsSolid.crown, color: colors.accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Friends Leaderboard',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (board.myRank != null)
                  Text(
                    'Your rank: #${board.myRank}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...board.entries.map((entry) => _leaderboardRow(colors, entry)),
        ],
      ),
    );
  }

  Widget _leaderboardRow(AzamanColors colors, AzmLeaderboardEntry entry) {
    final isTop3 = entry.rank <= 3;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: entry.isMe ? colors.accent.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: isTop3
                ? Icon(
                    HugeIconsSolid.medalFirstPlace,
                    size: 16,
                    color: entry.rank == 1
                        ? const Color(0xFFD4AF37)
                        : entry.rank == 2
                            ? colors.textSecondary
                            : const Color(0xFFB87333),
                  )
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.isMe ? '${entry.username} (You)' : entry.username,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: entry.isMe ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${entry.totalEarned.toStringAsFixed(0)} AZM',
            style: TextStyle(
              color: colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
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
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
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
