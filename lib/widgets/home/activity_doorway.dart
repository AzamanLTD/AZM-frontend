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

/// Pure, unit-testable handoff physics. Same grammar as the card deck:
/// resisted progress, deliberate threshold, symmetric reverse.
class ActivityHandoffPhysics {
  const ActivityHandoffPhysics._();

  /// Drag travel that maps to full handoff progress.
  static const double travelPx = 170;

  /// Commit fraction — deliberate, past the resisted midpoint.
  static const double commitThreshold = 0.55;

  static double progressFor(double dragPx) {
    if (dragPx <= 0) return 0;
    return (dragPx / travelPx).clamp(0.0, 1.0);
  }

  /// Ease-in resistance: the page pushes back at first.
  static double revealFor(double progress) {
    final p = progressFor(progress * travelPx);
    return p * p;
  }

  static bool commits(double progress) => progress >= commitThreshold;
}

/// The resting-state heading/doorway. Tapping enters the SAME second
/// resting state as the upward drag (correction A) — the parent owns the
/// handoff. Clean and minimal: identity bar, heading, directional arrow.
/// No instructional sentence.
class RecentActivityDoorway extends ConsumerWidget {
  const RecentActivityDoorway({super.key, required this.onOpen});

  /// Enters the in-Home activity surface — identical to the pull-up handoff.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return ScaleTap(
      key: const ValueKey('recent_activity_doorway'),
      onTap: () {
        AzamanHaptics.nav();
        onOpen();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AzSpace.sm),
            Flexible(
              child: Text(
                'Recent Activity',
                style: AzText.titleXl.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: AzSpace.xs),
            Icon(
              // UX-CORRECTION §6: the doorway rises from BELOW, so the
              // gesture that reaches the activity state is a pull UP —
              // wording, arrow and gesture direction all agree now.
              HugeIconsSolid.arrowUp01,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
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

    /// REVERSE handoff (audit §1): accumulated downward pull (logical px)
    /// from the top of the activity surface — from the header gesture and
    /// from the list-at-top overscroll. The parent maps it onto the
    /// handoff animation; the surface owns the threshold decision.
    required this.onTopPullUpdate,

    /// The reverse pull ended. [commits] is the surface's threshold
    /// verdict: true collapses back to the wallet state, false springs
    /// back to the activity state.
    required this.onTopPullEnd,
  });

  final VoidCallback onClose;
  final bool active;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeEnter(); // first mount (when opened directly into the active state)
  }

  @override
  void dispose() {
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

  void _pullEnd() {
    if (!_pulling) return;
    _pulling = false;
    final commits =
        ActivityHandoffPhysics.commits(ActivityHandoffPhysics.progressFor(_pullPx));
    _pullPx = 0;
    widget.onTopPullEnd(commits);
  }

  // ── LIST COORDINATION ────────────────────────────────────────────────────
  // Ordinary scrolling is untouched: the ListView owns its gesture arena
  // and only reports back through notifications. A downward OVERSCROLL
  // at pixels == 0 is the one case the list cannot use — and exactly the
  // "pull down from the top" the reverse handoff wants.
  bool _onScrollNotification(ScrollNotification n) {
    if (n is OverscrollNotification &&
        n.metrics.pixels <= 0 &&
        n.overscroll > 0 &&
        n.dragDetails != null) {
      _pullUpdate(n.overscroll);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header sits OUTSIDE the list, so a vertical drag on it can
        // never fight list scrolling. Pulling it down collapses the
        // activity state (the reverse handoff).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _pullStart(),
          onVerticalDragUpdate: (d) => _pullUpdate(d.delta.dy),
          onVerticalDragEnd: (_) => _pullEnd(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
            child: Row(
              children: [
                // Correction A: the activity state's heading is the SAME
                // doorway identity, now at the top of the visible content
                // — identity bar, heading, directional arrow facing UP.
                // The old "← Wallet  Recent Activity" composition is gone;
                // the reverse handoff (pull down / tap) walks the stack
                // back to the wallet with the same spring grammar.
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AzSpace.sm),
                Flexible(
                  child: Text(
                    'Recent Activity',
                    key: const ValueKey('home-activity-header-title'),
                    style: AzText.titleXl.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: AzSpace.xs),
                Icon(
                  HugeIconsSolid.arrowUp01,
                  size: 16,
                  color: colors.textTertiary,
                ),
              ],
            ),
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
                onTap: () => ref
                    .read(transactionHistoryProvider.notifier)
                    .refresh(),
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
                      style: AzText.body.copyWith(
                        color: colors.textSecondary,
                      ),
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
                physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(
                    AzSpace.lg, 0, AzSpace.lg, AzSpace.xxl),
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
                        reduceMotion: reduceMotion),
                  );
                },
              ),
            ),
          ),
      ],
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
          child: Transform.translate(
            offset: Offset(0, slide),
            child: child,
          ),
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

  const _LoadMoreTile({super.key, required this.loading, required this.onLoadMore});

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
                        style:
                            AzText.title.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AzSpace.xs),
                      Text(
                        '${_shortDate(txn.createdAt)}${failed ? ' · Failed' : ''}',
                        style: AzText.bodyS
                            .copyWith(color: colors.textTertiary),
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

  const _ActivityActionButton(
      {required this.label, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg, vertical: 10),
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
