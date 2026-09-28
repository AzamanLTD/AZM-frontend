// =============================================================================
// FLIPPABLE BALANCE CARD  (Master Sprint v2 → TASK-009d rebuild)
//
// Wraps HologramBalanceCard with a vertical 3D flip-to-back gesture. Tapping
// the card flips it on the X-axis (180° around the horizontal middle) to
// reveal a breakdown of every balance the user holds:
//
//   • Available USDC        • Vaults (sum of ACTIVE vaults)
//   • Escrow Locked         • Savings (/savings/overview)
//   • Vendor (vendor only)   • Susu (committed, from susuListProvider)
//   • Dispute Escrow        • AZM Loyalty Points
//
// The back face NEVER scrolls (the F-020 fix): a 10px share rail gives the
// instant visual read of where the money sits, and a 2-column grid shows every
// bucket's exact amount at once. Every bucket is ALWAYS present — a breakdown
// that omits a bucket is not a breakdown (the F-022 fix: the Susu row used to
// be gated behind a hardcoded 0).
//
// Design intent: position-locked flip — the card stays at the same screen
// rect, the same shadow plays on both faces. No overlay, no scrim.
// Just flips in place. Tap again to flip back.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';

class FlippableBalanceCard extends ConsumerStatefulWidget {
  const FlippableBalanceCard({super.key});

  @override
  ConsumerState<FlippableBalanceCard> createState() =>
      _FlippableBalanceCardState();
}

class _FlippableBalanceCardState extends ConsumerState<FlippableBalanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flip;
  bool _isBack = false;

  // Cached extras pulled lazily on first flip — re-fetched at most once per
  // [_extrasTtl] (the F-023 fix: this used to re-hit the network on every open).
  double _vaultLocked = 0;
  double _savingsLocked = 0;
  bool _loadingExtras = false;

  @override
  void initState() {
    super.initState();
    // `spatial` (450ms) — a 3D flip is a large surface move, not a control
    // change, so it belongs on the spatial step. `symmetric` is the matching
    // curve: a flip has no "arriving" or "leaving" end, so it must ease both.
    _ctrl = AnimationController(
      vsync: this,
      duration: MotionTokens.spatial,
    );
    _flip = CurvedAnimation(parent: _ctrl, curve: MotionTokens.symmetric);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    // A flip is a deliberate reveal of the user's own money — a selection, not
    // a navigation. `selection` (selectionClick) is the right sensation.
    AzamanHaptics.selection();
    if (_isBack) {
      _ctrl.reverse();
    } else {
      _fetchExtras();
      _ctrl.forward();
    }
    setState(() => _isBack = !_isBack);
  }

  /// Pulls vault / savings totals. Best-effort — failures degrade to the
  /// last known values rather than to zero, so a network blip cannot make a
  /// user's money appear to vanish.
  ///
  /// The Susu bucket is NOT fetched here — there is no `/susu/summary`
  /// endpoint (verified at spec time). It is derived from the existing
  /// `susuListProvider` in `build`.
  ///
  /// Cached for [_extrasTtl]. Previously this re-fetched on EVERY flip open, so
  /// flipping the card back and forth repeatedly re-hit the network each time.
  DateTime? _extrasFetchedAt;
  static const Duration _extrasTtl = Duration(minutes: 2);

  bool get _extrasFresh {
    final at = _extrasFetchedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _extrasTtl;
  }

  Future<void> _fetchExtras({bool force = false}) async {
    if (_loadingExtras) return;
    if (!force && _extrasFresh) return;
    setState(() => _loadingExtras = true);
    try {
      final results = await Future.wait([
        apiClient.get('/savings/overview'),
        apiClient.get('/vaults'),
      ]);
      double savings = 0;
      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        savings = (data?['totalSavedUsdc'] as num?)?.toDouble() ?? 0;
      }
      double vaults = 0;
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body) as Map<String, dynamic>;
        final list = body['vaults'] as List<dynamic>? ?? const [];
        for (final v in list) {
          if ((v['status'] ?? '') == 'ACTIVE') {
            vaults += (v['currentAmountUsdc'] as num?)?.toDouble() ?? 0;
          }
        }
      }

      if (mounted) {
        setState(() {
          _savingsLocked = savings;
          _vaultLocked = vaults;
          _extrasFetchedAt = DateTime.now();
          _loadingExtras = false;
        });
      }
    } catch (_) {
      // Deliberately keep the previous values — see the doc comment.
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Susu committed total — derived from the EXISTING Susu list surface
    // (`susuListProvider` → GET /susu/me). There is no `/susu/summary`
    // endpoint; the provider IS the shipped Susu layer. Only groups where
    // the caller is an ACTIVE member of an ACTIVE group count — a completed
    // group has already paid out, and a pending group has not locked funds.
    //
    // Watched here in the state (not in `_BackFace`) so the provider stays
    // alive for the card's lifetime: flipping back and forth does not
    // re-fetch, matching the F-023 cache semantics of `_fetchExtras`.
    final susuRows = ref.watch(susuListProvider).valueOrNull;
    var susuCommitted = 0.0;
    if (susuRows != null) {
      for (final s in susuRows) {
        if (s.status == SusuStatus.active &&
            s.myStatus == SusuMemberStatus.active) {
          susuCommitted += s.contributionUsdc;
        }
      }
    }

    // Pointer handling.
    //
    // A top-level `Listener` captures the tap BEFORE any child can claim it, and
    // a small drag tolerance lets the user scroll the page without
    // false-flipping the card.
    //
    // `HologramBalanceCard` (the front face) also uses a `Listener` — for the
    // holographic specular band. Nested `Listener`s both receive events because
    // `Listener` does NOT enter the gesture arena, so the two coexist without
    // competing. See TASK-009c.
    //
    // NOTE (F-024): the flip fires only when pointer travel is < 8px, while the
    // holographic light needs travel to be visible. So tap = flip and drag = see
    // the light are mutually exclusive BY CONSTRUCTION. Do not raise this
    // tolerance and do not add a long-press to "fix" it — the separation is
    // correct.
    Offset? downAt;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => downAt = e.position,
      onPointerUp: (e) {
        if (downAt == null) return;
        final dist = (e.position - downAt!).distance;
        downAt = null;
        // Treat anything under 8px movement as a tap (lets the user
        // scroll the page without false-flipping the card).
        if (dist < 8) _toggle();
      },
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = _flip.value;
          final angle = t * math.pi;
          final showBack = t > 0.5;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateX(math.pi),
                    child: _BackFace(
                      vaultLocked: _vaultLocked,
                      savingsLocked: _savingsLocked,
                      susuLocked: susuCommitted,
                    ),
                  )
                : const HologramBalanceCard(),
          );
        },
      ),
    );
  }
}

