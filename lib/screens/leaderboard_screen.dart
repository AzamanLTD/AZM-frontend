// =============================================================================
// AZAMAN V3 — LEADERBOARD SCREEN (Phase Q10)
//
// Displays vendor rankings fetched from GET /api/vendor/leaderboard.
// Features:
//   - Metric tabs (XP, Volume, Trades, Profit, Streak)
//   - Pull-to-refresh
//   - Skeleton loading state
//   - Empty state when no vendors exist
//   - Error state with retry
//   - "Your Rank" banner when user is outside top N
//   - Podium badges for top 3, highlight for "isYou" row
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/leaderboard_provider.dart';


class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  static const _metrics = LeaderboardMetric.values;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _metrics.length, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) {
      ref.read(leaderboardProvider).switchMetric(_metrics[_tabCtrl.index]);
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final lb = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'RANKINGS',
          style: TextStyle(
            color: colors.accent,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: colors.accent,
          labelColor: colors.accent,
          unselectedLabelColor: colors.textTertiary,
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
          tabs: _metrics.map((m) => Tab(text: m.label)).toList(),
        ),
      ),
      body: _buildBody(lb, colors),
    );
  }

  Widget _buildBody(LeaderboardProvider lb, AzamanColors colors) {
    // Error state
    if (lb.error != null && lb.entries.isEmpty) {
      return _ErrorState(
        message: lb.error!,
        colors: colors,
        onRetry: () => lb.refresh(),
      );
    }

    // Loading state (first load)
    if (lb.isLoading && lb.entries.isEmpty) {
      return _SkeletonList(colors: colors);
    }

    // Empty state
    if (!lb.isLoading && lb.entries.isEmpty) {
      return _EmptyState(colors: colors, onRefresh: () => lb.refresh());
    }

    // Data state with pull-to-refresh
    return RefreshIndicator(
      color: colors.accent,
      backgroundColor: colors.surface,
      onRefresh: () => lb.refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // "Your Rank" banner if user is not in top list
          if (lb.myRank != null && !lb.entries.any((e) => e.isYou))
            SliverToBoxAdapter(
              child: _MyRankBanner(
                rank: lb.myRank!,
                totalVendors: lb.totalVendors,
                colors: colors,
              ),
            ),

          // Stats summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    '${lb.totalVendors} vendors ranked',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (lb.myRank != null)
                    Text(
                      'You: #${lb.myRank}',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Leaderboard list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = lb.entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RankCard(
                      entry: entry,
                      metric: lb.activeMetric,
                      colors: colors,
                    ),
                  );
                },
                childCount: lb.entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// RANK CARD
// =============================================================================

class _RankCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final AzamanColors colors;

  const _RankCard({
    required this.entry,
    required this.metric,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isPodium = entry.rank <= 3;
    final isYou = entry.isYou;

    Color borderColor;
    Color glowColor;
    Widget leading;

    switch (entry.rank) {
      case 1:
        borderColor = const Color(0xFFFFD700);
        glowColor = const Color(0xFFFFD700).withOpacity(0.25);
        leading = _PodiumBadge(
          rank: 1,
          icon: Icons.emoji_events_outlined,
          color: const Color(0xFFFFD700),
          label: 'GOLD',
        );
      case 2:
        borderColor = const Color(0xFFC0C0C0);
        glowColor = const Color(0xFFC0C0C0).withOpacity(0.2);
        leading = _PodiumBadge(
          rank: 2,
          icon: Icons.emoji_events_outlined,
          color: const Color(0xFFC0C0C0),
          label: 'SILVER',
        );
      case 3:
        borderColor = const Color(0xFFCD7F32);
        glowColor = const Color(0xFFCD7F32).withOpacity(0.2);
        leading = _PodiumBadge(
          rank: 3,
          icon: Icons.emoji_events_outlined,
          color: const Color(0xFFCD7F32),
          label: 'BRONZE',
        );
      default:
        borderColor = colors.divider;
        glowColor = Colors.transparent;
        leading = Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${entry.rank}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    }

    return Container(
      decoration: BoxDecoration(
        color: isYou
            ? colors.accent.withOpacity(0.07)
            : isPodium
                ? colors.surface
                : colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isYou
              ? colors.accent.withOpacity(0.5)
              : isPodium
                  ? borderColor.withOpacity(0.5)
                  : colors.divider,
          width: isYou || isPodium ? 1.5 : 1,
        ),
        boxShadow: isPodium
            ? [
                BoxShadow(
                  color: glowColor,
                  blurRadius: 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isYou ? colors.accent : colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isYou) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'YOU',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (entry.kycVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: colors.accent.withOpacity(0.7),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Lv.${entry.level} · ${entry.completionRate.toStringAsFixed(0)}% completion',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _metricValue(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _metricSubtext(),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _metricValue() {
    switch (metric) {
      case LeaderboardMetric.xp:
        return '${_formatNumber(entry.xp)} XP';
      case LeaderboardMetric.volume:
        return '\$${_formatVolume(entry.totalVolume)}';
      case LeaderboardMetric.trades:
        return '${entry.tradesCompleted}';
      case LeaderboardMetric.profit:
        return '\$${_formatVolume(entry.totalProfit)}';
      case LeaderboardMetric.streak:
        return '${entry.streak} days';
    }
  }

  String _metricSubtext() {
    switch (metric) {
      case LeaderboardMetric.xp:
        return '${entry.tradesCompleted} trades';
      case LeaderboardMetric.volume:
        return '${entry.tradesCompleted} trades';
      case LeaderboardMetric.trades:
        return '\$${_formatVolume(entry.totalVolume)} vol';
      case LeaderboardMetric.profit:
        return '${entry.tradesCompleted} trades';
      case LeaderboardMetric.streak:
        return 'best: ${entry.longestStreak}d';
    }
  }

  String _formatVolume(double vol) {
    if (vol >= 1000000) return '${(vol / 1000000).toStringAsFixed(1)}M';
    if (vol >= 1000) return '${(vol / 1000).toStringAsFixed(1)}K';
    return vol.toStringAsFixed(0);
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

// =============================================================================
// PODIUM BADGE
// =============================================================================

class _PodiumBadge extends StatelessWidget {
  final int rank;
  final IconData icon;
  final Color color;
  final String label;

  const _PodiumBadge({
    required this.rank,
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 6,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MY RANK BANNER (shown when user is outside the top N)
// =============================================================================

class _MyRankBanner extends StatelessWidget {
  final int rank;
  final int totalVendors;
  final AzamanColors colors;

  const _MyRankBanner({
    required this.rank,
    required this.totalVendors,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, color: colors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your rank: #$rank of $totalVendors vendors',
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Keep trading!',
            style: TextStyle(
              color: colors.accent.withOpacity(0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SKELETON LOADING STATE
// =============================================================================

class _SkeletonList extends StatelessWidget {
  final AzamanColors colors;

  const _SkeletonList({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _SkeletonCard(colors: colors),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final AzamanColors colors;

  const _SkeletonCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          children: [
            // Rank placeholder
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.divider.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.divider.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 60,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.divider.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.divider.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 35,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.divider.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onRefresh;

  const _EmptyState({required this.colors, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 56,
              color: colors.textTertiary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Rankings Yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete trades to appear on the leaderboard.\nRankings update in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRefresh,
              icon: Icon(Icons.refresh, size: 16, color: colors.accent),
              label: Text(
                'Refresh',
                style: TextStyle(color: colors.accent, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ERROR STATE
// =============================================================================

class _ErrorState extends StatelessWidget {
  final String message;
  final AzamanColors colors;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.colors,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi,
              size: 48,
              color: colors.textTertiary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Rankings',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
