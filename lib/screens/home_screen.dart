import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/transaction_history_screen.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/tap_hint_hand.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'package:azaman/widgets/recent_activity_section.dart';


class AzamanHomePage extends ConsumerStatefulWidget {
  const AzamanHomePage({super.key});

  @override
  ConsumerState<AzamanHomePage> createState() => _AzamanHomePageState();
}

class _AzamanHomePageState extends ConsumerState<AzamanHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeSummaryProvider.notifier).primeIfNeeded();
    });
  }

  Future<void> _onRefresh() async {
    AzamanHaptics.nav();
    final summaryFuture = ref.read(homeSummaryProvider.notifier).refresh();
    final auth = ref.read(authProvider);
    if (auth.user?.id != null) {
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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.card,
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                _GreetingHeader().animate().fadeIn(duration: 320.ms),

                const SizedBox(height: 16),

                _GreetingTitle().animate().fadeIn(delay: 100.ms, duration: 360.ms).slideY(begin: 0.1, end: 0, delay: 100.ms, duration: 360.ms),

                const SizedBox(height: 16),

                _ActionPills().animate().fadeIn(delay: 200.ms, duration: 350.ms).slideY(begin: 0.15, end: 0, delay: 200.ms, duration: 350.ms),

                const SizedBox(height: 18),

                _BalanceCardsScroll().animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.15, end: 0, delay: 300.ms, duration: 400.ms),

                const SizedBox(height: 28),

                _SusuShortcutCard().animate().fadeIn(delay: 400.ms, duration: 400.ms).slideY(begin: 0.1, end: 0, delay: 400.ms, duration: 400.ms),

                const SizedBox(height: 28),

                RecentActivitySection().animate().fadeIn(delay: 500.ms, duration: 400.ms).slideY(begin: 0.1, end: 0, delay: 500.ms, duration: 400.ms),

                const SizedBox(height: 28),

                LiveMarketSection().animate().fadeIn(delay: 600.ms, duration: 400.ms).slideY(begin: 0.1, end: 0, delay: 600.ms, duration: 400.ms),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final isVisible = ref.watch(balanceVisibleProvider);

    // V3 Marketplace Sprint (2026-06-21): owner notification bell — only shown
    // when the signed-in user has a registered business.
    final hasBiz = ref.watch(myBusinessProvider).profile != null;
    final bizUnread = ref.watch(bizUnreadCountProvider);

    final username = user?.username ?? '';
    final initials = _initials(username);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colors.accent, colors.accentSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                ),
                child: ClipOval(
                  child: (user?.profilePictureUrl != null &&
                          user!.profilePictureUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: user.profilePictureUrl!,
                          width: 42, height: 42,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                duration: 300.ms,
                curve: Curves.easeOutBack,
              ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AzmRewardsScreen()),
              );
            },
            child: PremiumGlassContainer(
              blur: 8,
              opacity: 0.06,
              borderRadius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              enableShadow: false,
              border: Border.all(color: colors.success.withValues(alpha: 0.2), width: 0.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HugeIconsSolid.gift, size: 15, color: colors.success)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.1, 1.1),
                        duration: 800.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 5),
                  Text(
                    (user?.azmBalance ?? 0) > 0
                        ? "${user!.azmBalance.toStringAsFixed(0)} AZM"
                        : 'Earn AZM',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const NotificationBell(),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.toggle();
              ref.read(balanceVisibleProvider.notifier).state = !isVisible;
            },
            child: PremiumGlassContainer(
              blur: 8,
              opacity: 0.06,
              borderRadius: 20,
              padding: EdgeInsets.zero,
              enableShadow: false,
              child: SizedBox(
                width: 40, height: 40,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: 250.ms,
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: child.key == const ValueKey(true)
                          ? Tween(begin: 0.5, end: 1.0).animate(anim)
                          : Tween(begin: 1.0, end: 0.5).animate(anim),
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: Icon(
                      isVisible ? HugeIconsStroke.viewOff : HugeIconsStroke.view,
                      key: ValueKey(isVisible),
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 320.ms, curve: Curves.easeOut);
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'A';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

class _GreetingTitle extends ConsumerWidget {
  const _GreetingTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final username = ref.watch(authProvider).user?.username ?? '';
    final heading = username.isEmpty ? 'Welcome back' : 'Hi, $username';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        heading,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    ).animate().fadeIn(duration: 360.ms, curve: Curves.easeOut).slideY(
          begin: 0.1,
          end: 0,
          curve: Curves.easeOutCubic,
        );
  }
}

class _PillData {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PillData({required this.label, required this.icon, required this.onTap});
}

