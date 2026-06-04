// =============================================================================
// AZAMAN — HOME SCREEN  (Phase G overhaul)
//
// Was: a static brochure (hardcoded Core Assets at $1.00 forever, hardcoded
//      Platform News, decorative quick-action buttons, pull-to-refresh that
//      slept for one second).
//
// Is now: a dynamic morning-coffee dashboard.
//
//   1. HologramBalanceCard           — unchanged. Already animates via
//                                      TweenAnimationBuilder + AnimatedSwitcher.
//   2. Quick Actions                 — unchanged (Phase 0 wired these).
//   3. Today widget   (NEW Phase G)  — counters for active trades, pending
//                                      withdrawals, friend requests, unread
//                                      notifications. Each tile navigates to
//                                      the right destination.
//   4. Live Market    (NEW Phase G)  — replaces hardcoded "Core Assets".
//                                      Pulls from /api/oracle/rates, renders
//                                      a USD->GHS hero with sparkline plus
//                                      stable-peg rows for USDC / USDT / AZM.
//   5. Platform News                 — REMOVED. Was hardcoded mock data with
//                                      no backend endpoint. The audit's
//                                      §G says "remove until ready" — done.
//                                      Today widget takes its space.
//
// Pull-to-refresh actually refreshes:
//   * homeSummaryProvider.refresh()  — re-fetches all 5 home sections in
//                                      parallel via /api/oracle/rates,
//                                      /api/trades/history, /api/wallet/history,
//                                      /api/friends/requests,
//                                      /api/notifications/unread-count.
//   * Hologram balance auto-updates  — already wired via socket.io
//                                      `balance_update` events into
//                                      balanceDataProvider; no extra fetch
//                                      needed here, but we re-trigger
//                                      AuthProvider.fetchAndSetUser() so a
//                                      stale-token user still gets a fresh
//                                      balance from /auth/me.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/routed_tab_surface.dart';
import 'package:azaman/widgets/today_widget.dart';

class AzamanHomePage extends ConsumerStatefulWidget {
  const AzamanHomePage({super.key});

  @override
  ConsumerState<AzamanHomePage> createState() => _AzamanHomePageState();
}

class _AzamanHomePageState extends ConsumerState<AzamanHomePage> {
  @override
  void initState() {
    super.initState();
    // Kick the first home-summary fetch on mount so the user's data
    // is on screen by the time they look. Idempotent — the notifier
    // guards against duplicate primes during the initial paint storm.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeSummaryProvider.notifier).primeIfNeeded();
    });
  }

  Future<void> _onRefresh() async {
    AzamanHaptics.nav();
    // Re-fetch the home snapshot. AuthProvider's balance/user re-fetch is
    // a separate concern — we kick it as a side-effect but don't await it
    // (the socket handles live balance updates anyway).
    final summaryFuture = ref.read(homeSummaryProvider.notifier).refresh();
    final auth = ref.read(authProvider);
    if (auth.user?.id != null) {
      // Best-effort balance refresh via the canonical /auth/me/:id path.
      // Failure is fine — the snapshot still loads, and the socket
      // `balance_update` channel keeps the hologram fresh.
      // ignore: discarded_futures
      auth.fetchUserDetails();
    }
    await summaryFuture;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // 1. Hologram balance — flippable. Tap → reveals breakdown
              // (Available / Escrow / Vendor pool / Vaults / Savings /
              // Susu / AZM). Tap again to flip back.
              const FlippableBalanceCard(),

              const SizedBox(height: 24),

              // 2. Quick actions row (Phase 0 wired these).
              _quickActionsHeader(colors),
              const SizedBox(height: 12),
              _quickActionsRow(context, colors),

              const SizedBox(height: 24),

              // 3. Today (NEW — Phase G).
              const TodayWidget(),

              const SizedBox(height: 24),

              // 4. Live Market (NEW — replaces hardcoded Core Assets).
              const LiveMarketSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Local layout helpers (unchanged behaviour from Phase 0/C) ──────────

  Widget _quickActionsHeader(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'Quick Actions',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _quickActionsRow(BuildContext context, AzamanColors colors) {
    // Quick actions reflect the user's four primary money flows on the
    // home dashboard:
    //
    //   • Deposit  — top up (fiat MoMo or crypto) via DepositChooserSheet
    //   • Withdraw — pay out (fiat MoMo or external crypto wallet) via
    //                WithdrawalScreen, which has dual-mode tabs
    //   • Transfer — internal user→user transfer via FriendsHub (pick a
    //                friend, then the chat-side TransferModal)
    //   • Savings  — open Savings tab
    //
    // Buy/Sell crypto are intentionally NOT here — those are P2P actions
    // and live on the P2P tab in the bottom nav, which has its own
    // dedicated affordance (the swap_horiz icon).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildQuickAction(
            colors,
            Icons.account_balance_wallet,
            'Deposit',
            colors.accent,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DepositScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          _buildQuickAction(
            colors,
            Icons.north_rounded,
            'Withdraw',
            colors.warning,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WithdrawalScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          _buildQuickAction(
            colors,
            Icons.sync_alt_rounded,
            'Transfer',
            colors.success,
            onTap: () {
              AzamanHaptics.nav();
              // Internal user→user transfers happen inside a friend chat,
              // so the entry point is the Friends Hub (pick a friend
              // → chat → "+" send-crypto button → TransferModal).
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FriendsHubScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          _buildQuickAction(
            colors,
            Icons.savings_rounded,
            'Savings',
            colors.accentSecondary,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RoutedTabSurface(
                    title: 'Savings',
                    body: SavingsScreen(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    AzamanColors colors,
    IconData icon,
    String label,
    Color accentColor, {
    required VoidCallback onTap,
  }) {
    // Slender quick-action: 28×28 icon plate, 50px tall card,
    // hairline accent border. ~38% smaller vertical footprint than the
    // previous 18-pad ListTile-feel buttons.
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor.withOpacity(0.18), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 320.ms, curve: Curves.easeOut)
          .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
    );
  }
}
