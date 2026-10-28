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
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/quiet_depth.dart';
import 'package:azaman/widgets/home/home_persistent_header.dart';
import 'package:azaman/widgets/home/home_balance_card.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/az_refresh_reward.dart';
import 'package:azaman/providers/home_shell_active_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/home/visa_transfer_seam_control.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

/// [onOpenSettings] — 2026-10-12 Home refresh: the profile button in the
/// header opens the shell's EXISTING settings end drawer. The shell owns the
/// Scaffold (lib/main.dart), so it injects the explicit openEndDrawer
/// callback here instead of Home reaching for a global context shortcut or
/// pushing a separate settings route. Test hosts without a drawer pass a
/// recording callback (or none — a null callback renders the button inert,
/// never throws).
class AzamanHomePage extends ConsumerStatefulWidget {
  const AzamanHomePage({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

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

  // EXPERIENCE PASS §6/§7 — the scroll-driven handoff and the deck peek.
  // The Home page's own bottom overscroll feeds the SAME handoff physics
  // the doorway drag used (the drag surface is gone — the doorway stays
  // tappable as the explicit fallback). When the handoff commits, the
  // reminder deck parks in a small peek band above the activity surface so
  // the user can always tell there is still a layer above Activity.
  // PASS A5 — the Activity resting geometry lives structurally in
  // ActivityRestGeometry (peek band + heading inset); Home only owns
  // the measured deck parking offset inside that band.
  double _peekPx = 0;
  bool _peekSet = false;

  // WORKSTREAM A — the pinned header's translucency, driven directly by
  // the Home scroll offset (0 = transparent at rest, 1 = fully frosted).
  // A ValueNotifier, not an Animation: the scroll is the animation.
  final ValueNotifier<double> _headerTint = ValueNotifier<double>(0);

  // PASS A3 — how deep the CURRENT drag sits in the armed plateau
  // (forward or reverse). Feeds the heading's lock-in cue; zero while
  // no drag is live and during snaps.
  double _handoffArmedDepth = 0;
  bool _handoffArmedHapticFired = false;

  // UX-CORRECTION §6 + PASS B5 — the Recent Activity doorway sits LOW in
  // the resting composition, slightly above the bottom navigation, never
  // mid-content. The measured leftover is split between the reminder
  // deck's §4 FILL (it absorbs the band above the doorway first, capped
  // at its own bandCap) and the SPACER between the deck and the doorway:
  // measured once after the entrance choreography settles (transforms
  // corrupt localToGlobal mid-entrance), floored at AzSpace.xxl, capped,
  // never negative.
  static const double _doorwayGapMin = AzSpace.xxl;
  static const double _doorwayGapMax = 344.0;
  double _doorwayGap = _doorwayGapMin;
  bool _doorwayGapSettled = false;
  Timer? _doorwayGapTimer;

  /// §4 FILL (owner direction, 2026-10-05): the reminder deck's grown
  /// height BEYOND its natural band. The measured leftover above the
  /// doorway goes to the deck first (capped at its bandCap), the spacer
  /// keeps its breathing floor; shrinking reverses the order. Zero
  /// until the post-entrance measurement — the deck renders natural.
  double _deckFill = 0;

  /// TASK-B — the wallet band's height: the VISIBLE fold of the resting
  /// Home. The scrollable's viewport box is NOT a stable fold reference:
  /// under loose constraints the SingleChildScrollView sizes its viewport
  /// to its CONTENT, so every fill increment grew the "viewport" in
  /// lockstep and the measured delta never converged (the deck crept
  /// +8px per pass — the delayed visible resize). The band height, read
  /// from the LayoutBuilder each build, is the true first-viewport fold
  /// regardless of how the scrollable's constraints arrive.
  double? _visibleBandHeight;

  /// Bounded confirmation passes after a gap change: geometry re-read
  /// from the settled layout converges within a few frames. The budget
  /// covers the entrance window — content that lands during the entrance
  /// is absorbed while the choreography still masks the reflow, so the
  /// composition is FINAL by the time the entrance settles.
  int _doorwayGapPasses = 0;

  /// TASK-B: how many convergence passes may run. Each pass is one frame
  /// after a delta; normal layouts converge in 1-2, the budget absorbs
  /// late provider landings inside the entrance window.
  static const int _doorwayGapPassBudget = 6;
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

  @override
  void initState() {
    super.initState();
    _handoff.addListener(() {
      if (mounted) setState(() {});
      // The handoff fully collapsed: the parked peek is meaningless at
      // rest. Re-measure on the next session (the deck may have changed).
      if (_handoff.value <= 0.001) _peekSet = false;
    });
    // §7 — when a commit SETTLES, re-anchor the parked peek against the
    // live layout: content above the deck can shift a few px after the
    // session armed (a late provider landing, the fill's confirmation
    // passes), and the parked bottom must land in the peek band
    // regardless of when exactly the layout settled.
    _handoff.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _peekSet &&
          _handoff.value >= 0.999) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _correctPeek();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(homeSummaryProvider.notifier).primeIfNeeded();
    });
    _scheduleDoorwayGapMeasurement();
  }

  /// Re-measure when the available geometry changes (rotation, font
  /// scale) — but only after the gap has settled once.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doorwayGapSettled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureDoorwayGap();
      });
    }
  }

  @override
  void dispose() {
    // The doorway-gap measurement Timer belongs to this State's lifetime:
    // a test (or tab switch) that unmounts Home before the 1200ms
    // entrance settle would otherwise leave a pending timer behind.
    _doorwayGapTimer?.cancel();
    _doorwayGapTimer = null;
    _headerTint.dispose();
    _handoff.dispose();
    super.dispose();
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  void _scheduleDoorwayGapMeasurement() {
    // TASK-B — stable first-frame geometry. The layout probes are
    // UNTRANSFORMED (_LayoutMarker slots sit outside the entrance
    // transforms), so the content geometry is authoritative from the
    // very first settled layout. The composition is therefore measured
    // DURING the entrance (the choreography masks the reflow) instead
    // of resizing visibly at a fixed 1200ms mark.
    //
    // One cancelable verification Timer remains as a safety net: if a
    // provider lands after the convergence passes ran out, the
    // entrance-end pass corrects the composition once. When the
    // first-frame measurement is right — the normal case — this pass
    // finds ZERO delta and changes nothing (idempotent by design, see
    // _measureDoorwayGap). The Timer belongs to this State's lifetime
    // and is cancelled in dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureDoorwayGap();
      _doorwayGapTimer?.cancel();
      _doorwayGapTimer = Timer(const Duration(milliseconds: 1200), () {
        _doorwayGapTimer = null;
        if (mounted) _measureDoorwayGap();
      });
    });
  }

  void _measureDoorwayGap() {
    final doorwayCtx = _doorwayKey.currentContext;
    if (doorwayCtx == null) return;
    final scrollable = Scrollable.maybeOf(doorwayCtx);
    if (scrollable == null) return;
    final scrollBox = scrollable.context.findRenderObject();
    final doorwayBox = doorwayCtx.findRenderObject();
    if (scrollBox is! RenderBox ||
        doorwayBox is! RenderBox ||
        !scrollBox.attached) {
      return;
    }

    // Unscrolled layout position: global y shifts with the scroll
    // offset, so add it back. The scrollable's own origin is the stable
    // frame (transform corruption is why the probe runs post-entrance).
    final scrollOrigin = scrollBox.localToGlobal(Offset.zero).dy;
    final pixels = scrollable.position.hasContentDimensions
        ? scrollable.position.pixels
        : 0.0;
    final doorwayBottomUnscrolled =
        doorwayBox.localToGlobal(Offset.zero).dy +
        pixels -
        scrollOrigin +
        doorwayBox.size.height;

    // TASK-B — the fold is the VISIBLE band (the wallet surface region),
    // never the scrollable's viewport box: under loose constraints the
    // SingleChildScrollView sizes its viewport to the CONTENT, so a
    // content-sized "viewport" grows in lockstep with the measured fill
    // and the fixed point degenerates into +8px-per-pass creep. The
    // band height is constraint-stable: the composition converges and
    // stays converged. The nav-clearance padding below the doorway is
    // part of the scroll content and counts towards the fold.
    final foldHeight = _visibleBandHeight ?? scrollBox.size.height;
    final trueExtent =
        doorwayBottomUnscrolled + AzSpace.navClearance.bottom - foldHeight;

    // PASS B5 — the deck is a FIXED compact strip; the measured spacer is
    // the deck→doorway gap. The content must end a deliberate few pixels
    // below the fold: if it fit exactly, maxScrollExtent would be 0, the
    // page could never scroll off the bottom, and the mid-handoff
    // reversal (scroll up mid-overscroll releases the handoff — §6)
    // would have no scroll to win, silently turning every release past
    // threshold into a commit.
    const desiredOvershoot = AzSpace.sm;
    final delta = desiredOvershoot - trueExtent;

    // §4 FILL — split the measured leftover between the deck and the
    // spacer. Growth: the deck absorbs first (up to its bandCap), then
    // the spacer grows. Shrink: the spacer gives first (down to its
    // floor), then the deck releases its fill. Idempotent — the next
    // bounded pass re-reads the settled geometry and re-derives the
    // same pair.
    var rem = delta;
    var newGap = _doorwayGap;
    var newFill = _deckFill;
    if (rem > 0) {
      final byDeck = math.min(
        rem,
        HomeReminderDeck.bandCap - HomeReminderDeck.naturalBand - newFill,
      );
      newFill += byDeck;
      rem -= byDeck;
      newGap = (newGap + rem).clamp(_doorwayGapMin, _doorwayGapMax);
    } else if (rem < 0) {
      final byGap = math.min(-rem, newGap - _doorwayGapMin);
      newGap -= byGap;
      rem += byGap;
      if (rem < 0) newFill = math.max(0.0, newFill + rem);
    }
    _doorwayGapSettled = true;
    // TASK-B — apply tolerance: layout rounds to whole pixels, so the
    // measured residual drifts by fractions of a pixel between passes.
    // Re-applying sub-tolerance deltas would round to a 1px visible
    // reflow AFTER the entrance settled — exactly the delayed resize
    // this pass must never cause. Real imbalances (late provider
    // landings, rotation, font-scale changes) are orders of magnitude
    // larger and still apply.
    const applyTolerance = 2.0;
    if ((newGap - _doorwayGap).abs() > applyTolerance ||
        (newFill - _deckFill).abs() > applyTolerance) {
      setState(() {
        _doorwayGap = newGap;
        _deckFill = newFill;
      });
      // Bounded confirmation passes after the relayout: geometry re-read
      // from the FINAL layout converges even if the first pass caught the
      // content mid-settle. The budget covers the entrance window so any
      // reflow is absorbed while the choreography still runs — the
      // composition must already be final when the entrance settles.
      if (_doorwayGapPasses < _doorwayGapPassBudget) {
        _doorwayGapPasses++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measureDoorwayGap();
        });
      }
    } else {
      _doorwayGapPasses = 0;
    }
  }

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

  void _preparePeek() {
    if (_peekSet) return;
    final projected = _projectedDeckBottom();
    _peekPx = projected == null
        ? 0.0
        : math.max(0.0, projected - ActivityRestGeometry.peekBand);
    _peekSet = true;
  }

  /// Re-derives the parked peek from the LIVE committed layout: the
  /// deck's on-screen bottom already carries our own translate, so
  /// adding it back yields the translate-free at-rest bottom, and the
  /// correction lands the parked bottom exactly on the peek band. In
  /// production this is almost always a no-op (the armed value already
  /// matches); it exists so a late-landing layout shift cannot strand
  /// the park a few pixels off the band.
  void _correctPeek() {
    if (!_peekSet || _handoff.value < 0.999) return;
    final ctx = _reminderDeckKey.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached) return;
    var bottom = box.localToGlobal(Offset.zero).dy + box.size.height + _peekPx;
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable?.position.hasContentDimensions ?? false) {
      final pos = scrollable!.position;
      bottom += pos.maxScrollExtent - pos.pixels;
    }
    final want = math.max(0.0, bottom - ActivityRestGeometry.peekBand);
    if ((want - _peekPx).abs() > 0.5) setState(() => _peekPx = want);
  }

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
    final entered = child.animate().fadeIn(
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

  bool _onHomeScrollNotification(ScrollNotification n) {
    // WORKSTREAM A — the pinned header's translucency tracks the REAL
    // scroll offset directly (transparent at rest, frosted as content
    // passes under the band). Clamped; no timers, no idle animation.
    if (n is ScrollUpdateNotification) {
      _headerTint.value = (n.metrics.pixels / 48).clamp(0.0, 1.0);
    }
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
      _updateArmedDepth(progress);
    } else if (_scrollHandoffActive &&
        !atBottom &&
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
    _handoffArmedDepth = 0;
    _handoffArmedHapticFired = false;
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
    _handoffArmedDepth = 0;
    if (ActivityHandoffPhysics.commits(progress)) {
      // Released inside the armed plateau: the activity surface SNAPS
      // into focus (pass A2 — a strong, controlled settle) and the deck
      // parks in its peek band.
      _commitActivityHandoff();
    } else {
      // Released before the armed point: the tensioned sheet springs
      // back — no commit, no accidental entry.
      if (_reduceMotion) {
        _handoff.value = 0;
      } else {
        _handoff.animateWith(_handoffSpringTo(0));
      }
    }
  }

  /// PASS A3 — the armed plateau is where the heading's lock-in cue and
  /// the detent haptic live. Purely gesture-driven: depth is a function
  /// of the drag progress, zero the moment no drag is live.
  void _updateArmedDepth(double progress) {
    final depth = ActivityHandoffPhysics.armedFor(progress);
    if (depth > 0 && !_handoffArmedHapticFired) {
      // The detent catch: the pull entered the commit zone. Exactly one
      // threshold haptic per pull — the armed moment, not the release.
      AzamanHaptics.threshold();
      _handoffArmedHapticFired = true;
    }
    _handoffArmedDepth = depth;
  }

  void _commitActivityHandoff() {
    _handoffArmedHapticFired = false;
    if (_reduceMotion) {
      _handoff.value = 1;
    } else {
      _handoff.animateWith(_handoffSnapTo(1));
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
        duration: _reduceMotion ? Duration.zero : MotionTokens.emphasized,
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
    // PASS A8 — the reverse transition is the SAME tensioned grammar:
    // resistance, then the armed plateau with its detent haptic and the
    // heading's lock-in cue, then a deliberate snap back to Home.
    _updateArmedDepth(reverseProgress);
  }

  void _onActivityPullEnd(bool commits) {
    _handoffArmedDepth = 0;
    _handoffArmedHapticFired = false;
    if (commits) {
      // Released past the armed point: a deliberate snap back to Home
      // (pass A8) — the layer is pulled back over the wallet state,
      // which restores the reminder deck, wallet modules, balance card,
      // and the DOWN-arrow Recent Activity doorway.
      _collapseActivity();
    } else {
      // A small reverse pull springs back into the Activity rest.
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
      _handoff.animateWith(_handoffSnapTo(0));
    }
  }

  /// The release-before-armed settle: elastic, forgiving.
  SpringSimulation _handoffSpringTo(double end) {
    const spring = SpringDescription(mass: 1, stiffness: 320, damping: 24);
    return SpringSimulation(spring, _handoff.value, end, 0);
  }

  /// PASS A2/A8 — the COMMIT snap: stiffer and slightly under-damped so
  /// the transition into (or back out of) Activity reads as strong and
  /// controlled — one restrained settle, never a theatrical bounce.
  SpringSimulation _handoffSnapTo(double end) {
    const spring = SpringDescription(mass: 1, stiffness: 480, damping: 40);
    return SpringSimulation(spring, _handoff.value, end, 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = _reduceMotion;
    final t = _handoff.value;
    final walletGone = t > 0.999;
    // §7: the deck peek band — only meaningful mid-handoff or committed.
    final peekBand = (_peekSet && _peekPx > 0)
        ? ActivityRestGeometry.peekBand
        : 0.0;

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
                  _visibleBandHeight = fullH;
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
                            // QUIET DEPTH (Home pilot): the scoped
                            // focus/depth system lives around the Home
                            // content only. Controls opt in individually;
                            // the scope's Listener observes pointer-downs
                            // for the focused-region tap-outside rule and
                            // never competes with real gestures.
                            child: QuietDepthScope(
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // WORKSTREAM A — the header is now a
                                // PINNED band above the scroll view; the
                                // column reserves exactly its height plus
                                // the rhythm it always had (56 + 12 == the
                                // old 8 + 44 + 16, so the typewriter lands
                                // at the same y it always did).
                                const SizedBox(
                                  height: HomePersistentHeader.bandHeight +
                                      AzSpace.md,
                                ),

                                // Block 1 — the typewriter greeting (§2).
                                _stage(
                                  1,
                                  const AzTypewriterHeading(),
                                  reduceMotion,
                                ),

                                // PR #154 measured first pass: 20 → 12
                                // pulls the deck toward the greeting so the
                                // first viewport lands more of the wallet
                                // area above the fold.
                                const SizedBox(height: AzSpace.md),

                                // Block 2 — the balance hero + pull-reveal
                                // Visa deck (§3-6). The balance card visual
                                // is unchanged; what changed is everything
                                // AROUND it.
                                _stage(
                                  2,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AzSpace.lg,
                                    ),
                                    child: _DeckHost(key: _deckKey),
                                  ),
                                  reduceMotion,
                                ),

                                // PR #154 measured first pass: 24 → 16
                                // between the deck and the module row.
                                const SizedBox(height: AzSpace.lg),

                                // Block 3 — Save / P2P / Susu modules (§9).
                                _stage(
                                  3,
                                  KeyedSubtree(
                                    key: _walletModulesKey,
                                    child: const WalletModulesRow(),
                                  ),
                                  reduceMotion,
                                ),

                                // PASS B5 — breathing room above the
                                // reminder deck. The deck's geometry is
                                // FIXED from its first settled render
                                // (no band measurement, no placeholder
                                // growth): a stable strip, never a
                                // hard-coded giant SizedBox.
                                const SizedBox(height: AzSpace.xxl),

                                // PASS §4/§5 + B/D — the reminder deck:
                                // real susu + marketplace signals,
                                // shuffled by swipe, in a FIXED compact
                                // geometry (front card + one next-card
                                // peek + position dots). The dots are
                                // the card-count indicator. Production
                                // Home never fabricates content: with
                                // no real signal the deck renders the
                                // honest placeholder (owner direction —
                                // the slot is never blank), and a demo
                                // build seeds from the demo data. The
                                // height is the measured §4 FILL so the
                                // deck owns the band above the doorway
                                // instead of floating thin in it. The
                                // key lets the scroll handoff measure
                                // the deck's peek geometry. PASS B6:
                                // the deck sits in the SAME horizontal
                                // inset as the balance card — edges
                                // align, no independent magic width.
                                _stage(
                                  4,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AzSpace.lg,
                                    ),
                                    child: KeyedSubtree(
                                      key: _reminderDeckKey,
                                      child: HomeReminderDeck(
                                        height:
                                            HomeReminderDeck.naturalBand +
                                            _deckFill,
                                      ),
                                    ),
                                  ),
                                  reduceMotion,
                                ),

                                // UX-CORRECTION §6 + PASS B5: the
                                // ADAPTIVE measured spacer. The deck is a
                                // fixed strip; this gap is what keeps
                                // the doorway at the bottom of the first
                                // viewport (never mid-content, never a
                                // hard-coded giant SizedBox).
                                SizedBox(height: _doorwayGap),

                                // Block 4 — the Recent Activity doorway
                                // (§10). No transaction rows live on the
                                // resting Home, and (§6) the doorway is no
                                // longer the drag surface — the Home page's
                                // own bottom overscroll drives the handoff.
                                // The doorway stays tappable as the
                                // explicit fallback.
                                //
                                // TASK-B: the measurement key sits on a
                                // _LayoutMarker OUTSIDE the entrance
                                // transform — the marker's render box reports
                                // the doorway's LAYOUT position from the
                                // first frame, immune to the slide-in
                                // transform applied to the visual doorway.
                                _LayoutMarker(
                                  key: _doorwayKey,
                                  child: _stage(
                                    5,
                                    RecentActivityDoorway(
                                      onOpen: _enterActivity,
                                      progress: t,
                                      armed: _handoffArmedDepth,
                                      reduceMotion: reduceMotion,
                                    ),
                                    reduceMotion,
                                  ),
                                ),
                              ],
                              ),
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
            // §7 + PASS A5: the surface rises from below AND parks below
            // the peek band (ActivityRestGeometry), leaving the reminder
            // deck visible above it; the heading then sits a further
            // structural inset into the surface, so the committed state
            // reads as a layer pulled over Home.
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
                      headingProgress: t,
                      armedCue: _handoffArmedDepth,
                      onTopPullUpdate: _onActivityPullUpdate,
                      onTopPullEnd: _onActivityPullEnd,
                    ),
                  ),
                ),
              ),
            ),

            // ── WORKSTREAM A: the pinned, Home-only header ──────────────
            // Topmost child: the band paints over the scrolling content
            // (translucent when scrolled), wins hit-testing for the
            // pull-down reveal inside its 56px, and departs upward with
            // the wallet→activity handoff so the deck peek and the
            // activity surface's own chrome read cleanly.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: HomePersistentHeader(
                onOpenSettings: widget.onOpenSettings,
                handoff: _handoff,
                scrollTint: _headerTint,
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

