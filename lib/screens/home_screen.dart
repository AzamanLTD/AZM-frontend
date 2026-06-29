import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'package:azaman/screens/marketplace/business_notifications_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'package:azaman/widgets/recent_activity_section.dart';
import 'package:azaman/widgets/routed_tab_surface.dart';
import 'package:hugeicons_pro/hugeicons.dart';

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
          child: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),

                _GreetingHeader(),

                SizedBox(height: 16),

                _GreetingTitle(),

                SizedBox(height: 16),

                _ActionPills(),

                SizedBox(height: 18),

                _BalanceCardsScroll(),

                SizedBox(height: 28),

                _SusuShortcutCard(),

                SizedBox(height: 28),

                RecentActivitySection(),

                SizedBox(height: 28),

                LiveMarketSection(),
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
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.softSurface,
              ),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HugeIconsSolid.gift, size: 15, color: colors.success),
                  const SizedBox(width: 6),
                  Text(
                    'Earn AZM',
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
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.softSurface,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isVisible ? HugeIconsSolid.view : HugeIconsSolid.viewOff,
                  key: ValueKey(isVisible),
                  size: 18,
                  color: colors.textSecondary,
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
      _PillData(label: "Add Money", icon: HugeIconsSolid.add01,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const DepositScreen(initialTab: DepositTab.fiat)))),
      _PillData(label: "Send", icon: HugeIconsSolid.arrowDataTransferHorizontal,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const FriendsHubScreen()))),
      _PillData(label: "Withdraw", icon: HugeIconsSolid.bank,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const WithdrawalScreen()))),
      _PillData(label: "Savings", icon: HugeIconsSolid.piggyBank,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const RoutedTabSurface(
            title: 'Savings', body: SavingsScreen())))),
      _PillData(label: "Market", icon: HugeIconsSolid.store01,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const MarketplaceHomeScreen()))),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: pills.map((p) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _buildPill(context, colors, p),
        )).toList(),
      ),
    );
  }

  Widget _buildPill(BuildContext context, AzamanColors colors, _PillData pill) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { HapticFeedback.lightImpact(); pill.onTap(); },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider, width: 1),
          ),
          child: Icon(pill.icon, size: 22, color: colors.accent),
        ),
        const SizedBox(height: 6),
        Text(pill.label, style: TextStyle(
          color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
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
            child: const FlippableBalanceCard(),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: screenWidth * 0.38,
            child: _NewWalletCard(colors: colors),
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
          border: Border.all(color: colors.accent.withOpacity(0.3), width: 1.2),
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
                color: colors.accent.withOpacity(0.12),
              ),
              child: Icon(HugeIconsSolid.add01, size: 20, color: colors.accent),
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
      ),
    );
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
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            context.push("/susu/${next.id}");
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                colors.accent.withOpacity(0.1),
                colors.accentSecondary.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.accent.withOpacity(0.2))),
            child: Row(children: [
              Icon(HugeIconsSolid.userGroup, color: colors.accent, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Susu Circle", style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                Text(next.name, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              ])),
              Icon(HugeIconsSolid.arrowRight01, color: colors.textTertiary, size: 18),
            ]),
          ),
        );
      },
    );
  }
}
