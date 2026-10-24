// =============================================================================
// AZAMAN — BALANCE CARD PREVIEW (DEMO)
//
// Workstream E preview surface for the redesigned BalanceCardPair (#185's
// contract-seam components). This section exists ONLY so the owner can see
// and interact with the new card in the running app BEFORE the backend
// valuation contract (AZM-backend PR #367 — GET /api/users/balance with the
// additive data.valuation block) is live and adapted.
//
// HONESTY CONTRACT (non-negotiable):
//   • It renders ONLY in demo builds (AppConfig.demoMode) — real-account
//     Home behaviour is untouched and keeps the existing live card.
//   • It is EXPLICITLY labelled a preview with FIXTURE data. The numbers
//     below are illustrative fixtures, never read from (or written to) any
//     real balance source, and are never presented as real account funds.
//   • The FX rate is a FIXED DEMO rate (FxRateKind.demo) — display-only,
//     labelled "Demo rate (seeded)" by the front face, never a live or
//     guaranteed quote. No exchange rate is guessed or fetched.
//   • The USDC transaction gate stays CLOSED (usdcTransactionGateOpen:
//     false) — every transaction affordance stays fail-closed; the preview
//     never unlocks a real action.
//
// When the backend contract lands, the production adapter replaces this
// fixture with the authoritative response and the preview section is
// removed along with the old card.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/widgets/home/balance_card_pair.dart';

/// The fixture valuation the preview renders — an arbitrary, clearly
/// synthetic example covering every presentation state of the card pair:
/// GHS headline + USDC equivalent, a DEMO-kind rate, each locked rail,
/// the Susu unknown, the vendor restricted row and AZM points. Gate closed.
///
/// The values are deliberately modest: the pair's front face does not yet
/// scale 4-digit combined headlines into its fixed 165dp frame at 320dp
/// (a card defect tracked in PR #185 — surfaced by this preview work), so
/// the fixture stays within the proven 320–390dp envelope.
BalanceCardValuation _previewFixture() {
  return const BalanceCardValuation(
        nativeGhsAvailable: 484.50,
        availableUsdc: 10.00,
        balanceConfirmed: true,
        escrowLocked: 90.00,
        disputeEscrow: 25.00,
        vaultLocked: 180.00,
        susuCommitted: null, // unknown — renders the honest dash
        savingsLockedGhs: 1200.00,
        vendorUnallocatedUsdc: 3.00,
        vendorRowRelevant: true,
        azmPoints: 1450,
        rate: FxRateView(
          ghsPerUsdc: 15.80,
          kind: FxRateKind.demo,
          sourceLabel: 'Demo seed rate',
        ),
        usdcTransactionGateOpen: false,
      )
      .compute();
}

/// The labelled demo/preview home section. [visible] is injected (Home passes
/// AppConfig.demoMode) so the widget tests can pin both states without a
/// process-global demo-mode override; production Home decides visibility.
class BalanceCardPreviewSection extends StatelessWidget {
  const BalanceCardPreviewSection({
    super.key,
    required this.colors,
    this.visible = false,
  });

  final AzamanColors colors;
  final bool visible;

  static const String previewLabel = 'Balance card preview';
  static const String demoTag = 'DEMO';
  static const String fixtureCaption =
      'Fixture data — not real funds';

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // ── The explicit preview label — never implied, never skippable ──
        Row(
          children: [
            Text(
              previewLabel.toUpperCase(),
              semanticsLabel: previewLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.warning,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                demoTag,
                semanticsLabel: '$demoTag fixture data',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: colors.background,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          fixtureCaption,
          style: TextStyle(
            fontSize: 10,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        // ── The previewed card pair, fed ONLY the fixture valuation ──
        BalanceCardPair(
          valuation: _previewFixture(),
          colors: colors,
        ),
      ],
    );
  }
}
