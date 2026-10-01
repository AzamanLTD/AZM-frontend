// =============================================================================
// AZAMAN — HOME  (NEW-HOME: reactive, wallet-first redesign)
//
// Resting hierarchy (brief §1):
//   1. top identity/header
//   2. typewriter greeting / contextual message   (§2)
//   3. balance card (hero, unchanged visual)       (§3)
//   4. pull-reveal Visa card deck beneath it       (§4-6)
//   5. Save / P2P / Susu compact wallet modules    (§9)
//   6. Recent Activity heading / doorway           (§10)
//
// Removed from the resting Home: the action-pill row (§7), the horizontal
// card rail (§4), the three transaction rows (§10) and the LiveMarket /
// TODAY'S RATE section (§14). The underlying rate/insight/data systems are
// untouched elsewhere — only their Home presence is gone.
//
// The Home also gains a SECOND RESTING STATE (§11): pulling the doorway
// commits a physical, resisted handoff into the in-Home activity surface,
// and the wallet composition moves out of the way. Tapping the doorway
// still navigates to the canonical activity screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/tap_hint_hand.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/az_refresh_reward.dart';
import 'package:azaman/providers/home_shell_active_provider.dart';
import 'package:azaman/widgets/home/pull_reveal_card_deck.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/scale_tap.dart';

class AzamanHomePage extends ConsumerStatefulWidget {
  const AzamanHomePage({super.key});

  @override
  ConsumerState<AzamanHomePage> createState() => _AzamanHomePageState();
}

