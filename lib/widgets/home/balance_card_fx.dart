// =============================================================================
// AZAMAN — BALANCE CARD (FX-STATUS FRONT FACE)
//
// FRONT LAYOUT (owner-corrected 2026-10-26 — GHS headline dominant, as
// the live main card's rhythm, never USDC-first):
//
//   AVAILABLE BALANCE
//   GH₵ 1,234.56             ← the known combined value, dominant —
//                               it is NOT estimated, no ≈
//   ≈  102.79 USDC    ⓘ     ← the USDC EQUIVALENT, the estimate — the
//                               ≈ marks this line, info when a
//                               saved/demo fallback rate is displayed
//   [••• Updating rate…]            [refresh]
//
// The two amount lines share ONE leading gutter column and ONE
// unit-label column, so their digits sit in a clean vertical
// alignment. The ≈ renders ONLY on the USDC line — that is the line
// being estimated; the GHS headline is the known value. The visual
// USDC line never says the word "equivalent": ≈ already communicates
// the relationship; the full accessible semantics keep the honest
// explanation (an equivalent calculation, not necessarily USDC
// actually held).
//
// STATE LAWS (product contract):
//   • Balance readiness and FX readiness are SEPARATE states. FX loading
//     never replaces a known available-balance amount; the FX dots live
//     ONLY in the bottom-left rate cluster, and only while a request is
//     genuinely in progress with NO eligible saved fallback already shown.
//   • While a saved/demo fallback is displayed, a refresh keeps that value
//     and status in place — no dots.
//   • Fresh rate: no stale-rate warning. Saved/demo: explicit fallback
//     identification in the rate row plus the information disclosure
//     beside the USDC line (touch, keyboard and screen-reader
//     accessible) stating the rate is indicative, not a live/guaranteed
//     execution rate or firm quote.
//   • No rate and no eligible fallback: a STABLE unavailable state. With
//     no native GHS wallet on the current contract the headline renders
//     an honest dash, the REAL USDC holding still shows beneath it (it
//     is a fact, not a conversion), and the rate row says the rate is
//     unavailable. Never a fabricated GH₵ 0.00.
//   • The widget is PURE: it renders the typed valuation it is given and
//     never recalculates a valuation from a separately sourced rate.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/fx_typing_dots.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart'
    show FlipGuardMarker;

/// The leading gutter column shared by BOTH amount lines. The ≈ glyph
/// renders in it ONLY on the USDC line (the estimate); on the GHS
/// headline the slot stays empty — keeping the digits aligned.
const double kApproxGutter = 16;

/// The fixed unit-label column width: "GH₵" and "USDC" labels share it so
/// the digit blocks of the two lines align vertically.
const double kUnitColumn = 46;

/// The headline's amount size — the live main card's hero rhythm
/// (AzText.money, w600, tabular figures) scaled to the pair card's 165dp
/// footprint with the secondary line beneath.
const double _kHeadlineSize = AzText.sizeHero;

/// The redesigned Home balance card front face.
class BalanceCardFx extends StatelessWidget {
  const BalanceCardFx({
    super.key,
    required this.valuation,
    required this.colors,
    this.trailingRefresh,
    this.flipGuard,
  });

  /// The typed valuation the card renders.
  final BalanceCardValuation valuation;

  /// Theme colours (pure widget — no provider watch).
  final AzamanColors colors;

  /// The right-edge refresh affordance (the card's width contract pins it
  /// flush right, e.g. the Home wiring passes the live RateRefreshIndicator).
  final Widget? trailingRefresh;

  /// The shared frame's nested-gesture guard. Marked on pointer-down by
  /// this face's interactive affordances (the disclosure button, the
  /// refresh slot) so operating them never also flips the card.
  final ValueNotifier<bool>? flipGuard;

