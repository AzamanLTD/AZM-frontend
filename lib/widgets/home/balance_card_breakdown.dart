// =============================================================================
// AZAMAN — BALANCE CARD (ICON-LED BREAKDOWN BACK FACE)
// Final Balance Card Redesign §8: replaces the hard-to-scan text grid with
// a polished icon-led breakdown — small recognizable icons, readable
// labels, right-aligned amounts and explicit native units.
//
// Sections:
//   Available assets      GHS wallet (native GHS) · USDC held (actual
//                          liquid USDC — a REAL holding, never the
//                          equivalent figure)
//   Locked or committed   Escrow & disputes (grouped visually, distinct
//                          underlying fields preserved) · Vaults ·
//                          Savings (withdrawable sub-caption when the
//                          backend provides the net) · Susu (dash while
//                          unknown) · Vendor/unallocated (only when
//                          relevant, labelled with its availability state)
//   Non-cash              AZM points — never part of any monetary rail
//
// LAWS:
//   • Raw GHS and USDC amounts are NEVER added together. The share rail
//     (when shown) normalizes every USDC bucket into GHS with the one
//     valid valuation rate; without a valid rate there is no rail — only
//     a clearly neutral unavailable presentation.
//   • AZM points are excluded from every rail and every total.
//   • Only backend-confirmed immediately withdrawable funds count toward
//     the front headline; nothing here feeds the headline.
//   • Icons supplement text — every icon carries an accessible semantic
//     label, and labels are never replaced by icons.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';

/// One icon-led breakdown row.
class _BreakdownRow {
  const _BreakdownRow({
    required this.label,
    required this.icon,
    required this.iconSemantic,
    required this.amount,
    required this.unit,
    required this.color,
    this.subCaption,
    this.value,
  });

  final String label;
  final IconData icon;
  final String iconSemantic;
  final double? value; // null = unknown (dash), excluded from rails
  final String amount;
  final String unit;
  final Color color;
  final String? subCaption;
}

/// The redesigned icon-led breakdown back face.
class BalanceCardBreakdown extends StatelessWidget {
  const BalanceCardBreakdown({
    super.key,
    required this.valuation,
    required this.colors,
  });

  final BalanceCardValuation valuation;
  final AzamanColors colors;

  List<_BreakdownRow> _availableRows() => [
    _BreakdownRow(
      label: 'GHS wallet',
      icon: HugeIconsSolid.wallet01,
      iconSemantic: 'GHS wallet icon',
      value: valuation.nativeGhsAvailable,
      amount: AzMoney.ghs(valuation.nativeGhsAvailable),
      unit: 'GHS',
      color: colors.success,
    ),
    _BreakdownRow(
      label: 'USDC held',
      icon: HugeIconsSolid.coins01,
      iconSemantic: 'USDC wallet icon',
      value: valuation.availableUsdc,
      amount: AzMoney.amount(valuation.availableUsdc),
      unit: 'USDC',
      color: colors.accent,
      subCaption: 'actual USDC held — not the equivalent figure',
    ),
  ];

