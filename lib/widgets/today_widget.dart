// =============================================================================
// AZAMAN — TODAY WIDGET  (Phase G)
//
// The "morning coffee" dashboard surface that replaces the home screen's
// hardcoded Platform News carousel. Renders four counters in a 2x2 grid of
// pressable tiles:
//
//   * Active trades        → tap navigates to TradesTabScreen
//   * Pending withdrawals  → tap opens an in-place bottom sheet listing
//                            recent pending withdrawals (no dedicated detail
//                            screen exists today; sheet is enough surface)
//   * Friend requests      → tap navigates to FriendsHubScreen
//   * Unread notifications → tap navigates to /notifications via GoRouter
//
// Counters animate via implicit AnimatedSwitcher so a refresh feels alive.
// The whole widget consumes `homeSummaryProvider` so refreshes propagate
// without explicit prop-drilling.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/trades_tab_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/routed_tab_surface.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

/// Wrap a tab-body widget that doesn't ship its own Scaffold/AppBar in a
/// proper routed surface so the user gets a back button when we push it
/// from the Today tiles.
class _RoutedSurface extends StatelessWidget {
  final String title;
  final Widget body;
  const _RoutedSurface({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return RoutedTabSurface(title: title, body: body);
  }
}

class TodayWidget extends ConsumerWidget {
  const TodayWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final summary = ref.watch(homeSummaryProvider);

    // First-load skeleton — only when we've never loaded data yet.
    // Subsequent refreshes keep the previous snapshot visible (the
    // notifier guarantees this) so we don't blink.
    final isColdLoad = summary.loading &&
        summary.activeTradesCount == 0 &&
        summary.pendingWithdrawalsCount == 0 &&
        summary.friendRequestsCount == 0 &&
        summary.unreadNotifications == 0 &&
        summary.tradesError == null &&
        summary.withdrawalsError == null &&
        summary.friendsError == null &&
        summary.notificationsError == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(colors: colors, loading: summary.loading),
          const SizedBox(height: 12),
          if (isColdLoad)
            const _TodaySkeletonGrid()
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _StatTile(
                  colors: colors,
                  icon: HugeIconsSolid.exchange01,
                  label: 'Active Trades',
                  count: summary.activeTradesCount,
                  accent: colors.accent,
                  error: summary.tradesError,
                  onTap: () {
                    AzamanHaptics.nav();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _RoutedSurface(
                          title: 'Active Trades',
                          body: TradesTabScreen(),
                        ),
                      ),
                    );
                  },
                ),
                _StatTile(
                  colors: colors,
                  icon: HugeIconsSolid.moneySend01,
                  label: 'Pending Withdrawals',
                  count: summary.pendingWithdrawalsCount,
                  accent: colors.warning,
                  error: summary.withdrawalsError,
                  onTap: () {
                    AzamanHaptics.nav();
                    _PendingWithdrawalsSheet.show(
                      context,
                      summary.pendingWithdrawals,
                      colors,
                    );
                  },
                ),
                _StatTile(
                  colors: colors,
                  icon: HugeIconsSolid.userAdd01,
                  label: 'Friend Requests',
                  count: summary.friendRequestsCount,
                  accent: colors.success,
                  error: summary.friendsError,
                  onTap: () {
                    AzamanHaptics.nav();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FriendsHubScreen(),
                      ),
                    );
                  },
                ),
                _StatTile(
                  colors: colors,
                  icon: HugeIconsSolid.notification01,
                  label: 'Unread',
                  count: summary.unreadNotifications,
                  accent: colors.danger,
                  error: summary.notificationsError,
                  onTap: () {
                    AzamanHaptics.nav();
                    // GoRouter — /notifications is one of the four
                    // GoRoutes registered in app_router.dart, so this
                    // is also the path FCM deep-links land on.
                    context.push('/notifications');
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Cold-load skeleton matching the 2x2 stat-tile grid ─────────────────────

class _TodaySkeletonGrid extends StatelessWidget {
  const _TodaySkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: List.generate(
        4,
        (_) => const SkeletonBlock(
          height: double.infinity,
          width: double.infinity,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }
}

// ── Section header with optional spinner when refreshing ───────────────────

class _SectionHeader extends StatelessWidget {
  final AzamanColors colors;
  final bool loading;
  const _SectionHeader({required this.colors, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'TODAY',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textTertiary,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('idle')),
        ),
      ],
    );
  }
}

// ── Stat tile ──────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final String? error;
  final VoidCallback onTap;

  const _StatTile({
    required this.colors,
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.error,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icon + chevron row.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                Icon(Icons.arrow_forward_ios,
                    color: colors.textTertiary, size: 11),
              ],
            ),
            // Count + label.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    error != null ? '—' : '$count',
                    key: ValueKey<String>(error != null ? 'err' : '$count'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

// ── Pending withdrawals: in-place bottom-sheet listing ─────────────────────
//
// We don't have a dedicated WithdrawalHistoryScreen yet (Phase M will add
// one). For now, surfacing the list inline on tap is plenty — the tile is
// also a useful "remind me what I'm waiting on" affordance.

class _PendingWithdrawalsSheet {
  static void show(
    BuildContext context,
    List<WithdrawalSummary> items,
    AzamanColors colors,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Pending Withdrawals',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  items.isEmpty
                      ? 'No withdrawals waiting on settlement.'
                      : '${items.length} request${items.length == 1 ? '' : 's'} waiting on settlement.',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (items.isNotEmpty)
                  ...items.map(
                    (w) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.outbox_rounded,
                              color: colors.warning,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  // Phase H review pass: backend has no
                                  // `currency` column on Withdrawal —
                                  // payoutMethod (e.g. BINANCE_ID, MOMO_GHS)
                                  // is the closest semantic equivalent and
                                  // is what users care about anyway.
                                  '${w.amount.toStringAsFixed(2)}'
                                  '  ${w.payoutMethod.replaceAll('_', ' ')}',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _relative(w.createdAt),
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              w.status.toUpperCase(),
                              style: TextStyle(
                                color: colors.warning,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _relative(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