  String _observedAtLabel() {
    final at = valuation.rate.observedAt;
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)} UTC';
  }

  /// The honest disclosure for a saved/demo fallback rate.
  String _disclosureBody() {
    final rate = valuation.rate;
    final isDemo = rate.kind == FxRateKind.demo;
    final observed = _observedAtLabel();
    final source = rate.sourceLabel;
    final buffer = StringBuffer()
      ..write(
        'The current FX rate is unavailable, so this USDC figure is an '
        'indicative display calculation',
      );
    if (isDemo) {
      buffer.write(' using a demo-seeded rate — not a real market feed');
    } else {
      buffer.write(' using the last saved validated rate');
    }
    buffer.write(' (${AzMoney.ghs(rate.ghsPerUsdc ?? 0)} per USDC)');
    if (source != null && source.isNotEmpty) buffer.write(', source: $source');
    if (observed.isNotEmpty) buffer.write(', observed $observed');
    buffer.write(
      '. This is not a live rate, a guaranteed execution rate or a firm '
      'quote. USDC-enabled transactions are unavailable until a fresh rate '
      'is restored.',
    );
    return buffer.toString();
  }

  Future<void> _showDisclosure(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('balance-fx-fallback-disclosure'),
        title: const Text('About this USDC figure'),
        content: Text(
          _disclosureBody(),
          key: const ValueKey('balance-fx-fallback-disclosure-body'),
        ),
        actions: [
          TextButton(
            key: const ValueKey('balance-fx-fallback-disclosure-close'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = valuation;
    final rate = v.rate;
    final hasRate = rate.hasRate;

    // ── Headline: the combined available value in GHS (dominant) ───────
    // Balance readiness and FX readiness are separate: only the BALANCE
    // placeholder may occupy this slot — never an FX state, and never a
    // fabricated 0.00.
    final Widget headline;
    if (!v.balanceConfirmed) {
      headline = Row(
        key: const ValueKey('balance-fx-headline-loading'),
        children: [
          const SizedBox(width: kApproxGutter, child: SizedBox.shrink()),
          SizedBox(
            width: kUnitColumn,
            child: Text(
              'GH₵',
              style: AzText.label.copyWith(color: colors.textTertiary),
            ),
          ),
          FxTypingDots(
            key: const ValueKey('balance-fx-amount-dots'),
            color: colors.textPrimary,
          ),
        ],
      );
    } else if (v.availableGhsValue != null) {
      headline = _AmountLine(
        key: const ValueKey('balance-fx-headline'),
        unit: 'GH₵',
        amount: AzMoney.amount(v.availableGhsValue!),
        amountStyle: AzText.money(
          colors.textPrimary,
          size: _kHeadlineSize,
          weight: FontWeight.w600,
          tracking: 0,
        ),
        unitStyle: AzText.label.copyWith(color: colors.textTertiary),
        // The GHS headline is the KNOWN combined value — the ≈ glyph
        // belongs on the USDC line below, which is the estimate. The
        // gutter column stays so both lines' digits stay aligned.
        approx: false,
        semanticsLabel: 'Available balance '
            '${AzMoney.ghs(v.availableGhsValue!)} in GHS',
      );
    } else {
      // Confirmed balance, but the combined GHS value is not computable
      // (no usable rate, no native GHS wallet). Honest dash — never a
      // fabricated GH₵ 0.00, never USDC relabelled as GHS.
      headline = Row(
        key: const ValueKey('balance-fx-headline-unavailable'),
        children: [
          const SizedBox(width: kApproxGutter, child: SizedBox.shrink()),
          SizedBox(
            width: kUnitColumn,
            child: Text(
              'GH₵',
              style: AzText.label.copyWith(color: colors.textTertiary),
            ),
          ),
          Text(
            '—',
            key: const ValueKey('balance-fx-headline-dash'),
            style: AzText.money(
              colors.textTertiary,
              size: _kHeadlineSize,
              weight: FontWeight.w600,
              tracking: 0,
            ),
          ),
        ],
      );
    }

    // ── Secondary line: the USDC equivalent (smaller) ────────────────────
    final Widget secondary;
    if (!v.balanceConfirmed) {
      // Keep the geometry stable while loading: same row, no value.
      secondary = SizedBox(
        key: const ValueKey('balance-fx-equivalent-loading'),
        height: 20,
        child: Row(
          children: [
            const SizedBox(width: kApproxGutter, child: SizedBox.shrink()),
            SizedBox(
              width: kUnitColumn,
              child: Text(
                'USDC',
                style: AzText.bodyS.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      );
    } else if (v.availableUsdcEquivalent != null) {
      secondary = Row(
        key: const ValueKey('balance-fx-equivalent-row'),
        children: [
          // The USDC line is the ESTIMATE — the ≈ marks it, in the same
          // shared gutter so the digits of both lines still align.
          SizedBox(
            width: kApproxGutter,
            child: Text(
              '≈',
              key: const ValueKey('balance-fx-equivalent-approx'),
              style: AzText.bodyS.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: kUnitColumn,
            child: Text(
              'USDC',
              style: AzText.bodyS.copyWith(color: colors.textTertiary),
            ),
          ),
          Flexible(
            child: Text.rich(
              key: const ValueKey('balance-fx-equivalent'),
              TextSpan(
                text: AzMoney.amount(v.availableUsdcEquivalent!),
                semanticsLabel:
                    '${AzMoney.amount(v.availableUsdcEquivalent!)} USDC — '
                    'the USDC equivalent of the available balance, an '
                    'equivalent calculation, not necessarily USDC held',
                // E1: the squiggly ≈ already SAYS 'equivalent' — no
                // trailing word on the visual line; the semantics label
                // keeps the honest full explanation.
                style: AzText.money(
                  colors.textSecondary,
                  size: 16,
                  weight: FontWeight.w600,
                  tracking: 0,
                ),
              ),
            ),
          ),
          // The information icon sits IMMEDIATELY BESIDE the equivalent —
          // not by the GHS headline, not at the right edge by refresh.
          if (rate.isFallback) ...[
            const SizedBox(width: AzSpace.xs),
            FlipGuardMarker(
              flipGuard: flipGuard,
              child: _DisclosureIconButton(
                onTap: () => _showDisclosure(context),
                semanticLabel: 'About the USDC equivalent and saved rate',
              ),
            ),
          ],
        ],
      );
    } else if (v.availableUsdc > 0) {
      // No usable rate: there is NO equivalent. The REAL USDC holding
      // still shows — it is a fact, not a conversion — and the leading
      // slot stays empty: ≈ would claim a relationship that does not
      // exist in this state.
      secondary = Row(
        key: const ValueKey('balance-fx-usdc-held-no-rate'),
        children: [
          const SizedBox(width: kApproxGutter, child: SizedBox.shrink()),
          SizedBox(
            width: kUnitColumn,
            child: Text(
              'USDC',
              style: AzText.bodyS.copyWith(color: colors.textTertiary),
            ),
          ),
          Text(
            AzMoney.amount(v.availableUsdc),
            key: const ValueKey('balance-fx-usdc-held-amount'),
            style: AzText.money(
              colors.textSecondary,
              size: 16,
              weight: FontWeight.w600,
              tracking: 0,
            ),
          ),
        ],
      );
    } else {
      secondary = const SizedBox(height: 20);
    }

    // ── Bottom-left FX rate/status cluster ─────────────────────────────
    // Dots appear here ONLY while genuinely loading without an eligible
    // fallback already shown. A displayed saved/demo value is kept in
    // place while a refresh runs — never swapped for dots. The dots and
    // the 'Updating rate…' caption form ONE adjacent cluster in the same
    // slot the rate occupies when idle.
    final Widget rateStatus;
    if (hasRate) {
      final suffix = switch (rate.kind) {
        FxRateKind.fresh =>
          rate.sourceLabel?.isNotEmpty == true ? ' · ${rate.sourceLabel}' : '',
        FxRateKind.saved => ' · Using saved rate',
        FxRateKind.demo => ' · Demo rate (seeded)',
        FxRateKind.none => '',
      };
      rateStatus = Text(
        '1 USDC ≈ ${AzMoney.ghs(rate.ghsPerUsdc!)}$suffix',
        key: ValueKey(switch (rate.kind) {
          FxRateKind.saved => 'balance-fx-rate-saved',
          FxRateKind.demo => 'balance-fx-rate-demo',
          _ => 'balance-fx-rate-fresh',
        }),
        style: AzText.caption.copyWith(color: colors.textTertiary),
      );
    } else if (rate.loading) {
      rateStatus = SizedBox(
        height: 12 * 1.45,
        child: Row(
          key: const ValueKey('balance-fx-rate-updating'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FxTypingDots(
              key: const ValueKey('balance-fx-rate-dots'),
              color: colors.textSecondary,
            ),
            const SizedBox(width: AzSpace.xs),
            Text(
              'Updating rate…',
              key: const ValueKey('balance-fx-rate-updating-label'),
              style: AzText.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    } else {
      rateStatus = Text(
        'FX rate unavailable',
        key: const ValueKey('balance-fx-rate-unavailable'),
        style: AzText.caption.copyWith(color: colors.textTertiary),
      );
    }

    // CONTENT ONLY — the shared frame (BalanceCardPair) owns the material,
    // corner radius, rim and edge. This face supplies content inside the
    // fixed footprint; the rate row pins flush to the card's bottom edge,
    // and nothing here can influence the card's layout size.
    return Padding(
      key: const ValueKey('balance-fx-card'),
      padding: const EdgeInsets.all(AzSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AVAILABLE BALANCE',
            key: const ValueKey('balance-fx-label'),
            style: AzText.eyebrow.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AzSpace.sm),
          // The dominant GHS line, scaled down only as much as the card
          // width demands (never pre-shrunk, never unreadable).
          FittedBox(
            key: const ValueKey('balance-fx-headline-fitted'),
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: headline,
          ),
          const SizedBox(height: AzSpace.xxs),
          secondary,
          // The middle block lives in the REMAINING space of the fixed
          // footprint so the rate row always stays pinned flush bottom.
          const Expanded(child: SizedBox.shrink()),
          Row(
            key: const ValueKey('balance-fx-rate-row'),
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: rateStatus,
                  ),
                ),
              ),
              const SizedBox(width: AzSpace.xs),
              if (trailingRefresh != null)
                FlipGuardMarker(
                  flipGuard: flipGuard,
                  child: Semantics(
                    key: const ValueKey('balance-fx-refresh-slot'),
                    label: 'Refresh FX rate',
                    child: trailingRefresh!,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Accessible disclosure trigger: a real button — focusable by keyboard,
/// operable by touch, labelled for screen readers.
class _DisclosureIconButton extends StatelessWidget {
  const _DisclosureIconButton({
    required this.onTap,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Tooltip(
        message: 'USDC equivalent uses a saved fallback rate — details',
        child: IconButton(
          key: const ValueKey('balance-fx-equivalent-info'),
          onPressed: onTap,
          icon: Icon(
            HugeIconsSolid.informationCircle,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
    );
  }
}

/// The dominant amount line of the front face:
/// [≈ gutter][unit label][amount]. The ≈ slot precedes the amount, and
/// both lines share the same gutter and unit-column widths so their
/// digits align vertically — the visual relationship the owner asked for.
class _AmountLine extends StatelessWidget {
  const _AmountLine({
    super.key,
    required this.unit,
    required this.amount,
    required this.unitStyle,
    required this.amountStyle,
    required this.semanticsLabel,
    this.approx = false,
  });

  final String unit;
  final String amount;
  final TextStyle unitStyle;
  final TextStyle amountStyle;
  final String semanticsLabel;

  /// Whether the leading ≈ glyph renders. False in states where the
  /// amount is NOT an approximation of the other line (loading, or the
  /// real USDC holding shown without a rate).
  final bool approx;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: kApproxGutter,
            child: approx
                ? Text(
                    '≈',
                    style: amountStyle.copyWith(
                      color: unitStyle.color,
                      fontSize: (amountStyle.fontSize ?? 16) * 0.66,
                    ),
                  )
                : null,
          ),
          SizedBox(
            width: kUnitColumn,
            child: Text(unit, style: unitStyle),
          ),
          const SizedBox(width: AzSpace.xs),
          Text(amount, style: amountStyle),
        ],
      ),
    );
  }
}
