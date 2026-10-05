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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
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
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/az_refresh_reward.dart';
import 'package:azaman/providers/home_shell_active_provider.dart';
import 'package:azaman/widgets/home/pull_reveal_card_deck.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';
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

  // EXPERIENCE PASS §6/§7 — the scroll-driven handoff and the deck peek.
  // The Home page's own bottom overscroll feeds the SAME handoff physics
  // the doorway drag used (the drag surface is gone — the doorway stays
  // tappable as the explicit fallback). When the handoff commits, the
  // reminder deck parks in a small peek band above the activity surface so
  // the user can always tell there is still a layer above Activity.
  static const double _peekBandHeight = 96;
  double _peekPx = 0;
  bool _peekSet = false;
  bool _scrollHandoffActive = false;
  final GlobalKey _reminderDeckKey = GlobalKey();

  /// Card deck state (§4-6): whether the pull committed and whether the
  /// PIN gate has passed for this session.
  final GlobalKey<_DeckHostState> _deckKey = GlobalKey<_DeckHostState>();

  // UX-CORRECTION §6: the Recent Activity doorway sits LOW in the resting
  // composition — slightly above the bottom navigation — instead of
  // mid-content with an arbitrary gap. The gap between the wallet
  // modules and the doorway is MEASURED after the entrance choreography
  // settles (transforms corrupt localToGlobal mid-entrance), so the
  // doorway's bottom edge lands at the bottom of the first viewport on
  // any phone size while scrolling and small screens keep working (the
  // gap floors at AzSpace.xxl, never goes negative, and never exceeds a
  // cap — a spacer that grew unbounded would be the same fake-SizedBox
  // mistake the contract forbids).
  final GlobalKey _walletModulesKey = GlobalKey();
  final GlobalKey _doorwayKey = GlobalKey();
  double _doorwayGap = AzSpace.xxxl;
  bool _doorwayGapSettled = false;
  Timer? _doorwayGapTimer;

  @override
  void initState() {
    super.initState();
    _handoff.addListener(() {
      if (mounted) setState(() {});
      // The handoff fully collapsed: the parked peek is meaningless at
      // rest. Re-measure on the next session (the deck may have changed).
      if (_handoff.value <= 0.001) _peekSet = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeSummaryProvider.notifier).primeIfNeeded();
    });
    _scheduleDoorwayGapMeasurement();
  }

  /// Re-measure when the available geometry changes (rotation, font
  /// scale) — but only after the entrance has settled once.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doorwayGapSettled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureDoorwayGap());
    }
  }

  void _scheduleDoorwayGapMeasurement() {
    // MotionTokens.staggerDelay(4) + standard travel stays well under a
    // second; 1200ms lets the last block's entrance settle on any device.
    // A cancelable Timer, NOT Future.delayed: the measurement belongs to
    // this State's lifetime, and a bare delayed future would keep a
    // timer pending after the widget is disposed (leaking the wait into
    // whoever runs next — exactly what the test invariants flag).
    _doorwayGapTimer?.cancel();
    _doorwayGapTimer = Timer(const Duration(milliseconds: 1200), () {
      _doorwayGapTimer = null;
      if (mounted) _measureDoorwayGap();
    });
  }

  void _measureDoorwayGap() {
    final modulesCtx = _walletModulesKey.currentContext;
    final doorwayCtx = _doorwayKey.currentContext;
    if (modulesCtx == null || doorwayCtx == null) return;
    final modulesBox = modulesCtx.findRenderObject();
    final doorwayBox = doorwayCtx.findRenderObject();
    if (modulesBox is! RenderBox || doorwayBox is! RenderBox) return;
    final scrollable = Scrollable.maybeOf(modulesCtx);
    if (scrollable == null) return;
    final scrollBox = scrollable.context.findRenderObject();
    if (scrollBox is! RenderBox || !scrollBox.attached) return;

    // Unscrolled layout position: global y shifts with the scroll offset,
    // so add it back. The scrollable's own origin gives a stable frame.
    final scrollOrigin = scrollBox.localToGlobal(Offset.zero).dy;
    final pixels = scrollable.position.hasContentDimensions
        ? scrollable.position.pixels
        : 0.0;
    final modulesBottom = modulesBox.localToGlobal(Offset.zero).dy +
        pixels -
        scrollOrigin +
        modulesBox.size.height;
    // The first-viewport budget for the wallet column: the scrollable's
    // own height minus the nav clearance it pads its content with.
    final firstViewport =
        scrollBox.size.height - AzSpace.navClearanceHeight;
    final doorwayHeight = doorwayBox.size.height;
    // §4 — the reminder deck sits between the spacer and the doorway
    // (deck + AzSpace.md gap). Its height must leave the first viewport
    // WITH the deck in it: measuring only the doorway pushed the doorway
    // below the fold by the deck's height and left a dead band above the
    // deck. When the deck renders no signal it is a zero-height shrink,
    // and this term vanishes — the empty deck costs no space at all.
    final deckCtx = _reminderDeckKey.currentContext;
    double deckHeight = 0;
    if (deckCtx != null) {
      final deckBox = deckCtx.findRenderObject();
      if (deckBox is RenderBox && deckBox.attached) {
        deckHeight = deckBox.size.height;
      }
    }
    // No UPPER cap: the target is bounded by construction — it lands the
    // doorway's bottom at the first-viewport bottom line. A gap larger
    // than 160 only ever means the wallet column itself is short (tall
    // screen), where "low in the composition" IS the requested placement.
    // The floor keeps small screens from a negative spacer; if the
    // modules already overflow the first viewport the doorway simply
    // follows the content flow (mid-scroll), which scrolling handles.
    //
    // Deliberate sm overshoot below the fold line: the content stays a
    // few pixels TALLER than the viewport. If it fit exactly,
    // maxScrollExtent would be 0, the page could never scroll off the
    // bottom, and the mid-handoff reversal (scroll up mid-overscroll
    // releases the handoff — §6) would have no scroll to win, silently
    // turning every release past threshold into a commit.
    final target = math.max(AzSpace.xxl,
        firstViewport - modulesBottom - deckHeight - AzSpace.md - doorwayHeight + AzSpace.sm);
    _doorwayGapSettled = true;
    if ((target - _doorwayGap).abs() > 0.5) {
      setState(() => _doorwayGap = target);
    }
  }

  @override
  void dispose() {
    _doorwayGapTimer?.cancel();
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

  // ── ACTIVITY HANDOFF (§11, EXPERIENCE PASS §6) ─────────────────────────
  //
  // The doorway no longer owns a drag gesture. The Home page's OWN
  // vertical scroll drives the forward handoff: normal scrolling, the
  // deck/doorway come into view, and continued downward page scroll at
  // the bottom feeds the SAME resisted handoff physics. The user's finger
  // never needs to be over the doorway text. The doorway remains tappable
  // as the explicit navigation/accessibility fallback.

  /// The reminder deck's bottom edge projected to where it will sit after
  /// the Home scroll reaches its bottom — the peek's parking target.
  /// Returns null when the deck renders no signal (nothing to peek).
  double? _projectedDeckBottom() {
    final ctx = _reminderDeckKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || box.size.height <= 0) {
      return null;
    }
    final scrollable = Scrollable.maybeOf(ctx);
    var bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
    if (scrollable != null && scrollable.position.hasContentDimensions) {
      final pos = scrollable.position;
      bottom += pos.maxScrollExtent - pos.pixels;
    }
    return bottom;
  }

  /// Measure the deck peek for this handoff session. Called while the
  /// composition is still at rest (t == 0) so transforms cannot corrupt
  /// the measurement — the same discipline as _measureDoorwayGap.
  void _preparePeek() {
    if (_peekSet) return;
    final projected = _projectedDeckBottom();
    _peekPx = projected == null ? 0.0 : math.max(0.0, projected - _peekBandHeight);
    _peekSet = true;
  }

  bool _onHomeScrollNotification(ScrollNotification n) {
    // Committed: the activity surface owns all gestures now.
    if (_handoff.value >= 1.0) return false;
    final m = n.metrics;
    final atBottom = m.pixels >= m.maxScrollExtent - 0.5;
    // EXPERIENCE PASS §6: only an ACTIVE drag feeds the handoff. A fling
    // whose momentum overshoots the end (ballistic overscroll, no
    // dragDetails) springs back — the commit must be a deliberate, held
    // continuation of the page scroll, never an accident of momentum.
    if (n is OverscrollNotification &&
        atBottom &&
        n.overscroll > 0 &&
        n.dragDetails != null) {
      // Continued downward page scroll at the end of the Home content:
      // the one scroll case the list cannot use, and exactly the handoff.
      if (_handoffDragPx == 0) _preparePeek();
      _scrollHandoffActive = true;
      _handoffDragPx += n.overscroll;
      final progress = ActivityHandoffPhysics.progressFor(_handoffDragPx);
      _handoff.value = ActivityHandoffPhysics.revealFor(progress);
    } else if (_scrollHandoffActive && !atBottom &&
        n is ScrollUpdateNotification) {
      // The user reversed before the settle: the Home scroll wins, the
      // handoff releases cleanly. No fight between scroll and handoff.
      _releaseScrollHandoff();
    } else if (n is ScrollEndNotification) {
      _settleScrollHandoff();
    }
    return false;
  }

  void _releaseScrollHandoff() {
    if (!_scrollHandoffActive) return;
    _scrollHandoffActive = false;
    _handoffDragPx = 0;
    if (_reduceMotion) {
      _handoff.value = 0;
    } else {
      _handoff.animateWith(_handoffSpringTo(0));
    }
  }

  void _settleScrollHandoff() {
    if (!_scrollHandoffActive) return;
    _scrollHandoffActive = false;
    final progress = ActivityHandoffPhysics.progressFor(_handoffDragPx);
    _handoffDragPx = 0;
    if (ActivityHandoffPhysics.commits(progress)) {
      // Threshold crossed: the activity surface snaps into focus and the
      // deck parks in its peek band.
      _commitActivityHandoff();
    } else {
      if (_reduceMotion) {
        _handoff.value = 0;
      } else {
        _handoff.animateWith(_handoffSpringTo(0));
      }
    }
  }

  void _commitActivityHandoff() {
    if (_handoffHapticArmed) {
      AzamanHaptics.threshold();
      _handoffHapticArmed = false;
    }
    if (_reduceMotion) {
      _handoff.value = 1;
    } else {
      _handoff.animateWith(_handoffSpringTo(1));
    }
  }

  /// Correction A — ONE Recent Activity experience: tapping the doorway
  /// enters the SAME second resting state as the scroll handoff. Same
  /// threshold haptic, same spring snap, same surface — never a route push.
  /// The composition is brought to its bottom first so the deck parks in
  /// the peek band from the same resting geometry the scroll path uses.
  void _enterActivity() {
    if (_handoff.value >= 1) return;
    _preparePeek();
    final ctx = _doorwayKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 1.0,
        duration:
            _reduceMotion ? Duration.zero : MotionTokens.emphasized,
      );
    }
    _commitActivityHandoff();
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

  /// §4 — the deck's signals arrive asynchronously (susu list fetch,
  /// marketplace resume memory). A deck that materialises after the
  /// doorway gap settled would push the doorway below the fold again.
  /// Each of these listens re-runs the measurement AFTER the deck has
  /// laid out at its new height (post-frame, so the new geometry exists
  /// to measure). The local swipe-away of the LAST card is the one deck
  /// size change no provider reports; the next provider change or
  /// orientation change re-measures it, and the transient error is one
  /// card-height, never a fold break.
  void _scheduleDoorwayGapRecheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureDoorwayGap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = _reduceMotion;
    final t = _handoff.value;
    final walletGone = t > 0.999;
    // §7: the deck peek band — only meaningful mid-handoff or committed.
    final peekBand = (_peekSet && _peekPx > 0) ? _peekBandHeight : 0.0;

    ref.listen(susuListProvider, (_, _) => _scheduleDoorwayGapRecheck());
    ref.listen(marketplaceResumeProvider, (_, _) => _scheduleDoorwayGapRecheck());
    ref.listen(marketplaceRelevanceProvider, (_, _) => _scheduleDoorwayGapRecheck());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ── RESTING STATE 1: the wallet composition ──────────────────
            // EXPERIENCE PASS §6/§7: the wallet no longer fades out. It
            // slides UP under a measured clip that opens from full height
            // down to the peek band, so the reminder deck can park above
            // the activity surface as visible context ("there is still a
            // layer above Activity"). At rest (t == 0) the clip is the
            // full height — zero cost, no visual change.
            IgnorePointer(
              ignoring: walletGone,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fullH = constraints.maxHeight;
                  final clipH = fullH - (fullH - peekBand) * t;
                  return ClipRect(
                    clipper: _TopBandClipper(height: clipH),
                    child: Transform.translate(
                      offset: Offset(0, -_peekPx * t),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onHomeScrollNotification,
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
                                _stage(
                                    0, const _GreetingHeader(), reduceMotion),

                                const SizedBox(height: AzSpace.lg),

                                // Block 1 — the typewriter greeting (§2).
                                _stage(1, const AzTypewriterHeading(),
                                    reduceMotion),

                                const SizedBox(height: AzSpace.xl),

                                // Block 2 — the balance hero + pull-reveal
                                // Visa deck (§3-6). The balance card visual
                                // is unchanged; what changed is everything
                                // AROUND it.
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
                                  3,
                                  KeyedSubtree(
                                    key: _walletModulesKey,
                                    child: const WalletModulesRow(),
                                  ),
                                  reduceMotion,
                                ),

                                // UX-CORRECTION §6: measured, bounded spacer
                                // that lands the doorway at the bottom of
                                // the first viewport (see
                                // _measureDoorwayGap). Never a hard-coded
                                // giant SizedBox.
                                SizedBox(height: _doorwayGap),

                                // EXPERIENCE PASS §4/§5 — the reminder deck:
                                // real susu + marketplace signals, shuffled
                                // by swipe. Renders nothing when no signal
                                // exists. The key lets the scroll handoff
                                // measure the deck's peek geometry.
                                _stage(
                                  4,
                                  KeyedSubtree(
                                    key: _reminderDeckKey,
                                    child: const HomeReminderDeck(),
                                  ),
                                  reduceMotion,
                                ),

                                const SizedBox(height: AzSpace.md),

                                // Block 4 — the Recent Activity doorway
                                // (§10). No transaction rows live on the
                                // resting Home, and (§6) the doorway is no
                                // longer the drag surface — the Home page's
                                // own bottom overscroll drives the handoff.
                                // The doorway stays tappable as the
                                // explicit fallback.
                                _stage(
                                  5,
                                  KeyedSubtree(
                                    key: _doorwayKey,
                                    child: RecentActivityDoorway(
                                      onOpen: _enterActivity,
                                    ),
                                  ),
                                  reduceMotion,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── RESTING STATE 2: the activity surface (§11-13) ────────────
            // §7: the surface rises from below AND parks below the peek
            // band, leaving the deck visible above it.
            IgnorePointer(
              ignoring: !walletGone,
              child: Transform.translate(
                offset: Offset(0, (240 + peekBand) * (1 - t)),
                child: Opacity(
                  opacity: t,
                  child: Padding(
                    padding: EdgeInsets.only(top: peekBand),
                    child: HomeActivitySurface(
                      onClose: _collapseActivity,
                      active: walletGone,
                      onTopPullUpdate: _onActivityPullUpdate,
                      onTopPullEnd: _onActivityPullEnd,
                    ),
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
        // EXPERIENCE PASS §10 — initials only on Home, for now. A clean
        // circular surface: no photo, no thick gradient ring, no
        // double-border — at most a subtle 1px separation so the disc
        // reads against any background. Profile-picture support stays
        // everywhere else; this is a Home presentation decision.
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.card,
            border: Border.all(
              color: colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
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

/// EXPERIENCE PASS §6/§7 — clips the wallet composition to its top [height]
/// so the handoff slides it under the screen edge instead of fading it out.
/// At rest the height is the full constraint height (no visual effect).
class _TopBandClipper extends CustomClipper<Rect> {
  const _TopBandClipper({required this.height});

  final double height;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, height);

  @override
  bool shouldReclip(_TopBandClipper oldClipper) => oldClipper.height != height;
}