class _ActionPills extends ConsumerWidget {
  const _ActionPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final pills = [
      _PillData(label: "Add Money", icon: Icons.add,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DepositScreen(initialTab: DepositTab.fiat)))),
      _PillData(label: "Send", icon: Icons.send_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const FriendsHubScreen()))),
      _PillData(label: "Withdraw", icon: Icons.account_balance_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const WithdrawalScreen()))),
      _PillData(label: "History", icon: Icons.history,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const TransactionHistoryScreen()))),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: pills.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildPill(context, colors, p)
                .animate()
                .fadeIn(delay: (i * 80).ms, duration: 300.ms)
                .slideY(
                  begin: 0.2,
                  end: 0,
                  delay: (i * 80).ms,
                  duration: 300.ms,
                  curve: Curves.easeOutCubic,
                ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPill(BuildContext context, AzamanColors colors, _PillData pill) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { HapticFeedback.lightImpact(); pill.onTap(); },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PremiumGlassContainer(
            blur: 10,
            opacity: 0.05,
            borderRadius: 16,
            padding: EdgeInsets.zero,
            enableShadow: false,
            border: Border.all(color: colors.divider, width: 0.5),
            child: SizedBox(
              width: 52, height: 52,
              child: Center(
                child: Icon(pill.icon, size: 22, color: colors.accent),
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(
            duration: 2000.ms,
            color: colors.accent.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 6),
          Text(
            pill.label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCardsScroll extends ConsumerWidget {
  const _BalanceCardsScroll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return SizedBox(
      height: 164,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        children: [
          SizedBox(
            width: screenWidth * 0.76,
            child: const TapHintOverlay(
              hintKey: 'has_seen_flippable_card_hint',
              child: FlippableBalanceCard(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: screenWidth * 0.38,
            child: _NewWalletCard(colors: colors),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: screenWidth * 0.38,
            child: _MarketplaceShortcutCard(colors: colors),
          ),
        ],
      ),
    );
  }
}

class _NewWalletCard extends StatelessWidget {
  final AzamanColors colors;
  const _NewWalletCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DepositScreen(initialTab: DepositTab.fiat)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.accent.withValues(alpha: 0.3), width: 1.2),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42, height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.add, size: 20, color: colors.accent),
            ),
            const Spacer(),
            Text("Fund",
              style: TextStyle(color: colors.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("Deposit GHC\nor crypto",
              style: TextStyle(color: colors.textTertiary, fontSize: 11, height: 1.3)),
          ],
        ),
      )
      .animate(onPlay: (c) => c.repeat(reverse: true))
      .shimmer(
        duration: 3000.ms,
        color: colors.accent.withValues(alpha: 0.05),
      ),
    );
  }
}

class _MarketplaceShortcutCard extends ConsumerWidget {
  final AzamanColors colors;
  const _MarketplaceShortcutCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const MarketplaceHomeScreen()));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.accent, colors.accentSecondary],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42, height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.storefront_rounded,
                  size: 20, color: Colors.white),
            ),
            const Spacer(),
            const Text("Marketplace",
              style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text("Explore businesses",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
          ],
        ),
      ),
    )
    .animate()
    .fadeIn(delay: 200.ms, duration: 400.ms)
    .slideX(begin: 0.2, end: 0, delay: 200.ms, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}

class _SusuShortcutCard extends ConsumerWidget {
  const _SusuShortcutCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final susuAsync = ref.watch(susuListProvider);
    final colors    = ref.watch(themeProvider).colors;
    return susuAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
        final active = groups.where((g) => g.status == SusuStatus.active).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final next = active.first;
        final currentCycle = next.nextCycle?.cycleNumber ?? 1;
        final totalCycles = next.totalCycles > 0 ? next.totalCycles : 1;
        final susuProgress = currentCycle / totalCycles;
        final contributionUsdc = next.contributionUsdc;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            context.push("/susu/${next.id}");
          },
          child: PremiumGlassContainer(
            blur: 12,
            opacity: 0.04,
            borderRadius: 20,
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Progress ring
                SizedBox(
                  width: 56, height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: susuProgress, // 0.0 - 1.0
                        strokeWidth: 4,
                        color: colors.accent,
                        backgroundColor: colors.divider,
                      ),
                      Center(
                        child: Text(
                          '${(susuProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 400.ms, curve: Curves.easeOutBack),
                const SizedBox(width: 16),
                // Susu info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Susu Circle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                      const SizedBox(height: 3),
                      Text(
                        'Cycle $currentCycle of $totalCycles',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${contributionUsdc.toStringAsFixed(2)} / cycle',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: colors.accent),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(Icons.chevron_right_rounded, size: 24, color: colors.textTertiary),
              ],
            ),
          )
          .animate()
          .fadeIn(delay: 300.ms, duration: 400.ms)
          .slideY(begin: 0.1, end: 0, delay: 300.ms, duration: 400.ms, curve: Curves.easeOutCubic),
        );
      },
    );
  }
}