// =============================================================================
// BACK FACE — share rail + 2-column grid. Nothing scrolls.
// =============================================================================
class _BackFace extends ConsumerWidget {
  final double vaultLocked;
  final double savingsLocked;
  final double susuLocked;

  const _BackFace({
    required this.vaultLocked,
    required this.savingsLocked,
    required this.susuLocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(balanceDataProvider);
    final isVendor = ref.watch(tradeProvider).currentRole == AppRole.vendor;

    // Every bucket is ALWAYS present — no `if (value > 0)` gates.
    //
    // F-022: the old code gated the Susu row behind `if (susuLocked > 0)` and
    // hardcoded the value to 0, so the row was unreachable. A breakdown that
    // omits a bucket is not a breakdown. A zero bucket renders as "0.00" and
    // contributes no segment to the rail.
    final rows = <_BalanceRow>[
      _BalanceRow(
        label: 'Available',
        value: balance.availableBalance,
        suffix: 'USDC',
        color: colors.success,
        icon: HugeIconsSolid.wallet01,
      ),
      _BalanceRow(
        label: 'Escrow',
        value: balance.escrowLockedBalance,
        suffix: 'USDC',
        color: colors.warning,
        icon: HugeIconsSolid.lock,
      ),
      if (isVendor)
        _BalanceRow(
          label: 'Vendor',
          value: balance.vendorUnallocatedBalance,
          suffix: 'USDC',
          color: colors.accent,
          icon: HugeIconsSolid.store01,
        ),
      _BalanceRow(
        label: 'Dispute',
        value: balance.disputeEscrowBalance,
        suffix: 'USDC',
        color: colors.danger,
        icon: HugeIconsSolid.alertCircle,
      ),
      _BalanceRow(
        label: 'Vaults',
        value: vaultLocked,
        suffix: 'USDC',
        color: colors.accentSecondary,
        icon: HugeIconsSolid.shield01,
      ),
      _BalanceRow(
        label: 'Savings',
        value: savingsLocked,
        suffix: 'USDC',
        color: colors.success,
        icon: HugeIconsSolid.piggyBank,
      ),
      _BalanceRow(
        label: 'Susu',
        value: susuLocked,
        suffix: 'USDC',
        color: colors.warning,
        icon: HugeIconsSolid.userGroup,
      ),
      _BalanceRow(
        label: 'AZM',
        value: balance.azmBalance,
        suffix: 'AZM',
        color: colors.accentSecondary,
        icon: HugeIconsSolid.flash,
        // AZM is a loyalty point, not a currency — it must never be a slice of
        // the USDC share rail, or the rail would lie about where the money is.
        countsTowardRail: false,
      ),
    ];

    final railRows = rows.where((r) => r.countsTowardRail).toList();
    final railTotal = railRows.fold<double>(0, (sum, r) => sum + r.value);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AzRadius.brXl,
        border: Border.all(color: colors.border, width: 0.75),
      ),
      padding: const EdgeInsets.fromLTRB(
        AzSpace.lg,
        AzSpace.md,
        AzSpace.lg,
        AzSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'BREAKDOWN',
                style: AzText.eyebrow.copyWith(color: colors.textTertiary),
              ),
              const Spacer(),
              Icon(
                HugeIconsSolid.arrowDataTransferHorizontal,
                color: colors.textTertiary,
                size: 12,
              ),
              const SizedBox(width: AzSpace.xs),
              Text(
                'Tap to flip',
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),

          const SizedBox(height: AzSpace.sm),

          // ── Share rail ────────────────────────────────────────────────
          // Segment WIDTHS are proportional to each bucket's share of the USDC
          // total. This is the picture of the breakdown: one glance answers
          // "where is my money?" without reading a single number.
          //
          // Height 10px: thick enough to read as a bar, thin enough to leave the
          // grid its 88px. Do not grow it without redoing the height budget in
          // the task header.
          if (railTotal > 0)
            ClipRRect(
              borderRadius: AzRadius.brPill,
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final row in railRows)
                      if (row.value > 0)
                        Expanded(
                          // `flex` must be an int. Scaling by 1000 keeps three
                          // decimal places of proportion, which is ample: a
                          // bucket holding 0.1% of the total still receives a
                          // visible segment.
                          flex: (row.value / railTotal * 1000)
                              .round()
                              .clamp(1, 1000),
                          child: ColoredBox(color: row.color),
                        ),
                  ],
                ),
              ),
            )
          else
            // Nothing to show — an empty rail would be a hairline of background.
            // Reserve the height so the grid below does not shift.
            SizedBox(
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: AzRadius.brPill,
                ),
              ),
            ),

          const SizedBox(height: AzSpace.md),

          // ── 2-column grid ─────────────────────────────────────────────
          // 8 buckets = 4 rows x 2 columns x 22px = 88px, which is exactly the
          // budget remaining in the card. Every bucket is visible at once
          // — this is the fix for F-020, where 8 stacked rows needed ~272px and
          // forced the user to scroll inside the card.
          Expanded(
            child: _BalanceGrid(rows: rows, colors: colors),
          ),
        ],
      ),
    );
  }
}

