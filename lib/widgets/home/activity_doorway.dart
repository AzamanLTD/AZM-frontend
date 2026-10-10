// =============================================================================
// AZAMAN — RECENT ACTIVITY DOORWAY + SECOND RESTING STATE  (NEW-HOME §10-12)
//
// The resting Home renders NO transaction rows — only the Recent Activity
// heading/doorway. Tap and pull are ONE experience (correction A): the
// doorway enters the SAME second resting state — the in-Home activity
// surface — never /account/activity. The canonical account-activity route
// stays reachable from its own surfaces (profile, etc.), but this doorway
// has exactly one meaning.
//
// The handoff is physical and deliberate (§11): resistance below a
// threshold, a commit that snaps the activity surface into focus while the
// wallet composition moves out of the way, and the same grammar in reverse.
// NOT a giant animated page-scroll gimmick — two clear resting states with
// a controlled handoff.
//
// §12 is a REAL lazy-load boundary: entering the activity state triggers
// the EXISTING transactionHistoryProvider (/finance/transactions, cursor
// pagination) — never the home summary refresh, so opening Activity never
// drags rates/friend-requests/notifications along. Skeletons appear ONLY
// during genuine cold loading, and resting Home never fetches to decorate
// a preview. Pulling down from the top (header drag, or the list's own
// at-top overscroll) is the reverse handoff back to the wallet.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/home/activity_actions.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// Pure, unit-testable handoff physics — the TENSIONED SHEET (pass A1/A2).
///
/// The handoff must not feel like an ordinary scroll. The reveal is a
/// two-phase curve, C1-joined at the ARMED point:
///
///   1. TENSION [0, armed): reveal = revealAtArm · (p/armed)³ — the sheet
///      pushes back hard early (at 15% of the pull the page moves at
///      roughly a tenth of the finger), gives through the middle, and
///      CATCHES at the armed boundary with a slope drop to zero: a detent.
///   2. ARMED PLATEAU [armed, 1]: smoothstep to the full reveal — movement
///      is constrained (slope starts at zero), so the hold reads as "a
///      second resting state is being selected". Further pull only eases
///      the last fraction in; releasing at or beyond the armed point
///      snaps deliberately.
///
/// No timers anywhere: the hold IS the plateau, driven purely by gesture
/// progress. The same grammar runs in reverse (Activity → Home).
class ActivityHandoffPhysics {
  const ActivityHandoffPhysics._();

  /// Drag travel that maps to full handoff progress. Deliberate: reaching
  /// the armed point takes a clearly intentional pull (~143 logical px).
  static const double travelPx = 230;

  /// The ARMED point — releasing at or beyond this progress commits.
  static const double commitThreshold = 0.62;

  /// Reveal fraction reached exactly at the armed boundary.
  static const double revealAtArm = 0.58;

  static double progressFor(double dragPx) {
    if (dragPx <= 0) return 0;
    return (dragPx / travelPx).clamp(0.0, 1.0);
  }

  /// The tensioned reveal (see the class comment for the curve).
  static double revealFor(double progress) {
    final p = progressFor(progress * travelPx);
    if (p < commitThreshold) {
      final k = p / commitThreshold;
      return revealAtArm * k * k * k;
    }
    final q = (p - commitThreshold) / (1 - commitThreshold);
    return revealAtArm + (1 - revealAtArm) * (q * q * (3 - 2 * q));
  }

  /// How deep into the armed plateau the pull is (0 before armed, 1 at
  /// full reveal). Drives the heading's restrained lock-in cue (pass A3).
  static double armedFor(double progress) {
    final p = progressFor(progress * travelPx);
    if (p <= commitThreshold) return 0;
    return ((p - commitThreshold) / (1 - commitThreshold)).clamp(0.0, 1.0);
  }

  /// A tiny, short wobble as the lock-in engages — a PURE function of the
  /// armed depth (never a timer): two diminishing half-swings, ~±0.3° at
  /// entry, decayed to ~0.1° inside the first third of the plateau. It
  /// must read as "Activity is locking into place" — never a
  /// notification shake, never an error, never a bounce.
  static double wobbleFor(double armedDepth) {
    if (armedDepth <= 0 || armedDepth >= 1) return 0;
    final decay = (1 - armedDepth) * (1 - armedDepth);
    return math.sin(armedDepth * math.pi * 3) * decay * 0.007;
  }

