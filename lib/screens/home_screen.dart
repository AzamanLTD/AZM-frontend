import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
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
import 'package:azaman/services/home_summary_service.dart'
    show TransactionSummary;
import 'package:azaman/screens/spending_insights_screen.dart'
    show SpendingInsightsScreen, spendingCategoryMap, uncategorizedSpendingCategory;
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/widgets/home/az_greeting_brain.dart';
import 'package:azaman/widgets/home/az_insight_card.dart';
import 'package:azaman/widgets/home/az_refresh_reward.dart';


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

  /// Applies block [block]'s entrance choreography — or nothing at all when
  /// [reduceMotion] is set: Home simply IS there on the first frame. One
  /// method owns the whole camera move, so the entrance's tempo, direction
  /// and reduced-motion policy are each tunable from one place.
  ///
  /// Block map (see the choreography comment in [build]):
  ///   0 header    — control,   from the left  (-0.04)
  ///   1 title     — control,   from the left  (-0.04)
  ///   2 pills     — standard,  from below     (+0.12)
  ///   3 rail      — standard,  from the right (+0.06)
  ///   4 susu      — standard,  from below     (+0.06)
  ///   5 activity  — standard,  from below     (+0.06)
  ///   6 market    — standard,  from below     (+0.06)
  Widget _stage(int block, Widget child, bool reduceMotion) {
    if (reduceMotion) return child;
    final delay = block == 0 ? Duration.zero : MotionTokens.staggerDelay(block);
    final duration = block <= 1 ? MotionTokens.control : MotionTokens.standard;
    final onX = block <= 1 || block == 3;
    final begin = switch (block) {
      2 => 0.12,
      3 => 0.06,
      _ => onX ? -0.04 : 0.06,
    };
    final entered = child
        .animate()
        .fadeIn(
          delay: delay,
          duration: duration,
          curve: MotionTokens.enter,
        );
    return onX
        ? entered.slideX(
            begin: begin,
            end: 0,
            delay: delay,
            duration: duration,
            curve: MotionTokens.enter,
          )
        : entered.slideY(
            begin: begin,
            end: 0,
            delay: delay,
            duration: duration,
            curve: MotionTokens.enter,
          );
  }

  Future<void> _onRefresh() async {
    // A refresh is a "re-check the world" action, not a navigation. The
    // threshold tick is the same sensation the pull gesture armed with, so the
    // release feels like the gesture completing rather than a new event.
    // Exactly one threshold haptic per committed pull — never doubled.
    AzamanHaptics.threshold();
    // NEW-D refresh reward: capture the authoritative balance the Home deck
    // renders BEFORE the world is re-read, so the comparison is between two
    // real observations, not an invented one.
    final balanceBefore = ref.read(balanceDataProvider).availableBalance;
    final summaryFuture = ref.read(homeSummaryProvider.notifier).refresh();
    final auth = ref.read(authProvider);
    if (auth.user?.id != null) {
      // Awaited now: the balance comparison below is only honest once the
      // fresh profile (and the balance it publishes) has actually landed.
      await auth.fetchUserDetails();
    }
    await summaryFuture;
    final balanceAfter = ref.read(balanceDataProvider).availableBalance;
    if (AzRefreshReward.landed(
        before: balanceBefore, after: balanceAfter)) {
      // A settlement really landed while refreshing — the money moving up
      // on screen is the animation; this is its receipt (§H.7).
      // ignore: discarded_futures
      AzamanHaptics.moneyLanded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    // Reduced motion: Home simply IS there on the first frame — no fade, no
    // slide. Same convention as the tab transitions in main.dart and the
    // in-app push banner; the entrance is non-essential motion.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

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
                _stage(0, const _GreetingHeader(), reduceMotion),

                const SizedBox(height: AzSpace.lg),

                // Block 1 — greeting title, follows the header.
                _stage(1, const _GreetingTitle(), reduceMotion),

                const SizedBox(height: AzSpace.lg),

                // Block 2 — action pills, rise into place.
                _stage(2, const _ActionPills(), reduceMotion),

                const SizedBox(height: AzSpace.xl),

                // Block 3 — the rail, arrives from the RIGHT. This is the one
                // block that travels opposite the others, so the deck feels
                // slid into view rather than dropped in.
                _stage(3, const _BalanceCardsScroll(), reduceMotion),

                const SizedBox(height: AzSpace.xxl),

                // Block 4 — susu shortcut.
                _stage(4, const _SusuShortcutCard(), reduceMotion),

                const SizedBox(height: AzSpace.xxl),

                // Block 5 — recent activity.
                _stage(5, const RecentActivitySection(), reduceMotion),

                const SizedBox(height: AzSpace.xxl),

                // Block 6 — live market. Last to arrive; the page is fully
                // painted at staggerDelay(6) + standard = 240 + 220 = 460ms.
                _stage(6, const LiveMarketSection(), reduceMotion),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // V3 Marketplace Sprint (2026-06-21): owner notification bell — only shown
    // when the signed-in user has a registered business.

    final username = user?.username ?? '';
    final initials = _initials(username);

    // The avatar's scale is the one micro-detail inside a block the parent
    // already fades (F-015, TASK-008 spec 2c). Reduced motion drops even
    // this — the avatar simply IS there, like everything else.
    final avatarCore = ScaleTap(
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
          width: 46,
          height: 46,
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
                      width: 42,
                      height: 42,
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
    );
    final avatar = reduceMotion
        ? avatarCore
        : avatarCore
            .animate()
            .scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1, 1),
              duration: 300.ms,
              curve: Curves.easeOutBack,
            );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          avatar,
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
              border:
                  Border.all(color: colors.success.withValues(alpha: 0.2), width: 0.5),
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
                width: 40,
                height: 40,
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Read the signals where they already exist. Every input is optional: an
    // absent value means the brain skips that line rather than inventing one.
    // (NEW-D; §H.7: no streak input — streaks are not a Home mechanic.)
    final summary = ref.watch(homeSummaryProvider);
    final susuGroups = ref.watch(susuListProvider).valueOrNull ?? const [];
    final line = AzGreetingBrain.resolve(AzGreetingInputs(
      now: DateTime.now(),
      username: username,
      moneyArrivedToday: _settledInflowToday(summary.recentTransactions),
      // Escrow release timing has no Home-level authoritative source
      // (escrowProvider is trade-keyed); left null rather than invented.
      escrowReleasingInHours: null,
      susuDueTomorrow: _susuDueTomorrow(susuGroups),
      // Deposit-awaiting-approval has no authoritative Home-level source;
      // pendingWithdrawals are withdrawals, not deposits. Left null.
      depositAwaitingApproval: false,
    ));

    final glyph = Icon(
      AzGreetingBrain.glyphFor(line.tone),
      key: ValueKey(line.tone),
      size: 20,
      color: colors.accent,
    );
    final text = Text(
      line.text,
      key: ValueKey(line.text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AzText.display.copyWith(color: colors.textPrimary),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: Row(
        children: [
          // Reduced motion: the glyph and the words simply ARE there — the
          // switcher becomes an identity swap, same convention as the rest
          // of Home's entrance (TASK-008).
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : MotionTokens.control,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: glyph,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : MotionTokens.standard,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: text,
            ),
          ),
        ],
      ),
    );
  }

  /// A settled inflow today: the most recent wallet-history credit that is
  /// COMPLETED (settled) and landed today. The amount comes from the same
  /// authoritative /wallet/history snapshot the Activity section renders —
  /// no extra fetch, no invented figures. Null when nothing qualifies.
  static String? _settledInflowToday(
      List<TransactionSummary> recentTransactions) {
    for (final t in recentTransactions) {
      if (!t.isCredit || t.status != 'COMPLETED') continue;
      final created = t.createdAt;
      if (created == null) continue;
      final now = DateTime.now();
      if (created.year == now.year &&
          created.month == now.month &&
          created.day == now.day) {
        return t.symbol == 'GHS'
            ? AzMoney.ghs(t.amount)
            : AzMoney.usdc(t.amount);
      }
    }
    return null;
  }

  /// True when an ACTIVE Susu group's next pending cycle is scheduled for
  /// tomorrow — the same `nextCycle` the hub tile renders its countdown
  /// from. Real data only; no group means no claim.
  static bool _susuDueTomorrow(List<SusuSummary> groups) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    for (final g in groups) {
      if (g.status != SusuStatus.active) continue;
      final runAt = g.nextCycle?.scheduledRunAt;
      if (runAt == null) continue;
      if (runAt.year == tomorrow.year &&
          runAt.month == tomorrow.month &&
          runAt.day == tomorrow.day) {
        return true;
      }
    }
    return false;
  }
}