class _AzamanHomePageState extends ConsumerState<AzamanHomePage>
    with TickerProviderStateMixin {
  /// The wallet→activity handoff (§11): 0 = wallet rest, 1 = activity rest.
  late final AnimationController _handoff = AnimationController(
    vsync: this,
    duration: MotionTokens.spatial,
    lowerBound: 0,
    upperBound: 1,
    value: 0,
  );
  double _handoffDragPx = 0;
  bool _handoffHapticArmed = false;

  /// Card deck state (§4-6): whether the pull committed and whether the
  /// PIN gate has passed for this session.
  final GlobalKey<_DeckHostState> _deckKey = GlobalKey<_DeckHostState>();

  @override
  void initState() {
    super.initState();
    _handoff.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeSummaryProvider.notifier).primeIfNeeded();
    });
  }

  @override
  void dispose() {
    _handoff.dispose();
    super.dispose();
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  /// Applies a block's entrance choreography — or nothing at all when
  /// reduceMotion is set: Home simply IS there on the first frame.
  ///
  /// Block map (camera-move composition):
  ///   0 header     — control,  from the left  (-0.04)
  ///   1 heading    — control,  from the left  (-0.04)
  ///   2 deck       — standard, from below     (+0.08)
  ///   3 modules    — standard, from below     (+0.06)
  ///   4 doorway    — standard, from below     (+0.06)
  Widget _stage(int block, Widget child, bool reduceMotion) {
    if (reduceMotion) return child;
    final delay = block == 0 ? Duration.zero : MotionTokens.staggerDelay(block);
    final duration = block <= 1 ? MotionTokens.control : MotionTokens.standard;
    final onX = block <= 1;
    final begin = switch (block) {
      2 => 0.08,
      _ => onX ? -0.04 : 0.06,
    };
    final entered = child
        .animate()
        .fadeIn(delay: delay, duration: duration, curve: MotionTokens.enter);
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
    // A refresh is a "re-check the world" action. Exactly one threshold
    // haptic per committed pull — never doubled.
    AzamanHaptics.threshold();
    // NEW-D refresh reward: compare two REAL balance observations.
    final balanceBefore = ref.read(balanceDataProvider).availableBalance;
    final summaryFuture = ref.read(homeSummaryProvider.notifier).refresh();
    final auth = ref.read(authProvider);
    if (auth.user?.id != null) {
      await auth.fetchUserDetails();
    }
    await summaryFuture;
    final balanceAfter = ref.read(balanceDataProvider).availableBalance;
    if (AzRefreshReward.landed(before: balanceBefore, after: balanceAfter)) {
      // ignore: discarded_futures
      AzamanHaptics.moneyLanded();
    }
  }

  // ── ACTIVITY HANDOFF GESTURE (§11) ────────────────────────────────────

  void _onDoorwayDragStart(DragStartDetails _) {
    _handoffDragPx = 0;
    _handoffHapticArmed = true;
  }

  void _onDoorwayDragUpdate(DragUpdateDetails d) {
    // AUDIT §1 (gesture direction): the physical gesture must match the
    // surface being revealed. The activity surface rises from BELOW, so
    // the finger drags UP and the content follows the finger — wallet
    // up, activity up. (The reverse handoff keeps the same grammar:
    // dragging DOWN from the activity top walks the stack back up to
    // the wallet.) An upward delta is negative dy, hence the negation.
    _handoffDragPx -= d.delta.dy;
    final progress = ActivityHandoffPhysics.progressFor(_handoffDragPx);
    _handoff.value = ActivityHandoffPhysics.revealFor(progress);
  }

  void _onDoorwayDragEnd(DragEndDetails _) {
    final progress = ActivityHandoffPhysics.progressFor(_handoffDragPx);
    if (ActivityHandoffPhysics.commits(progress)) {
      // Threshold crossed: the activity surface snaps into focus.
      if (_handoffHapticArmed) {
        AzamanHaptics.threshold();
        _handoffHapticArmed = false;
      }
      if (_reduceMotion) {
        _handoff.value = 1;
      } else {
        _handoff.animateWith(_handoffSpringTo(1));
      }
    } else {
      if (_reduceMotion) {
        _handoff.value = 0;
      } else {
        _handoff.animateWith(_handoffSpringTo(0));
      }
    }
    _handoffDragPx = 0;
  }

  // REVERSE HANDOFF (audit §1): pulling down from the top of the activity
  // surface walks the handoff back with the same resistance grammar — a
  // small pull moves the wallet barely at all; past the commit threshold
  // the wallet state takes over. Below threshold the activity state
  // springs back.
  void _onActivityPullUpdate(double dragPx) {
    final reverseProgress = ActivityHandoffPhysics.progressFor(dragPx);
    _handoff.value = 1 - ActivityHandoffPhysics.revealFor(reverseProgress);
  }

  void _onActivityPullEnd(bool commits) {
    if (commits) {
      if (_handoffHapticArmed) {
        AzamanHaptics.threshold();
        _handoffHapticArmed = false;
      }
      _collapseActivity();
    } else {
      if (_reduceMotion) {
        _handoff.value = 1;
      } else {
        _handoff.animateWith(_handoffSpringTo(1));
      }
    }
  }

  void _collapseActivity() {
    if (_reduceMotion) {
      _handoff.value = 0;
    } else {
      _handoff.animateWith(_handoffSpringTo(0));
    }
  }

  SpringSimulation _handoffSpringTo(double end) {
    const spring = SpringDescription(mass: 1, stiffness: 320, damping: 24);
    return SpringSimulation(spring, _handoff.value, end, 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = _reduceMotion;
    final t = _handoff.value;
    final walletGone = t > 0.999;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ── RESTING STATE 1: the wallet composition ──────────────────
            IgnorePointer(
              ignoring: walletGone,
              child: Transform.translate(
                offset: Offset(0, -180 * t),
                child: Opacity(
                  opacity: 1 - t,
                  child: AzPullToRefresh(
                    color: colors.accent,
                    backgroundColor: colors.card,
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      padding: AzSpace.navClearance,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AzSpace.sm),

                          // Block 0 — header, arrives from the left.
                          _stage(0, const _GreetingHeader(), reduceMotion),

                          const SizedBox(height: AzSpace.lg),

                          // Block 1 — the typewriter greeting (§2).
                          _stage(
                              1, const AzTypewriterHeading(), reduceMotion),

                          const SizedBox(height: AzSpace.xl),

                          // Block 2 — the balance hero + pull-reveal Visa
                          // deck (§3-6). The balance card visual is
                          // unchanged; what changed is everything AROUND it.
                          _stage(
                            2,
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AzSpace.lg),
                              child: _DeckHost(key: _deckKey),
                            ),
                            reduceMotion,
                          ),

                          const SizedBox(height: AzSpace.xxl),

                          // Block 3 — Save / P2P / Susu modules (§9).
                          _stage(
                              3, const WalletModulesRow(), reduceMotion),

                          const SizedBox(height: AzSpace.xxl),

                          // Block 4 — the Recent Activity doorway (§10).
                          // No transaction rows live on the resting Home.
                          _stage(
                            4,
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: _onDoorwayDragStart,
                              onVerticalDragUpdate: _onDoorwayDragUpdate,
                              onVerticalDragEnd: _onDoorwayDragEnd,
                              child: const RecentActivityDoorway(),
                            ),
                            reduceMotion,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── RESTING STATE 2: the activity surface (§11-13) ────────────
            IgnorePointer(
              ignoring: !walletGone,
              child: Transform.translate(
                offset: Offset(0, 240 * (1 - t)),
                child: Opacity(
                  opacity: t,
                  child: HomeActivitySurface(
                    onClose: _collapseActivity,
                    active: walletGone,
                    onTopPullUpdate: _onActivityPullUpdate,
                    onTopPullEnd: _onActivityPullEnd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hosts the pull-reveal deck + the PIN-gated card details flow. The deck is
/// the gesture surface; this host owns what "revealed" means downstream:
/// the gate (§6) and the details panel that only mounts after a successful
/// verification.
class _DeckHost extends ConsumerStatefulWidget {
  const _DeckHost({super.key});

  @override
  ConsumerState<_DeckHost> createState() => _DeckHostState();
}

class _DeckHostState extends ConsumerState<_DeckHost> {
  bool _detailsUnlocked = false;

  /// The inner deck handle: the PIN-gate flow and the visibility re-lock
  /// both collapse the deck PROGRAMMATICALLY (audit §6/§7).
  final GlobalKey<PullRevealCardDeckState> _deckKey =
      GlobalKey<PullRevealCardDeckState>();

  static const double _cardHeight = 180;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // AUDIT §7 — MainWrapper keeps pages mounted, so an unlock can never be
    // treated as indefinitely valid. The INSTANT Home stops being the
    // shell's active tab, sensitive card details re-lock and the deck
    // collapses to the balance-card resting state.
    ref.listen(homeShellActiveProvider, (prev, next) {
      if (!next) _relockNow();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PullRevealCardDeck(
          key: _deckKey,
          cardHeight: _cardHeight,
          topCard: const TapHintOverlay(
            hintKey: 'has_seen_flippable_card_hint',
            child: FlippableBalanceCard(),
          ),
          bottomCard: const AzmVisaCard(),
          onRevealChanged: _onRevealChanged,
        ),
        // §6: sensitive card content appears ONLY after the gate passes.
        if (_detailsUnlocked)
          Padding(
            padding: const EdgeInsets.only(top: AzSpace.md),
            child: Container(
              padding: const EdgeInsets.all(AzSpace.lg),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: AzmCardDetailsPanel(
                programme: ref.read(azmCardProgrammeProvider),
              ),
            ),
          ),
      ],
    );
  }

  /// The single re-lock path: clears the unlock AND collapses the deck
  /// back to the balance-card resting state.
  void _relockNow() {
    if (!mounted) return;
    if (_detailsUnlocked) {
      setState(() => _detailsUnlocked = false);
    }
    _deckKey.currentState?.collapse();
  }

  Future<void> _onRevealChanged(bool revealed) async {
    if (!revealed) {
      // Pulled back / programmatic collapse: lock again next time.
      if (_detailsUnlocked) {
        setState(() => _detailsUnlocked = false);
      }
      return;
    }
    // §6: the pull committed — gate BEFORE exposing anything sensitive.
    final verified = await showCardPinGate(context);
    if (!mounted) return;
    if (verified) {
      setState(() => _detailsUnlocked = true);
    } else {
      // AUDIT §6 — gate cancelled/failed: the deck MUST collapse back to
      // the balance-card resting state, not merely clear a flag while the
      // revealed card lingers.
      setState(() => _detailsUnlocked = false);
      _deckKey.currentState?.collapse();
    }
  }
}

/// The header: avatar (profile), rewards, notification bell, balance-visibility
/// toggle. Kept from NEW-D — Home's identity row is not part of this task's
/// information-hierarchy change.
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final isVisible = ref.watch(balanceVisibleProvider);
    final reduceMotion = !AzMotion.of(context).travel;
    final username = user?.username ?? '';
    final initials = _initials(username);

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
              border: Border.all(
                  color: colors.success.withValues(alpha: 0.2), width: 0.5),
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
                    duration: reduceMotion ? Duration.zero : 250.ms,
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: child.key == const ValueKey(true)
                          ? Tween(begin: 0.5, end: 1.0).animate(anim)
                          : Tween(begin: 1.0, end: 0.5).animate(anim),
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: Icon(
                      isVisible
                          ? HugeIconsStroke.viewOff
                          : HugeIconsStroke.view,
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