  static bool commits(double progress) => progress >= commitThreshold;
}

/// The Activity layer's RESTING geometry (pass A5) — structural, not a
/// per-instance Transform.translate bolt-on. The committed Activity reads
/// as a layer pulled over Home: the reminder deck parks in the peek band
/// at the top of the viewport, a fixed structural offset separates the
/// peek from the heading, so the heading sits clearly lower than a
/// conventional page's top margin, and the content follows it.
class ActivityRestGeometry {
  const ActivityRestGeometry._();

  /// The band the reminder deck parks in above the Activity surface.
  static const double peekBand = 96;

  /// The heading's structural offset below the peek band — the fixed
  /// breath of space that keeps "layer over Home" readable.
  static const double headingInset = 48;
}

/// The resting-state Recent bubble. Its visual state follows the same
/// handoff controller as the wallet/activity composition: neutral when idle,
/// progressively larger while pulled, and silver-green when it becomes the
/// active header. The entire doorway band remains the tap target.
class RecentActivityDoorway extends ConsumerWidget {
  const RecentActivityDoorway({
    super.key,
    required this.onOpen,
    this.progress = 0,
    this.armed = 0,
    this.reduceMotion = false,
  });

  final VoidCallback onOpen;
  final double progress;
  final double armed;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final t = progress.clamp(0.0, 1.0).toDouble();
    final scale = reduceMotion ? 1.0 : 1.0 + 0.14 * t + 0.045 * armed;
    final wobble = reduceMotion ? 0.0 : ActivityHandoffPhysics.wobbleFor(armed);