/// NEW-D — Home's verifiable spending insight, derived ONLY from the
/// transaction history that is ALREADY loaded (transactionHistoryProvider).
/// Home never triggers a history fetch to decorate itself (§G.8 data-source
/// rule): an empty history renders no card at all. Amounts follow the
/// insights screen's own aggregation (USDC, principal + fee, debit-only).
final _homeInsightDataProvider = Provider<AzInsightData?>((ref) {
  final items = ref.watch(transactionHistoryProvider).items;
  if (items.isEmpty) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // 7 daily buckets, oldest first, ending today.
  final daily = List<double>.filled(7, 0, growable: false);
  var lastWeekTotal = 0.0;
  final categoryTotals = <String, double>{};

  for (final t in items) {
    // Same debit definition as spending_insights_screen.dart, restricted
    // to settled records — an unsettled spend is not a fact yet.
    if (t.category != 'WITHDRAWAL' || t.status != 'COMPLETED') continue;
    final amount = t.amountUsdc + t.feeUsdc;
    final created = DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
    final ageDays = today.difference(created).inDays;
    if (ageDays < 0 || ageDays >= 14) continue;
    if (ageDays < 7) {
      daily[6 - ageDays] += amount;
      categoryTotals[t.rawType.toUpperCase()] =
          (categoryTotals[t.rawType.toUpperCase()] ?? 0) + amount;
    } else {
      lastWeekTotal += amount;
    }
  }

  final thisWeekTotal = daily.fold<double>(0, (a, b) => a + b);
  // A week with no settled spending has no insight to state — absent, not
  // zeroed (F.5).
  if (thisWeekTotal <= 0) return null;

  // Top real category this week, labelled by the insights screen's own
  // authoritative category map.
  String categoryLabel = uncategorizedSpendingCategory.label;
  var best = -1.0;
  categoryTotals.forEach((type, total) {
    if (total > best) {
      best = total;
      categoryLabel =
          (spendingCategoryMap[type] ?? uncategorizedSpendingCategory).label;
    }
  });

  return AzInsightData(
    amountText: AzMoney.usdc(thisWeekTotal),
    category: categoryLabel,
    changeFraction: lastWeekTotal > 0
        ? (thisWeekTotal - lastWeekTotal) / lastWeekTotal
        : null,
    daily: daily,
  );
});

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Icon family: hugeicons_pro, matching the bottom nav. These four names
    // are verified in-repo (`rg -o "HugeIcons(Solid|Stroke)\.[A-Za-z0-9_]+" lib`).
    // NEW-D (§G.8/§10.10): 4 → 3 — "fewer, larger, better". Withdraw is a
    // rare, considered action (and WithdrawalScreen commits via its own
    // slide-to-confirm), so it moves one tap deeper behind History, the
    // single surface that exposes "what happened" and "money out".
    final pills = [
      _PillData(label: "Add Money", icon: HugeIconsSolid.plusSign,
        onTap: () => pushWithVerticalTransition(context, const DepositScreen(initialTab: DepositTab.fiat))),
      _PillData(label: "Send", icon: HugeIconsSolid.moneySend01,
        onTap: () => pushWithVerticalTransition(context, const SendMoneyScreen())),
      _PillData(label: "History", icon: HugeIconsStroke.transactionHistory,
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: colors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(HugeIconsStroke.transactionHistory,
                        color: colors.accent),
                    title: const Text('Transaction history'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      pushWithVerticalTransition(
                          sheetContext, const TransactionHistoryScreen());
                    },
                  ),
                  ListTile(
                    leading: Icon(HugeIconsSolid.bank, color: colors.accent),
                    title: const Text('Withdraw'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      pushWithVerticalTransition(
                          sheetContext, const WithdrawalScreen());
                    },
                  ),
                ],
              ),
            ),
          );
        }),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: pills.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final pill = _buildPill(context, colors, p);
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            // Reduced motion: the pills sit at rest immediately, no stagger.
            child: reduceMotion
                ? pill
                : pill
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

    // NEW-D insight card: rendered ONLY when the already-loaded transaction
    // history yields a verifiable insight. No fetch happens from Home — if
    // the history has not been loaded by its own screen, the deck is
    // exactly what TASK-008 shipped. Nothing is faked to fill the slot.
    final insight = ref.watch(_homeInsightDataProvider);

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
          if (insight != null) ...[
            const SizedBox(width: deckGutter),
            SizedBox(
              width: screenWidth * deckCardWidthFactor,
              child: AzInsightCard(
                insight: insight,
                onTap: () => pushWithVerticalTransition(
                    context, const SpendingInsightsScreen()),
              ),
            ),
          ],
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
