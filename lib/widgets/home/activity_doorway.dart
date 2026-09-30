// =============================================================================
// AZAMAN — RECENT ACTIVITY DOORWAY + SECOND RESTING STATE  (NEW-HOME §10-12)
//
// The resting Home renders NO transaction rows — only the Recent Activity
// heading/doorway. The doorway is:
//   * tappable    → the canonical activity screen (/account/activity)
//   * gesture    → a controlled handoff into Home's SECOND resting state,
//                  the in-Home activity surface.
//
// The handoff is physical and deliberate (§11): resistance below a
// threshold, a commit that snaps the activity surface into focus while the
// wallet composition moves out of the way, and the same grammar in reverse.
// NOT a giant animated page-scroll gimmick — two clear resting states with
// a controlled handoff.
//
// §12 is a REAL lazy-load boundary: entering the activity state triggers
// the existing summary refresh (the only fetch), skeletons appear ONLY
// during genuine cold loading, and resting Home never fetches to decorate
// a preview.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/home_summary_service.dart';
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

/// The resting-state heading/doorway. Tapping navigates to the canonical
/// activity screen; the parent wires the drag handoff around it.
class RecentActivityDoorway extends ConsumerWidget {
  const RecentActivityDoorway({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return ScaleTap(
      onTap: () {
        AzamanHaptics.nav();
        context.push('/account/activity');
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
              HugeIconsSolid.arrowDown01,
              size: 16,
              color: colors.textTertiary,
            ),
            const Spacer(),
            Text(
              'Pull down',
              style: AzText.bodyS.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home's second resting state. A REAL lazy-load boundary: the surface
/// calls the existing summary refresh when it ENTERS (not before), renders
/// the existing skeleton system only while genuinely loading with no data,
/// and gives each activity an explicit typed action.
class HomeActivitySurface extends ConsumerStatefulWidget {
  const HomeActivitySurface({
    super.key,
    required this.onClose,

    /// Whether the handoff COMMITTED — the surface is mounted at rest too
    /// (it fades in during the drag), so `active` is the lazy-load gate:
    /// the fetch fires exactly once, when the user actually ENTERS.
    required this.active,
  });

  final VoidCallback onClose;
  final bool active;

  @override
  ConsumerState<HomeActivitySurface> createState() =>
      _HomeActivitySurfaceState();
}

class _HomeActivitySurfaceState extends ConsumerState<HomeActivitySurface> {
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeEnter(); // first mount (when opened directly into the active state)
  }

  @override
  void didUpdateWidget(HomeActivitySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeEnter(); // the handoff committed while the surface was mounted
  }

  void _maybeEnter() {
    if (_entered || !widget.active) return;
    _entered = true;
    // The lazy-load boundary: the fetch happens exactly when the user
    // ENTERS the activity state — never on resting Home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(homeSummaryProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final summary = ref.watch(homeSummaryProvider);
    final txns = summary.recentTransactions;
    final reduceMotion = !AzMotion.of(context).travel;

    final genuineLoading = summary.loading && txns.isEmpty && summary.transactionsError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AzamanHaptics.nav();
                  widget.onClose();
                },
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.arrowLeft01,
                        size: 18, color: colors.textPrimary),
                    const SizedBox(width: AzSpace.xs),
                    Text(
                      'Wallet',
                      style: AzText.bodyL.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Recent Activity',
                style: AzText.title.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
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
        else if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AzSpace.xxl),
            child: Center(
              child: Text(
                summary.transactionsError != null
                    ? 'Could not load activity. Pull to refresh.'
                    : 'Nothing yet — your activity will appear here.',
                style: AzText.bodyL.copyWith(color: colors.textTertiary),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  AzSpace.lg, 0, AzSpace.lg, AzSpace.xxl),
              itemCount: txns.length,
              itemBuilder: (context, i) => _ActivityActionRow(
                txn: txns[i], colors: colors, reduceMotion: reduceMotion),
            ),
          ),
      ],
    );
  }
}

class _ActivityActionRow extends StatelessWidget {
  final TransactionSummary txn;
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

    return Padding(
      padding: const EdgeInsets.only(bottom: AzSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AzText.title.copyWith(color: colors.textPrimary),
                ),
                if (txn.createdAt != null)
                  Text(
                    _shortDate(txn.createdAt!),
                    style:
                        AzText.bodyS.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AzSpace.md),
          Text(
            '${txn.isCredit ? '+' : '-'}'
            '${txn.symbol == 'GHS' ? AzMoney.ghs(txn.amount) : AzMoney.usdc(txn.amount)}',
            style: AzText.title.copyWith(
              color: failed
                  ? colors.textTertiary
                  : txn.isCredit
                      ? colors.success
                      : colors.textPrimary,
            ),
          ),
          const SizedBox(width: AzSpace.md),
          // The typed action chip — rendered from structured data only.
          _ActionChip(
            label: action.label,
            accent: colors.accent,
            onTap: () => ActivityActionResolver.dispatch(context, txn),
          ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return '${d.day}/${d.month}';
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: AzText.bodyS.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
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