    return ScaleTap(
      key: const ValueKey('recent_activity_doorway'),
      onTap: () {
        AzamanHaptics.nav();
        onOpen();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.lerp(
                Alignment.centerLeft,
                Alignment.center,
                t,
              )!,
              child: Transform.rotate(
                angle: wobble,
                child: Transform.scale(
                  scale: scale,
                  child: _RecentBubbleFace(
                    colors: colors,
                    progress: t,
                    selected: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentBubbleFace extends StatelessWidget {
  const _RecentBubbleFace({
    required this.colors,
    required this.progress,
    required this.selected,
  });

  final AzamanColors colors;
  final double progress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final active = selected ? 1.0 : progress.clamp(0.0, 1.0).toDouble();
    final idleSurface = colors.softSurface;
    final activeSurface = colors.isDark
        ? const Color(0xFF254B39)
        : const Color(0xFFC9DDCF);
    final idleInk = colors.textTertiary;
    final activeInk = colors.isDark
        ? const Color(0xFFD9EBDD)
        : const Color(0xFF254B39);

    return Semantics(
      button: true,
      label: 'Recent transactions',
      selected: selected,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AzSpace.xl,
          vertical: AzSpace.sm,
        ),
        decoration: BoxDecoration(
          color: Color.lerp(idleSurface, activeSurface, active),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Color.lerp(colors.border, activeSurface, active)!,
            width: 1,
          ),
          boxShadow: active > 0.5
              ? [
                  BoxShadow(
                    color: activeSurface.withValues(alpha: 0.16 * active),
                    blurRadius: 14 * active,
                    spreadRadius: 0.5 * active,
                  ),
                ]
              : null,
        ),
        child: Text(
          'Recent',
          key: selected ? const ValueKey('home-activity-header-title') : null,
          style: AzText.body.copyWith(
            color: Color.lerp(idleInk, activeInk, active),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

/// Home's second resting state. A REAL lazy-load boundary: the surface
/// calls the existing transactionHistoryProvider (/finance/transactions)
/// when it ENTERS (not before) — the summary refresh (rates, friend
/// requests, unread notifications, ...) is NOT the activity data source
/// and resting Home stays lightweight. Skeletons appear ONLY during genuine
/// cold loading with no data, cursor pagination (hasMore/nextCursor) lets
/// the list continue beyond the first page, and each activity carries an
/// explicit typed action.
class HomeActivitySurface extends ConsumerStatefulWidget {
  const HomeActivitySurface({
    super.key,
    required this.onClose,

    /// Whether the handoff COMMITTED — the surface is mounted at rest too
    /// (it fades in during the drag), so `active` is the lazy-load gate:
    /// the fetch fires exactly once, when the user actually ENTERS.
    required this.active,

    /// PASS A3/A4 — the handoff reveal (0..1) driving the heading's
    /// state-driven presentation: the arrow rotates from DOWN (hidden,
    /// uncommitted) to UP (Activity rest) and the heading settles through
    /// the armed cue. The parent owns the value; the heading is a pure
    /// function of it.
    required this.headingProgress,

    /// PASS A3 — how deep into the armed plateau the CURRENT pull is
    /// (0..1). Drives the restrained lock-in cue (slight expansion +
    /// a tiny decaying wobble). Zero during snaps: the cue belongs to
    /// the gesture, never the settle.
    required this.armedCue,

    /// REVERSE handoff (audit §1): accumulated downward pull (logical px)
    /// from the top of the activity surface — from ANY non-scroll region
    /// of the surface (header, empty area, skeleton) and from the list's
    /// own at-top overscroll. The parent maps it onto the handoff
    /// animation; the surface owns the threshold decision.
    required this.onTopPullUpdate,

    /// The reverse pull ended. [commits] is the surface's threshold
    /// verdict: true collapses back to the wallet state, false springs
    /// back to the activity state.
    required this.onTopPullEnd,
  });

  final VoidCallback onClose;
  final bool active;
  final double headingProgress;
  final double armedCue;
  final ValueChanged<double> onTopPullUpdate;
  final void Function(bool commits) onTopPullEnd;

  @override
  ConsumerState<HomeActivitySurface> createState() =>
      _HomeActivitySurfaceState();
}

class _HomeActivitySurfaceState extends ConsumerState<HomeActivitySurface>
    with SingleTickerProviderStateMixin {
  bool _entered = false;

  // ── ENTRANCE CHOREOGRAPHY (EXPERIENCE PASS §8) ──────────────────────────
  // ONE controller drives the whole list: the first rows settle in first
  // and the rest follow with a tiny stagger. No per-row animations, no
  // timers, no endless loops — the controller runs ONCE on entry and
  // completes. Rows built later (cursor pagination) find it already
  // finished and render at their final state immediately.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Reverse-pull accumulation. Two coordinated sources feed the SAME
  // controller: a drag on the header (outside the list, never a scroll
  // conflict) and the list's own overscroll when it is AT the top — so
  // ordinary list scrolling keeps working untouched.
  double _pullPx = 0;
  bool _pulling = false;

  // PASS A6/A7 — the list's scroll position, so surface-level drags
  // (header, empty area, anywhere that is not the list) only feed the
  // reverse handoff when the list sits at its TOP boundary. Mid-scroll,
  // ordinary scrolling stays untouched.
  final ScrollController _listScroll = ScrollController();

  /// The list's top-limit verdict for surface-level (non-list) pulls.
  bool get _atListTop {
    if (!_listScroll.hasClients) return true; // no list mounted → at top
    return _listScroll.offset <= 0.5;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeEnter(); // first mount (when opened directly into the active state)
  }

  @override
  void dispose() {
    _listScroll.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeActivitySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeEnter(); // the handoff committed while the surface was mounted
  }

  void _maybeEnter() {
    if (_entered || !widget.active) return;
    _entered = true;
    // The entrance choreography fires with the lazy load: the surface was
    // just entered, so the rows settle in as they arrive. Reduced motion
    // skips straight to the final state.
    if (!AzMotion.of(context).travel) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
    // The lazy-load boundary: the FIRST page fetch happens exactly when
    // the user ENTERS the activity state — never on resting Home. The
    // data source is the transaction history (/finance/transactions), so
    // opening Activity never drags rates/friend-requests/notifications
    // along with it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final history = ref.read(transactionHistoryProvider);
      if (history.items.isEmpty) {
        ref.read(transactionHistoryProvider.notifier).refresh();
      }
    });
  }

  void _pullStart() {
    _pullPx = 0;
    _pulling = true;
  }

  void _pullUpdate(double dy) {
    _pullPx += dy;
    widget.onTopPullUpdate(_pullPx);
  }

  /// PASS A6 — a drag starting anywhere OUTSIDE the list (header, empty
  /// area, skeleton, gaps). The ListView is the child in the gesture
  /// arena, so it always wins drags that start on it — the parent
  /// recognizer only fires where nothing scrollable competes, which is
  /// exactly the anywhere-but-the-list surface. Gated on the list's top
  /// boundary (A7): mid-scroll, the surface drag does nothing.
  void _surfaceDragStart(DragStartDetails _) {
    if (!_atListTop) return;
    _pullStart();
  }

  void _surfaceDragUpdate(DragUpdateDetails d) {
    if (!_pulling) return;
    _pullUpdate(d.delta.dy);
  }

  void _surfaceDragEnd(DragEndDetails _) {
    _pullEnd();
  }

  void _pullEnd() {
    if (!_pulling) return;
    _pulling = false;
    final commits = ActivityHandoffPhysics.commits(
      ActivityHandoffPhysics.progressFor(_pullPx),
    );
    _pullPx = 0;
    widget.onTopPullEnd(commits);
  }

  // ── LIST COORDINATION ────────────────────────────────────────────────────
  // Ordinary scrolling is untouched: the ListView owns its gesture arena
  // and only reports back through notifications. A downward OVERSCROLL
  // at pixels == 0 is the one case the list cannot use — and exactly the
  // "pull down from the top" the reverse handoff wants.
  bool _onScrollNotification(ScrollNotification n) {
    // SIGN NOTE: at the list's TOP boundary a DOWNWARD finger drag
    // reports a NEGATIVE overscroll (the scroll position wanted to go
    // below zero and could not). The original `> 0` gate matched only
    // the opposite direction, so the at-top pull-down never reached
    // the handoff — the first-row pull was dead in production. Flip the
    // sign on the way into the same positive-pull grammar the surface
    // drag uses.
    if (n is OverscrollNotification &&
        n.metrics.pixels <= 0 &&
        n.overscroll < 0 &&
        n.dragDetails != null) {
      _pullUpdate(-n.overscroll);
      _pulling = true;
    } else if (n is ScrollEndNotification) {
      _pullEnd();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final history = ref.watch(transactionHistoryProvider);
    // UX-CORRECTION §7: economic activity only. The source is the real
    // transaction history (/finance/transactions), and the surface keeps
    // only explicitly supported financial transaction types — unknown or
    // unmapped records are excluded here rather than presented as
    // mysterious activity. "These are things that happened to my money."
    final records = history.items
        .where((t) => ActivityKindNormalizer.isSupportedOnHome(t.rawType))
        .toList(growable: false);
    final reduceMotion = !AzMotion.of(context).travel;

    final genuineLoading =
        history.isLoading && history.items.isEmpty && history.error == null;

    final surface = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PASS A5 — the heading sits STRUCTURALLY below the deck peek
        // band (ActivityRestGeometry.headingInset), never at a page's
        // conventional top margin: Activity is a layer pulled over Home
        // and its heading keeps a fixed breath below the peek so the
        // reminder-card peek stays visible above the surface.
        Padding(
          padding: const EdgeInsets.only(
            top: ActivityRestGeometry.headingInset,
          ),
          child: _CuedHeading(
            colors: colors,
            progress: widget.headingProgress,
            armed: widget.armedCue,
            reduceMotion: reduceMotion,
            onClose: widget.onClose,
          ),
        ),
        const SizedBox(height: AzSpace.lg),
        // Dormant until the user actually ENTERS: an invisible surface at
        // rest must not run skeleton tickers or render content the fetch
        // hasn't been asked for yet (the lazy-load gate is `_entered`).
        if (!_entered)
          const SizedBox.shrink()
        else if (genuineLoading)
          const _ActivitySkeleton()
        else if (history.error != null && records.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AzSpace.xxl),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tap the message to retry after an error. This is the
                // error branch ONLY — the genuine empty state is calm and
                // premium, never error-styled (correction B).
                onTap: () =>
                    ref.read(transactionHistoryProvider.notifier).refresh(),
                child: Text(
                  'Could not load activity. Tap to retry.',
                  style: AzText.bodyL.copyWith(color: colors.textTertiary),
                ),
              ),
            ),
          )
        else if (records.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AzSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Correction B — the exact semantic structure: one
                    // bold centered line, one normal centered line.
                    Text(
                      'Your activity will appear here',
                      key: const ValueKey('home-activity-empty-title'),
                      textAlign: TextAlign.center,
                      style: AzText.titleL.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AzSpace.sm),
                    Text(
                      "Click the plus button and 'Add Money' to make your first deposit to get started.",
                      key: const ValueKey('home-activity-empty-body'),
                      textAlign: TextAlign.center,
                      style: AzText.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: ListView.builder(
                key: const ValueKey('home-activity-list'),
                controller: _listScroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AzSpace.lg,
                  0,
                  AzSpace.lg,
                  AzSpace.xxl,
                ),
                // +1 trailing slot while a next page exists: the cursor
                // pagination (hasMore/nextCursor) continues the list
                // beyond the first page.
                itemCount: records.length + (history.hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == records.length) {
                    return _LoadMoreTile(
                      key: const ValueKey('home-activity-load-more'),
                      loading: history.isLoading,
                      onLoadMore: () => ref
                          .read(transactionHistoryProvider.notifier)
                          .loadMore(),
                    );
                  }
                  return _StaggeredRow(
                    controller: _entrance,
                    index: i,
                    child: _ActivityActionRow(
                      txn: records[i],
                      colors: colors,
                      reduceMotion: reduceMotion,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );

    // PASS A6 — the ENTIRE visible Activity surface participates in the
    // reverse handoff: a translucent vertical-drag recognizer at the
    // surface level wins the gesture arena wherever no scrollable child
    // competes (the heading, the empty area, the skeleton, the gaps),
    // while the ListView — always the child in the arena — keeps
    // ordinary scrolling completely untouched and reports its own
    // at-top overscroll through the notification path. With the list
    // mounted, the surface drag is gated on the list's TOP boundary
    // (A7): mid-scroll it does nothing at all.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _surfaceDragStart,
      onVerticalDragUpdate: _surfaceDragUpdate,
      onVerticalDragEnd: _surfaceDragEnd,
      child: surface,
    );
  }
}

/// PASS A3/A4 — the Activity heading, a pure function of the handoff
/// state. At rest (progress 1) the arrow points UP: the next downward
/// pull returns to Home. The lock-in cue is restrained: a slight
/// expansion plus a tiny decaying wobble while the pull sits inside the
/// armed plateau — it must read as "Activity is locking into place",
/// never a notification shake, an error flash, or a cartoon bounce.
/// Reduced motion removes the expressive movement while preserving the
/// same final states (the arrow still flips UP on commit).
class _CuedHeading extends StatelessWidget {
  const _CuedHeading({
    required this.colors,
    required this.progress,
    required this.armed,
    required this.reduceMotion,
    required this.onClose,
  });

  final AzamanColors colors;
  final double progress;
  final double armed;
  final bool reduceMotion;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    final scale = reduceMotion ? 1.0 : 1.0 + 0.14 * t + 0.045 * armed;
    final wobble = reduceMotion ? 0.0 : ActivityHandoffPhysics.wobbleFor(armed);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: Center(
        child: ScaleTap(
          onTap: () {
            AzamanHaptics.nav();
            onClose();
          },
          child: Transform.rotate(
            angle: wobble,
            child: Transform.scale(
              scale: scale,
              child: _RecentBubbleFace(
                colors: colors,
                progress: 1,
                selected: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// EXPERIENCE PASS §8 — one row of the entrance choreography. [index]
/// maps onto a small Interval of the shared controller: begin is a tiny
/// per-row delay (capped so long lists don't wait), end completes ~250ms
/// later. The row settles with a small upward translation + opacity lift —
/// nothing else animates. Rows built after the controller completed (cursor
/// pagination) render at their final state immediately.
class _StaggeredRow extends StatelessWidget {
  const _StaggeredRow({
    required this.controller,
    required this.index,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Stagger math: first row starts immediately; each subsequent row is
    // 50ms later. The 0.5 cap keeps deep lists instant after the first
    // screenful — only the visible-on-arrival rows choreograph.
    final begin = (index * 0.055).clamp(0.0, 0.5);
    final end = (begin + 0.25).clamp(0.0, 1.0);
    if (begin >= 1.0 || controller.isCompleted) return child;

    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final slide = 14 * (1 - curved.value);
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(offset: Offset(0, slide), child: child),
        );
      },
    );
  }
}

/// Trailing tile while `hasMore`: builds schedule the next cursor page
/// exactly once per build (guarded by the notifier's own isLoading/
/// hasMore gate), and the tile shows quiet progress while it loads.
class _LoadMoreTile extends StatelessWidget {
  final bool loading;
  final VoidCallback onLoadMore;

  const _LoadMoreTile({
    super.key,
    required this.loading,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AzSpace.md),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: loading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ActivityActionRow extends StatelessWidget {
  final TransactionRecord txn;
  final AzamanColors colors;
  final bool reduceMotion;

  const _ActivityActionRow({
    required this.txn,
    required this.colors,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final action = ActivityActionResolver.resolve(txn);
    final failed = txn.status == 'FAILED' || txn.status == 'CANCELLED';
    // AUDIT §4: rendering reads the SAME centralised direction semantics
    // the actions read (TransactionRecord.isInbound) — the metadata
    // direction flag is honoured here exactly as it is by Send Again.
    final isCredit = txn.isInbound;

    // UX-CORRECTION §8: a roomy two-line card, never a squeezed single
    // row. Top: counterparty/title + date/state + amount. Bottom: the
    // typed action as a WIDE button — full labels like 'View withdrawal'
    // fit without truncation, so nothing meaningful hides behind ...
    return Padding(
      padding: const EdgeInsets.only(bottom: AzSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(AzSpace.lg),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.md),
          border: Border.all(color: colors.divider, width: 0.5),
          boxShadow: AzElevation.level1(colors.isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(txn),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.title.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AzSpace.xs),
                      Text(
                        '${_shortDate(txn.createdAt)}${failed ? ' · Failed' : ''}',
                        style: AzText.bodyS.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AzSpace.md),
                Text(
                  '${isCredit ? '+' : '-'}${AzMoney.usdc(txn.amountUsdc.abs())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AzText.title.copyWith(
                    color: failed
                        ? colors.textTertiary
                        : isCredit
                        ? colors.success
                        : colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AzSpace.lg),
            // The typed action button — rendered from structured data
            // only, wide enough for its full label.
            _ActivityActionButton(
              label: action.label,
              accent: colors.accent,
              onTap: () => ActivityActionResolver.dispatch(context, txn),
            ),
          ],
        ),
      ),
    );
  }

  /// Display title — DESCRIPTION first, then counterparty, then a
  /// prettified raw type. NEVER a source of action semantics.
  static String _titleFor(TransactionRecord t) {
    final desc = t.description;
    if (desc.isNotEmpty) return desc;
    final cp = t.counterparty;
    if (cp.isNotEmpty) return '${_prettyType(t.rawType)} \u00b7 $cp';
    return _prettyType(t.rawType);
  }

  static String _prettyType(String rawType) {
    final spaced = rawType.replaceAll('_', ' ').toLowerCase();
    if (spaced.isEmpty) return 'Activity';
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static String _shortDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return '${d.day}/${d.month}';
  }
}

/// UX-CORRECTION §8: the activity action is a WIDE button with room for
/// its full label ('Send again', 'View withdrawal', ...) — the old tiny
/// pill chip is what squeezed everything onto one line and forced
/// ellipsized labels.
class _ActivityActionButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ActivityActionButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: AzSpace.lg,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AzRadius.md),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: AzText.bodyS.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        6,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SkeletonBlock(
                width: 42,
                height: 42,
                borderRadius: BorderRadius.all(Radius.circular(21)),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBlock(width: 140, height: 13),
                    SizedBox(height: 7),
                    SkeletonBlock(width: 80, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 10),
              SkeletonBlock(width: 54, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
