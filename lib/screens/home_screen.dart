import 'package:flutter/material.dart';
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
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/screens/transaction_history_screen.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/theme/az_tokens.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/tap_hint_hand.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'package:azaman/widgets/recent_activity_section.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


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
    // A refresh is a "re-check the world" action, not a navigation. The
    // threshold tick is the same sensation the pull gesture armed with, so the
    // release feels like the gesture completing rather than a new event.
    AzamanHaptics.threshold();
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
        child: AzPullToRefresh(
          color: colors.accent,
          backgroundColor: colors.card,
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            // Clears the floating 62px nav pill + its 16px gutter + breathing
            // room. See AzSpace.navClearance — if the nav pill height changes,
            // this value must change with it, and it must change in ONE place.
            padding: AzSpace.navClearance,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ENTRANCE CHOREOGRAPHY ─────────────────────────────────
                // One place defines how Home arrives. Every delay comes from
                // MotionTokens.staggerDelay, so Home shares a tempo with the
                // rest of the app instead of hardcoding 100/200/300/400/500/600.
                //
                // Two rules are load-bearing here:
                //
                // 1. TOTAL TIME. The previous entrance did not finish until
                //    1000ms (last delay 600 + duration 400). The new
                //    choreography finishes at staggerDelay(6) + standard =
                //    240 + 220 = 460ms — less than half the time.
                //
                // 2. DIRECTION. A strict top-to-bottom stagger reads as a
                //    queue draining ("loading"). This one is composed like a
                //    camera move: the header and title arrive from the LEFT,
                //    the rail from the RIGHT, and the list rises from BELOW.
                //    The eye is led, not queued.
                const SizedBox(height: AzSpace.sm),

                // Block 0 — header, arrives from the left.
                const _GreetingHeader()
                    .animate()
                    .fadeIn(
                      duration: MotionTokens.control,
                      curve: MotionTokens.enter,
                    )
                    .slideX(begin: -0.04, end: 0, curve: MotionTokens.enter),

                const SizedBox(height: AzSpace.lg),

                // Block 1 — greeting title, follows the header.
                const _GreetingTitle()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(1),
                      duration: MotionTokens.control,
                      curve: MotionTokens.enter,
                    )
                    .slideX(
                      begin: -0.04,
                      end: 0,
                      delay: MotionTokens.staggerDelay(1),
                      curve: MotionTokens.enter,
                    ),

                const SizedBox(height: AzSpace.lg),

                // Block 2 — action pills, rise into place.
                const _ActionPills()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(2),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    )
                    .slideY(
                      begin: 0.12,
                      end: 0,
                      delay: MotionTokens.staggerDelay(2),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    ),

                const SizedBox(height: AzSpace.xl),

                // Block 3 — the rail, arrives from the RIGHT. This is the one
                // block that travels opposite the others, so the deck feels
                // slid into view rather than dropped in.
                const _BalanceCardsScroll()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(3),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    )
                    .slideX(
                      begin: 0.06,
                      end: 0,
                      delay: MotionTokens.staggerDelay(3),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    ),

                const SizedBox(height: AzSpace.xxl),

                // Block 4 — susu shortcut.
                const _SusuShortcutCard()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(4),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    )
                    .slideY(
                      begin: 0.06,
                      end: 0,
                      delay: MotionTokens.staggerDelay(4),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    ),

                const SizedBox(height: AzSpace.xxl),

                // Block 5 — recent activity.
                const RecentActivitySection()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(5),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    )
                    .slideY(
                      begin: 0.06,
                      end: 0,
                      delay: MotionTokens.staggerDelay(5),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    ),

                const SizedBox(height: AzSpace.xxl),

                // Block 6 — live market. Last to arrive; the page is fully
                // painted at staggerDelay(6) + standard = 240 + 220 = 460ms.
                const LiveMarketSection()
                    .animate()
                    .fadeIn(
                      delay: MotionTokens.staggerDelay(6),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    )
                    .slideY(
                      begin: 0.06,
                      end: 0,
                      delay: MotionTokens.staggerDelay(6),
                      duration: MotionTokens.standard,
                      curve: MotionTokens.enter,
                    ),
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

    final username = user?.username ?? '';
    final initials = _initials(username);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ScaleTap(
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Hero(
              tag: 'profile-avatar',
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
                      ? AzamanNetworkImage(
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
          ),
          ).animate().scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                duration: 300.ms,
                curve: Curves.easeOutBack,
              ),
          const Spacer(),
          ScaleTap(
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
                  Icon(HugeIconsSolid.gift, size: 15, color: colors.success),
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
          ScaleTap(
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
    );
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
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: Text(
        heading,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AzText.display.copyWith(color: colors.textPrimary),
      ),
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
    // Icon family: hugeicons_pro, matching the bottom nav. These four names
    // are verified in-repo (`rg -o "HugeIcons(Solid|Stroke)\.[A-Za-z0-9_]+" lib`).
    final pills = [
      _PillData(label: "Add Money", icon: HugeIconsSolid.plusSign,
        onTap: () => pushWithVerticalTransition(context, const DepositScreen(initialTab: DepositTab.fiat))),
      _PillData(label: "Send", icon: HugeIconsSolid.moneySend01,
        onTap: () => pushWithVerticalTransition(context, const SendMoneyScreen())),
      _PillData(label: "Withdraw", icon: HugeIconsSolid.bank,
        onTap: () => pushWithVerticalTransition(context, const WithdrawalScreen())),
      _PillData(label: "History", icon: HugeIconsStroke.transactionHistory,
        onTap: () => pushWithVerticalTransition(context, const TransactionHistoryScreen())),
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
                .fadeIn(
                  delay: MotionTokens.staggerDelay(i),
                  duration: MotionTokens.control,
                  curve: MotionTokens.decelerate,
                )
                .slideY(
                  begin: 0.18,
                  end: 0,
                  delay: MotionTokens.staggerDelay(i),
                  duration: MotionTokens.control,
                  curve: MotionTokens.enter,
                ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPill(BuildContext context, AzamanColors colors, _PillData pill) {
    return ScaleTap(
      onTap: () { AzamanHaptics.nav(); pill.onTap(); },
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

    // A deck, not a mixed grid.
    //
    // Before: widths 0.76 / 0.38 / 0.38. Because card 1 was twice as wide as
    // cards 2 and 3, card 2 sat half-off the screen edge on a fresh load, which
    // the eye reads as a layout bug. The content was also mixed-weight: a full
    // balance card beside two small shortcut tiles.
    //
    // After: every card is the same width, so exactly one card is hero and the
    // next PEEKS by a consistent 12% of the viewport. The peek is the
    // affordance that says "there is more to the right" — it must be
    // deliberate, not accidental.
    //
    // `clipBehavior: Clip.none` lets each card's ambient shadow bleed into the
    // screen gutter, so the hero card appears to sit ABOVE the page rather than
    // inside a letterbox. This is the screen's one full-bleed moment. If any
    // artefact appears while scrolling, set it back to `Clip.hardEdge` — the
    // shadow will simply be tighter and nothing else changes.
    const double deckCardWidthFactor = 0.88;
    const double deckGutter = AzSpace.md;

    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: screenWidth * deckCardWidthFactor,
            child: const TapHintOverlay(
              hintKey: 'has_seen_flippable_card_hint',
              child: FlippableBalanceCard(),
            ),
          ),
          const SizedBox(width: deckGutter),
          SizedBox(
            width: screenWidth * deckCardWidthFactor,
            child: _MarketplaceShortcutCard(colors: colors),
          ),
        ],
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
        AzamanHaptics.nav();
        pushWithVerticalTransition(context, const MarketplaceHomeScreen());
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
              child: const Icon(HugeIconsSolid.store01,
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
        final currentCycle = next.nextCycle?.cycleNumber ?? 1;
        final totalCycles = next.totalCycles > 0 ? next.totalCycles : 1;
        final susuProgress = currentCycle / totalCycles;
        final contributionUsdc = next.contributionUsdc;

        return GestureDetector(
          onTap: () {
            AzamanHaptics.nav();
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
                        '${AzMoney.usdc(contributionUsdc)} / cycle',
                        style: AzText.title.copyWith(color: colors.textPrimary),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(HugeIconsSolid.arrowRight01, size: 24, color: colors.textTertiary),
              ],
            ),
          ),
        );
      },
    );
  }
}
