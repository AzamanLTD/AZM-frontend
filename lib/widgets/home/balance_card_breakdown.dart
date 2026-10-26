// =============================================================================
// AZAMAN — BALANCE CARD (SECTION-PAGED BREAKDOWN BACK FACE)
//
// The REVERSE of the shared physical card (BalanceCardPair). Content
// only — the shared frame owns the material, corner radius, rim, edge
// and the fixed 165dp footprint.
//
// NAVIGATION MODEL (B4): the back is NOT one long scrolling report. It
// is a snap-paged walk through discrete sections, in this order:
//
//   1. AVAILABLE     GHS wallet (unknown until the native-GHS contract
//                     lands — a dash, never GH₵ 0.00) · USDC held (the
//                     REAL holding, never the equivalent figure)
//   2. COMMITTED     Vaults · Savings (GHS-native) · Susu — each a dash
//                     while unknown, never a zero
//   3. LOCKED        Escrow · Dispute escrow (separate visible values)
//   4. VENDOR        Unallocated vendor balance — present ONLY when the
//                     account is a vendor; never padded otherwise
//   5. NON-CASH      AZM loyalty points — excluded from every monetary
//                     total, FX calculation and rail
//
// A fractional-height PageView (viewportFraction 0.86) pages one
// section per step: each page shows a small section header, its rows,
// and a deliberate peek of the NEXT section's header at the bottom so
// more content is discoverable. The compact section-ICON indicator row
// beneath the pager marks the active section (quiet emphasis, subdued
// siblings — smaller and quieter than the row icons) and carries the
// full 'Section N of M: <name>' semantics.
//
// GESTURES: vertical swipes PAGE the breakdown and never flip the card
// (the pager owns vertical drags; only a deliberate tap — < 8px travel,
// the frame's contract — flips). The header's return affordance marks
// the frame's flip guard so tapping it never double-triggers through
// the parent listener.
//
// LAWS:
//   • Raw GHS and USDC amounts are NEVER added together or substituted
//     for one another — "USDC held" is the real holding, never the
//     equivalent figure.
//   • Unknown is rendered as unknown (a dash), never as zero.
//   • AZM points are excluded from every monetary context.
//   • Icons supplement text — every icon carries an accessible semantic
//     label; no label is ever replaced by an icon. No emojis.
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
    this.showDivider = false,
  });

  final String label;
  final IconData icon;
  final String iconSemantic;
  final String amount;
  final String unit;
  final AzamanColors colors;
  final String? detail;

  /// One consistent hairline between rows within a section. The LAST row
  /// of a section carries no divider (the section label's own spacing is
  /// the rhythm); the divider is a fixed 1px rule in the palette's quiet
  /// neutral so the list reads as one uniform ledger, never as tiles.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // SECTION-PAGE RHYTHM: each section must fit its snap page inside
      // the fixed 165dp footprint, so the row stays ONE compact line —
      // the optional detail rides INLINE as a muted suffix (never a
      // second line that could push a section past its page).
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Semantics(
                label: iconSemantic,
                child: Icon(icon, size: 16, color: colors.textSecondary),
              ),
              const SizedBox(width: AzSpace.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    style: AzText.bodyS.copyWith(
                      color: colors.textPrimary,
                    ),
                    children: [
                      if (detail != null)
                        TextSpan(
                          text: '  ·  $detail',
                          style: AzText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  // ONE line, always — the page-fit contract above. The
                  // long "no GHS wallet on the current contract" suffix
                  // must ELLIPSIZE, never wrap: a wrapped row pushed the
                  // AVAILABLE section 9.9dp past its snap page on the
                  // real Home (fixed 165dp card). Screen readers still
                  // get the full untruncated disclosure via the
                  // semantics label.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  semanticsLabel:
                      detail == null ? null : '$label · $detail',
                ),
              ),
              const SizedBox(width: AzSpace.xs),
              Flexible(
                child: Text(
                  '$amount $unit'.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: AzText.bodyS.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (showDivider) ...[
            const SizedBox(height: 2),
            Container(
              key: const ValueKey('bc-row-divider'),
              height: 1,
              color: colors.divider,
            ),
          ],
        ],
      ),
    );
  }
}

/// A small, readable section header inside one page.
class _SectionLabel extends StatelessWidget {
  // Section pages build labels positionally; the pager's own section
  // keys identify them.
  // ignore: unused_element_parameter
  // ignore: prefer_const_constructors_in_immutables
  _SectionLabel(this.text, this.colors);