class _DeckHostState extends ConsumerState<_DeckHost>
    with WidgetsBindingObserver {
  bool _detailsUnlocked = false;

  /// The deck's live pose. The transfer clasp (VisaTransferSeamAnchor) is
  /// mounted only while tucked — an out card's own gestures own the deck
  /// surface, and the pocket mouth (the clasp's home) is only exposed in
  /// the tucked pose.
  WalletDeckState _deckState = WalletDeckState.tucked;

  /// STALE-RESULT GUARD (2026-10-16 follow-up): monotonic attempt counter
  /// for the Visa PIN gate. A gate that is pending when the app is
  /// backgrounded, the deck is tucked/switched or the Home tab loses
  /// focus is invalidated by bumping this counter; when the awaited gate
  /// later resolves, only the CURRENT attempt may unlock the details
  /// panel — a delayed successful PIN can never unlock details for a
  /// deck that has already been re-locked.
  int _pinGeneration = 0;

  /// The inner deck handle: the PIN-gate flow, the tab-change re-lock and
  /// the app-lifecycle re-lock all tuck the deck PROGRAMMATICALLY
  /// (audit §6/§7 + the 2026-10-16 pouch-deck lifecycle audit: MainWrapper
  /// keeps Home mounted, so a tab change alone does NOT cover the app being
  /// backgrounded — this host also observes the app lifecycle and returns
  /// the deck to `tucked` on every inactive/paused/hidden transition).
  final GlobalKey<WalletCardDeckState> _deckKey =
      GlobalKey<WalletCardDeckState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // SECURITY (pouch deck): the tucked pouch is the deck's default privacy
    // state. The moment the app loses focus — notification shade, app
    // switcher, background — the deck goes back in the pocket and any
    // unlocked card details are dropped.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _relockNow();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.resumed:
        break;
    }
  }

  // UX pass (2026-10-27): the physical cards' footprint returns to the
  // ORIGINAL deck geometry, 180px (d63a4d4 — the reactive-surface deck PR;
  // the 2026-10-12 refresh had reduced it to 165). The balance card is the
  // product's primary money surface and the founder wants the larger
  // presentation back: the GHS headline, the USDC-equivalent line and the
  // FX status row each get a fixed reserved region inside the taller frame
  // (see BalanceCardGeometry and balance_card_fx.dart). Both cards'
  // contents were originally designed at this height and are audited here
  // again; if a future change needs a different height, revisit BOTH cards,
  // not just this constant.
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
        VisaTransferSeamAnchor(
          visible: _deckState == WalletDeckState.tucked,
          onTransfer: () => context.push(AzRoutes.cardTransfer),
          child: WalletCardDeck(
            key: _deckKey,
            cardHeight: _cardHeight,
            // WALLET POUCH follow-up: the old TapHintOverlay is REMOVED —
            // its hand animation played invisibly behind the opaque pouch
            // (the deck's exposed headers already teach tap-to-select).
            // No perpetual ambient animation replaces it.
            balanceCard: const HomeBalanceCard(),
            visaCard: const AzmVisaCard(),
            onStateChanged: _onDeckStateChanged,
          ),
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

  /// The single re-lock path: clears the unlock AND returns the deck to
  /// the tucked pouch state.
  void _relockNow() {
    if (!mounted) return;
    // Any in-flight PIN attempt is superseded the moment a re-lock happens.
    _pinGeneration++;
    if (_detailsUnlocked) {
      setState(() => _detailsUnlocked = false);
    }
    _deckKey.currentState?.tuck();
  }

  /// The deck reports every state change; the host owns what each state
  /// means downstream (audit §6).
  Future<void> _onDeckStateChanged(WalletDeckState next) async {
    if (_deckState != next) {
      setState(() => _deckState = next);
    }
    // QUIET DEPTH: the out card is a designated focal surface. While it
    // is out the secondary Home controls recess; when the deck tucks the
    // controls rise and the idle cycle restarts. This rides the REAL
    // deck-state callback — never inferred coordinates or timing.
    final quiet = QuietDepthScope.maybeOf(context);
    if (next == WalletDeckState.tucked) {
      quiet?.exitFocus('wallet-deck');
    } else {
      quiet?.enterFocus('wallet-deck');
    }
    switch (next) {
      case WalletDeckState.tucked:
        // Returned to the pouch (swipe, tap elsewhere, programmatic):
        // a fresh reveal must pass the gate again. Any pending gate is
        // for a deck state that no longer exists — invalidate it.
        _pinGeneration++;
        if (_detailsUnlocked) {
          setState(() => _detailsUnlocked = false);
        }
      case WalletDeckState.balanceOut:
        // The user's own balance card: no gate, but the Visa details
        // panel (if it was ever unlocked) is no longer the active card.
        // A still-pending Visa gate is likewise superseded.
        _pinGeneration++;
        if (_detailsUnlocked) {
          setState(() => _detailsUnlocked = false);
        }
      case WalletDeckState.visaOut:
        // §6: the card programme's sensitive details mount ONLY after the
        // PIN gate passes. The Visa card FACE itself is the demo surface
        // (masked number + SAMPLE disclosure) and carries nothing
        // sensitive.
        if (_detailsUnlocked) return;
        final attempt = _pinGeneration;
        final verified = await showCardPinGate(context);
        if (!mounted) return;
        // The result is only honoured if the attempt is still current AND
        // the deck is still showing the Visa card: a gate that resolves
        // after a re-lock (backgrounding, tab change, tuck, card switch)
        // must never unlock anything.
        if (attempt != _pinGeneration) return;
        if (_deckKey.currentState?.state != WalletDeckState.visaOut) return;
        if (verified) {
          setState(() => _detailsUnlocked = true);
        } else {
          // Gate cancelled/failed: the deck MUST return to the tucked
          // pouch state, not merely clear a flag while the Visa card
          // lingers out.
          _pinGeneration++;
          setState(() => _detailsUnlocked = false);
          _deckKey.currentState?.tuck();
        }
    }
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

/// TASK-B — an untransformed layout marker.
///
/// A pure layout slot: [SizedBox] creates its own render box at the
/// child's LAYOUT position while any entrance transform applied inside
/// the child subtree (the staged slide/fade choreography) stays BELOW
/// it. Measuring via this box therefore reports the doorway's true
/// content-space geometry from the very first frame — the prerequisite
/// for first-frame composition measurement without a delayed visible
/// resize (see _measureDoorwayGap).
class _LayoutMarker extends StatelessWidget {
  const _LayoutMarker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(child: child);
}