/// One balance bucket. [shareOf] is the fraction of the USDC total, used to size
/// the segment in the share rail. [countsTowardRail] is false for AZM, which is
/// a loyalty point rather than a currency and therefore cannot be a slice of a
/// USDC total.
class _BalanceRow {
  final String label;
  final double value;
  final String suffix;
  final Color color;
  final IconData icon;
  final bool countsTowardRail;

  const _BalanceRow({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
    required this.icon,
    this.countsTowardRail = true,
  });
}

/// Lays [rows] out two per line, preserving order.
///
/// A `Wrap` cannot be used here: it would size to content and overflow the fixed
/// card height. A `Column` of `Expanded` rows divides the available height
/// evenly, so the grid adapts whether the user has 6, 7 or 8 buckets.
class _BalanceGrid extends StatelessWidget {
  const _BalanceGrid({required this.rows, required this.colors});

  final List<_BalanceRow> rows;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    final lines = <List<_BalanceRow>>[];
    for (var i = 0; i < rows.length; i += 2) {
      lines.add(rows.sublist(i, i + 2 > rows.length ? rows.length : i + 2));
    }

    return Column(
      children: [
        for (final line in lines)
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: i < line.length
                        ? _BalanceCell(row: line[i], colors: colors)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One bucket: a colour dot, a label, and a tabular amount.
class _BalanceCell extends StatelessWidget {
  const _BalanceCell({required this.row, required this.colors});

  final _BalanceRow row;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: row.value > 0
                ? row.color
                : colors.textTertiary.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AzSpace.sm),
        // The label yields to the amount. `Flexible` + ellipsis means a long
        // label truncates rather than pushing the figure out of the cell.
        Flexible(
          child: Text(
            row.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AzText.label.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AzSpace.xs),
        // `AzMoney.amount` + tabular figures: every figure occupies the same
        // width, so the column of amounts aligns down the card.
        Text(
          AzMoney.amount(row.value),
          style: AzText.bodyS.copyWith(
            color: row.value > 0 ? colors.textPrimary : colors.textTertiary,
            fontWeight: FontWeight.w700,
            fontFeatures: AzText.tabular,
          ),
        ),
      ],
    );
  }
}
