// =============================================================================
// AZAMAN — BALANCE CARD (ICON-LED BREAKDOWN BACK FACE)
//
// The REVERSE of the shared physical card (BalanceCardPair). This face
// supplies CONTENT only — the shared frame owns the material, corner
// radius, rim and edge. There is deliberately no second decorated
// container, no second border, no second rim: the back reads as the matte
// reverse side of the same card, and internal dividers separate
// information rows only.
//
// HIERARCHY (top → bottom):
//   BALANCE BREAKDOWN            compact header + a "return to balance"
//                                  affordance (guarded, accessible)
//   AVAILABLE                    GHS wallet · USDC held (right-aligned
//                                  amounts, explicit native units)
//   LOCKED OR COMMITTED          Escrow & disputes (grouped visually, the
//                                  two underlying values preserved) ·
//                                  Vaults · Savings (withdrawable detail
//                                  only when the data supplies it) · Susu
//                                  (a dash while unknown — never zero) ·
//                                  Vendor (only when relevant, with its
//                                  availability state)
//   NON-CASH                     AZM points — never part of any monetary
//                                  total or rail
//
// The rows live in an inner scroll region clipped to the shared rounded
// boundary: the card's fixed footprint never grows, and vertical drags
// scroll the breakdown without flipping the card.
//
// LAWS:
//   • Raw GHS and USDC amounts are NEVER added together or substituted
//     for one another — "USDC held" is the real holding, never the
//     equivalent figure.
//   • Unknown is rendered as unknown (a dash), never as zero.
//   • AZM points are excluded from every monetary context.
//   • Icons supplement text — every icon carries an accessible semantic
//     label, and no label is ever replaced by an icon. No emojis.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart'
    show FlipGuardMarker;

