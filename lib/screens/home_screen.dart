import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
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
          if (hasBiz) ...[
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AzamanHaptics.nav();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BusinessNotificationsScreen(),
                  ),
                );
              },
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.softSurface,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(HugeIconsSolid.notification01,
                        size: 18, color: colors.textSecondary),
                    if (bizUnread > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.softSurface, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
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

class _ActionPills extends ConsumerWidget {
  const _ActionPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _pill(
            colors: colors,
            label: 'Add money',
            primary: true,
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DepositScreen()),
              );
            },
          ),
          const SizedBox(width: 10),
          _pill(
            colors: colors,
            label: 'Send',
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsHubScreen()),
              );
            },
          ),
          const SizedBox(width: 10),
          _pill(
            colors: colors,
            label: 'Withdraw',
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WithdrawalScreen()),
              );
            },
          ),
          const SizedBox(width: 10),
          _pill(
            colors: colors,
            label: 'Savings',
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
          const SizedBox(width: 10),
          // V3 Marketplace Sprint (2026-06-21): entry into the Premium
          // Marketplace (the same screen mounted as the 5th bottom-nav tab).
          _pill(
            colors: colors,
            label: 'Marketplace',
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MarketplaceHomeScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required AzamanColors colors,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final fg = primary ? Colors.black : colors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: primary ? colors.accent : colors.softSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOut)
        .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic);
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
    return Container(
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.card,
            ),
            child: Icon(
              HugeIconsSolid.add01,
              size: 20,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            'New',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Send, save in\nmany currencies',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