  List<_BreakdownRow> _lockedRows() => [
    // Escrow & disputes: grouped visually, distinct fields preserved.
    _BreakdownRow(
      label: 'Escrow & disputes',
      icon: HugeIconsSolid.lock,
      iconSemantic: 'Escrow lock icon',
      value: valuation.escrowLocked + valuation.disputeEscrow,
      amount: AzMoney.amount(valuation.escrowLocked + valuation.disputeEscrow),
      unit: 'USDC',
      color: colors.warning,
      subCaption:
          'Escrow ${AzMoney.amount(valuation.escrowLocked)} · '
          'Disputes ${AzMoney.amount(valuation.disputeEscrow)} USDC',
    ),
    _BreakdownRow(
      label: 'Vaults',
      icon: HugeIconsSolid.shield01,
      iconSemantic: 'Vault shield icon',
      value: valuation.vaultLocked,
      amount: AzMoney.amount(valuation.vaultLocked),
      unit: 'USDC',
      color: colors.accentSecondary,
    ),
    _BreakdownRow(
      label: 'Savings',
      icon: HugeIconsSolid.piggyBank,
      iconSemantic: 'Savings piggy bank icon',
      value: valuation.savingsLocked,
      amount: AzMoney.amount(valuation.savingsLocked),
      unit: 'USDC',
      color: colors.success,
      subCaption: valuation.savingsWithdrawable != null
          ? 'net withdrawable today '
                '${AzMoney.amount(valuation.savingsWithdrawable!)} USDC'
          : null,
    ),
    _BreakdownRow(
      label: 'Susu',
      icon: HugeIconsSolid.userGroup,
      iconSemantic: 'Susu group icon',
      // Unknown (still loading / failed fetch) is a DASH, never a
      // zero: unknown must not read as "nothing".
      value: valuation.susuCommitted,
      amount: valuation.susuCommitted != null
          ? AzMoney.amount(valuation.susuCommitted!)
          : '—',
      unit: valuation.susuCommitted != null ? 'USDC' : '',
      color: colors.warning,
      subCaption: valuation.susuCommitted == null
          ? 'amount not loaded yet'
          : null,
    ),
    if (valuation.vendorRowRelevant)
      _BreakdownRow(
        label: 'Vendor balance',
        icon: HugeIconsSolid.store01,
        iconSemantic: 'Vendor storefront icon',
        value: valuation.vendorUnallocated,
        amount: AzMoney.amount(valuation.vendorUnallocated),
        unit: 'USDC',
        color: colors.accent,
        subCaption: valuation.vendorUnallocatedEligible
            ? 'unallocated, withdrawable'
            : 'unallocated — not currently withdrawable',
      ),
  ];

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: AzSpace.md, bottom: AzSpace.xs),
    child: Row(
      children: [
        Text(title, style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    ),
  );

  Widget _row(_BreakdownRow row) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: row.iconSemantic,
              excludeSemantics: true,
              child: Icon(row.icon, size: 14, color: row.color),
            ),
            const SizedBox(width: AzSpace.sm),
            Flexible(
              child: Text(
                row.label,
                style: AzText.bodyS.copyWith(color: colors.textSecondary),
              ),
            ),
            const Spacer(),
            // Right-aligned monetary amount with its explicit native
            // unit — GHS rows read "GH₵ 1,234.56", USDC rows read
            // "12.00 USDC". No cross-currency sums anywhere.
            Text.rich(
              TextSpan(
                text: row.amount,
                style: AzText.money(
                  colors.textPrimary,
                  size: 14,
                  weight: FontWeight.w600,
                  tracking: 0,
                ),
                children: [
                  if (row.unit.isNotEmpty)
                    TextSpan(
                      text: ' ${row.unit}',
                      style: AzText.bodyS.copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (row.subCaption != null)
          Padding(
            padding: const EdgeInsets.only(left: 14 + AzSpace.sm),
            child: Text(
              row.subCaption!,
              style: AzText.caption.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = valuation;
    final rate = v.rate.hasRate ? v.rate.ghsPerUsdc! : null;

    // Share rail: every monetary bucket normalized into GHS with the ONE
    // valid rate. No valid rate → no rail (a neutral note instead); AZM
    // points are NEVER a rail segment.
    final railBuckets = <(double, Color)>[
      (v.nativeGhsAvailable, colors.success),
      (v.availableUsdc, colors.accent),
      (v.escrowLocked, colors.warning),
      (v.disputeEscrow, colors.warning),
      (v.vaultLocked, colors.accentSecondary),
      (v.savingsLocked, colors.success),
      if (v.susuCommitted != null) (v.susuCommitted!, colors.warning),
      if (v.vendorRowRelevant) (v.vendorUnallocated, colors.accent),
    ];
    // GHS-normalized segment sizes (USDC buckets convert at the rate).
    final segments = rate == null
        ? const <(double, Color)>[]
        : [
            for (final (raw, color) in railBuckets)
              (raw.isFinite && raw > 0 ? raw * rate : 0.0, color),
          ];
    final railTotal = segments.fold<double>(
      0,
      (sum, s) => sum + (s.$1 > 0 ? s.$1 : 0),
    );

    return Container(
      key: const ValueKey('balance-fx-breakdown-card'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AzRadius.brXl,
        border: Border.all(color: colors.border, width: 0.75),
      ),
      padding: const EdgeInsets.all(AzSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BREAKDOWN',
            key: const ValueKey('balance-fx-breakdown-header'),
            style: AzText.eyebrow.copyWith(color: colors.textTertiary),
          ),

          // ── Share rail (GHS-normalized, only with a valid rate) ─────
          if (rate != null && railTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: AzSpace.sm),
              child: ClipRRect(
                borderRadius: AzRadius.brPill,
                child: SizedBox(
                  height: 10,
                  key: const ValueKey('balance-fx-share-rail'),
                  child: Row(
                    children: [
                      for (final (size, color) in segments)
                        if (size > 0)
                          Expanded(
                            flex: (size / railTotal * 1000).round().clamp(
                              1,
                              1000,
                            ),
                            child: Container(color: color),
                          ),
                    ],
                  ),
                ),
              ),
            )
          else if (rate == null)
            Padding(
              padding: const EdgeInsets.only(top: AzSpace.sm),
              child: Text(
                'Share view unavailable — it needs a valid FX rate',
                key: const ValueKey('balance-fx-share-rail-unavailable'),
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ),

          _sectionHeader('Available assets'),
          for (final row in _availableRows()) _row(row),
          _sectionHeader('Locked or committed'),
          for (final row in _lockedRows()) _row(row),
          _sectionHeader('Non-cash'),
          _row(
            _BreakdownRow(
              label: 'AZM points',
              icon: HugeIconsSolid.flash,
              iconSemantic: 'AZM points icon',
              value: v.azmPoints,
              amount: AzMoney.amount(v.azmPoints, decimals: 0),
              unit: 'AZM',
              color: colors.accentSecondary,
              subCaption: 'loyalty points — not money, never in a total',
            ),
          ),
        ],
      ),
    );
  }
}