/// One icon-led breakdown row: a crisp 16dp glyph in the single restrained
/// tone (the meaning lives in the text, not in colour-coded tiles), a
/// clear label, an optional one-line secondary detail, and the amount
/// right-aligned with its explicit native unit.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    super.key,
    required this.label,
    required this.icon,
    required this.iconSemantic,
    required this.amount,
    required this.unit,
    required this.colors,
    this.detail,
  });

  final String label;
  final IconData icon;
  final String iconSemantic;
  final String amount;
  final String unit;
  final AzamanColors colors;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                label: iconSemantic,
                excludeSemantics: true,
                child: Icon(icon, size: 16, color: colors.textSecondary),
              ),
              const SizedBox(width: AzSpace.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AzText.bodyS.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AzSpace.sm),
              // Right-aligned amount with its explicit native unit — GHS
              // rows read "GH₵ 1,234.56", USDC rows read "12.00 USDC".
              // No cross-currency sums anywhere.
              Expanded(
                child: Text.rich(
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  TextSpan(
                    text: amount,
                    style: AzText.money(
                      colors.textPrimary,
                      size: 13,
                      weight: FontWeight.w600,
                      tracking: 0,
                    ),
                    children: [
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: ' $unit',
                          style: AzText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 16 + AzSpace.sm),
              child: Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, this.colors);

  final String title;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AzSpace.sm, bottom: 2),
      child: Text(
        title,
        style: AzText.eyebrow.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// The redesigned icon-led breakdown back face (content of the shared frame).
class BalanceCardBreakdown extends StatelessWidget {
  const BalanceCardBreakdown({
    super.key,
    required this.valuation,
    required this.colors,
    this.flipGuard,
    this.onFlipBackRequested,
  });

  final BalanceCardValuation valuation;
  final AzamanColors colors;

  /// The shared frame's nested-gesture guard (see [FlipGuardMarker]).
  final ValueNotifier<bool>? flipGuard;

  /// Invoked by the header's "return to balance" affordance. The frame
  /// supplies the actual flip; the affordance marks [flipGuard] so the
  /// tap never also lands in the frame's tap-to-flip listener.
  final VoidCallback? onFlipBackRequested;

  @override
  Widget build(BuildContext context) {
    final v = valuation;

    return Padding(
      key: const ValueKey('balance-fx-breakdown-card'),
      padding: const EdgeInsets.fromLTRB(
        AzSpace.lg, AzSpace.md, AzSpace.lg, AzSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compact header + return affordance ─────────────────────
          Row(
            key: const ValueKey('balance-fx-breakdown-header'),
            children: [
              Expanded(
                child: Text(
                  'BALANCE BREAKDOWN',
                  style: AzText.eyebrow.copyWith(color: colors.textTertiary),
                ),
              ),
              if (onFlipBackRequested != null)
                FlipGuardMarker(
                  flipGuard: flipGuard,
                  child: Semantics(
                    label: 'Back to balance',
                    button: true,
                    child: Tooltip(
                      message: 'Back to balance',
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        key: const ValueKey('bc-flip-back'),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          onPressed: onFlipBackRequested,
                          icon: Icon(
                            HugeIconsSolid.arrowLeft01,
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
          // ── Scrollable rows, clipped to the shared rounded frame ────
          // The fixed footprint never grows: genuinely additional detail
          // scrolls INSIDE the card. Vertical drags belong to this region;
          // only a deliberate tap (< 8px travel) flips the card back.
          Expanded(
            child: ListView(
              key: const ValueKey('bc-breakdown-scroll'),
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              children: [
                _SectionLabel('AVAILABLE', colors),
                _BreakdownRow(
                  key: const ValueKey('bc-row-ghs-wallet'),
                  label: 'GHS wallet',
                  icon: HugeIconsSolid.wallet01,
                  iconSemantic: 'GHS wallet icon',
                  amount: AzMoney.ghs(v.nativeGhsAvailable),
                  unit: '',
                  colors: colors,
                ),
                _BreakdownRow(
                  key: const ValueKey('bc-row-usdc-held'),
                  label: 'USDC held',
                  icon: HugeIconsSolid.coins01,
                  iconSemantic: 'USDC wallet icon',
                  amount: AzMoney.amount(v.availableUsdc),
                  unit: 'USDC',
                  colors: colors,
                ),
                _SectionLabel('LOCKED OR COMMITTED', colors),
                _BreakdownRow(
                  key: const ValueKey('bc-row-escrow'),
                  label: 'Escrow & disputes',
                  icon: HugeIconsSolid.lock,
                  iconSemantic: 'Escrow lock icon',
                  amount: AzMoney.amount(v.escrowLocked + v.disputeEscrow),
                  unit: 'USDC',
                  colors: colors,
                  // Grouped visually, distinct values preserved.
                  detail: 'Escrow ${AzMoney.amount(v.escrowLocked)} · '
                      'Disputes ${AzMoney.amount(v.disputeEscrow)} USDC',
                ),
                _BreakdownRow(
                  key: const ValueKey('bc-row-vaults'),
                  label: 'Vaults',
                  icon: HugeIconsSolid.shield01,
                  iconSemantic: 'Vault shield icon',
                  amount: AzMoney.amount(v.vaultLocked),
                  unit: 'USDC',
                  colors: colors,
                ),
                _BreakdownRow(
                  key: const ValueKey('bc-row-savings'),
                  label: 'Savings',
                  icon: HugeIconsSolid.piggyBank,
                  iconSemantic: 'Savings piggy bank icon',
                  amount: AzMoney.amount(v.savingsLocked),
                  unit: 'USDC',
                  colors: colors,
                  // Shown only when the authoritative data supplies it.
                  detail: v.savingsWithdrawable != null
                      ? 'withdrawable today '
                          '${AzMoney.amount(v.savingsWithdrawable!)} USDC'
                      : null,
                ),
                _BreakdownRow(
                  key: const ValueKey('bc-row-susu'),
                  label: 'Susu',
                  icon: HugeIconsSolid.userGroup,
                  iconSemantic: 'Susu group icon',
                  // Unknown (still loading / failed fetch) is a DASH,
                  // never a zero: unknown must not read as "nothing".
                  amount: v.susuCommitted != null
                      ? AzMoney.amount(v.susuCommitted!)
                      : '—',
                  unit: v.susuCommitted != null ? 'USDC' : '',
                  colors: colors,
                  detail: v.susuCommitted == null ? 'not loaded yet' : null,
                ),
                if (v.vendorRowRelevant)
                  _BreakdownRow(
                    key: const ValueKey('bc-row-vendor'),
                    label: 'Vendor balance',
                    icon: HugeIconsSolid.store01,
                    iconSemantic: 'Vendor storefront icon',
                    amount: AzMoney.amount(v.vendorUnallocated),
                    unit: 'USDC',
                    colors: colors,
                    detail: v.vendorUnallocatedEligible
                        ? 'unallocated · withdrawable'
                        : 'unallocated · not withdrawable now',
                  ),
                _SectionLabel('NON-CASH', colors),
                _BreakdownRow(
                  key: const ValueKey('bc-row-azm-points'),
                  label: 'AZM points',
                  icon: HugeIconsSolid.flash,
                  iconSemantic: 'AZM points icon',
                  amount: AzMoney.amount(v.azmPoints, decimals: 0),
                  unit: 'pts',
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