  final String text;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        text,
        style: AzText.eyebrow.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// One paged section of the breakdown.
class _Section {
  const _Section({
    required this.key,
    required this.title,
    required this.indicatorIcon,
    required this.indicatorSemantic,
    required this.child,
  });

  final ValueKey<String> key;
  final String title;
  final IconData indicatorIcon;

  /// The section's semantic name — used verbatim by the indicator's
  /// 'Section N of M' announcement.
  final String indicatorSemantic;
  final Widget child;
}

/// The section-paged back face.
class BalanceCardBreakdown extends StatefulWidget {
  const BalanceCardBreakdown({
    super.key,
    required this.valuation,
    required this.colors,
    this.flipGuard,
    this.onFlipBackRequested,
  });

  final BalanceCardValuation valuation;
  final AzamanColors colors;
  final ValueNotifier<bool>? flipGuard;
  final VoidCallback? onFlipBackRequested;

  @override
  State<BalanceCardBreakdown> createState() => _BalanceCardBreakdownState();
}

class _BalanceCardBreakdownState extends State<BalanceCardBreakdown> {
  final PageController _pageController = PageController(
    // 0.86 leaves a deliberate peek of the NEXT section's header at the
    // bottom of every page — the affordance that more sections exist.
    viewportFraction: 0.86,
  );

  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_Section> _sections(BalanceCardValuation v, AzamanColors colors) {
    final sections = <_Section>[
      _Section(
        key: const ValueKey('bc-section-available'),
        title: 'AVAILABLE',
        indicatorIcon: HugeIconsSolid.wallet01,
        indicatorSemantic: 'Available',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('AVAILABLE', colors),
            _BreakdownRow(
              key: const ValueKey('bc-row-ghs-wallet'),
              showDivider: true,
              label: 'GHS wallet',
              icon: HugeIconsSolid.wallet01,
              iconSemantic: 'GHS wallet icon',
              // No native-GHS wallet exists on the current contract:
              // unknown renders as a dash, never as GH₵ 0.00.
              amount: v.nativeGhsAvailable != null
                  ? AzMoney.amount(v.nativeGhsAvailable!)
                  : '—',
              unit: '',
              colors: colors,
              detail: v.nativeGhsAvailable == null
                  ? 'no GHS wallet on the current contract'
                  : null,
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
          ],
        ),
      ),
      _Section(
        key: const ValueKey('bc-section-committed'),
        title: 'COMMITTED',
        indicatorIcon: HugeIconsSolid.shield01,
        indicatorSemantic: 'Committed',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('COMMITTED', colors),
            _BreakdownRow(
              key: const ValueKey('bc-row-vaults'),
              showDivider: true,
              label: 'Vaults',
              icon: HugeIconsSolid.shield01,
              iconSemantic: 'Vault shield icon',
              amount: v.vaultLocked != null
                  ? AzMoney.amount(v.vaultLocked!)
                  : '—',
              unit: v.vaultLocked != null ? 'USDC' : '',
              colors: colors,
            ),
            _BreakdownRow(
              key: const ValueKey('bc-row-savings'),
              showDivider: true,
              label: 'Savings',
              icon: HugeIconsSolid.piggyBank,
              iconSemantic: 'Savings piggy bank icon',
              // The savings goal is GHS-denominated (SavingsGoal
              // .currentAmountGhs). Explicit GHS unit — never USDC.
              amount: v.savingsLockedGhs != null
                  ? AzMoney.amount(v.savingsLockedGhs!)
                  : '—',
              unit: v.savingsLockedGhs != null ? 'GHS' : '',
              colors: colors,
            ),
            _BreakdownRow(
              key: const ValueKey('bc-row-susu'),
              label: 'Susu',
              icon: HugeIconsSolid.userGroup,
              iconSemantic: 'Susu group icon',
              // Unknown (still loading / failed fetch) is a DASH, never
              // a zero: unknown must not read as 'nothing'.
              amount: v.susuCommitted != null
                  ? AzMoney.amount(v.susuCommitted!)
                  : '—',
              unit: v.susuCommitted != null ? 'USDC' : '',
              colors: colors,
              detail: v.susuCommitted == null ? 'not loaded yet' : null,
            ),
          ],
        ),
      ),
      _Section(
        key: const ValueKey('bc-section-locked'),
        title: 'LOCKED',
        indicatorIcon: HugeIconsSolid.lock,
        indicatorSemantic: 'Locked',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('LOCKED', colors),
            _BreakdownRow(
              key: const ValueKey('bc-row-escrow'),
              showDivider: true,
              label: 'Escrow',
              icon: HugeIconsSolid.lock,
              iconSemantic: 'Escrow lock icon',
              amount: AzMoney.amount(v.escrowLocked),
              unit: 'USDC',
              colors: colors,
            ),
            _BreakdownRow(
              key: const ValueKey('bc-row-dispute-escrow'),
              label: 'Dispute escrow',
              icon: HugeIconsSolid.shieldUser,
              iconSemantic: 'Dispute escrow shield icon',
              amount: AzMoney.amount(v.disputeEscrow),
              unit: 'USDC',
              colors: colors,
            ),
          ],
        ),
      ),
      // Vendor is present ONLY when the account is a vendor — the
      // section list reflects the real account, never padded.
      if (v.vendorRowRelevant)
        _Section(
          key: const ValueKey('bc-section-vendor'),
          title: 'VENDOR',
          indicatorIcon: HugeIconsSolid.store01,
          indicatorSemantic: 'Vendor',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('VENDOR', colors),
              _BreakdownRow(
                key: const ValueKey('bc-row-vendor'),
                label: 'Vendor balance',
                icon: HugeIconsSolid.store01,
                iconSemantic: 'Vendor storefront icon',
                amount: AzMoney.amount(v.vendorUnallocatedUsdc),
                unit: 'USDC',
                colors: colors,
                // Truthful, capability-free description: the backend
                // publishes no eligibility field, and withdrawability is
                // never inferred from the amount.
                detail: 'unallocated · restricted',
              ),
            ],
          ),
        ),
      _Section(
        key: const ValueKey('bc-section-noncash'),
        title: 'NON-CASH',
        indicatorIcon: HugeIconsSolid.flash,
        indicatorSemantic: 'Non-cash',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('NON-CASH', colors),
            _BreakdownRow(
              key: const ValueKey('bc-row-azm-points'),
              label: 'AZM points',
              icon: HugeIconsSolid.flash,
              iconSemantic: 'AZM points icon',
              // Never money: excluded from every monetary total, FX
              // calculation and rail.
              amount: AzMoney.amount(v.azmPoints, decimals: 0),
              unit: 'pts',
              colors: colors,
            ),
          ],
        ),
      ),
    ];
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.valuation;
    final colors = widget.colors;
    final sections = _sections(v, colors);

    // Clamp the remembered page if the section list shrank (e.g. the
    // vendor role changed) so the pager never points past the end.
    if (_page >= sections.length) _page = sections.length - 1;

    return Padding(
      key: const ValueKey('balance-fx-breakdown-card'),
      padding: const EdgeInsets.fromLTRB(
        AzSpace.lg,
        AzSpace.sm,
        AzSpace.lg,
        AzSpace.xs,
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
              if (widget.onFlipBackRequested != null)
                FlipGuardMarker(
                  flipGuard: widget.flipGuard,
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
                          onPressed: widget.onFlipBackRequested,
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
          // ── The section pager: one section per step, with the next
          // section's header peeking at the bottom of every page.
          Expanded(
            child: PageView(
              key: const ValueKey('bc-section-pager'),
              controller: _pageController,
              scrollDirection: Axis.vertical,
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final section in sections)
                  Padding(
                    // The section's own key rides the pager child — the
                    // ordered children list is the testable contract of
                    // the section sequence.
                    key: section.key,
                    padding: const EdgeInsets.only(bottom: AzSpace.xxs),
                    child: section.child,
                  ),
              ],
            ),
          ),
          // ── Section-ICON indicator: smaller and quieter than the row
          // icons, the active section emphasized, siblings subdued. The
          // full accessible statement rides on the strip.
          Semantics(
            key: const ValueKey('bc-section-indicator'),
            label:
                'Section ${_page + 1} of ${sections.length}: '
                '${sections[_page].indicatorSemantic}',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      sections[i].indicatorIcon,
                      key: ValueKey('bc-section-indicator-$i'),
                      size: i == _page ? 14 : 11,
                      color: i == _page
                          ? colors.textPrimary
                          : colors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
