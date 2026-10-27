// =============================================================================
// AZAMAN — BALANCE CARD (FX-STATUS FRONT FACE)
//
// FRONT LAYOUT (owner-corrected 2026-10-26 — GHS headline dominant, as
// the live main card's rhythm, never USDC-first):
//
//   AVAILABLE BALANCE
//   ≈ GH₵ 1,234.56           ← the dominant headline; the ≈ marks it
//                               APPROXIMATE whenever the total includes
//                               a converted USDC component (the current
//                               live contract: the whole figure is a
//                               converted display valuation). A
//                               genuinely native-GHS-only total renders
//                               exact, without ≈ (Workstream J2).
//   ≈  102.79 USDC    ⓘ     ← the USDC EQUIVALENT, the estimate — the
//                               ≈ marks this line; the ⓘ renders
//                               whenever this line renders (its
//                               disclosure wording is state-aware: the
//                               converted-valuation explanation in the
//                               current contract, the fallback-rate
//                               explanation on saved/demo rates)
//   [••• Updating rate…]            [refresh]
//
// The two amount lines share ONE leading gutter column and ONE
// unit-label column, so their digits sit in a clean vertical
// alignment. The ≈ marks the GHS headline whenever it includes a
// converted USDC component, and always marks the USDC line — both are
// estimates of the other's frame, never exact holdings of both. The visual
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
    this.flipGuard,
  });

  /// The typed valuation the card renders.
  final BalanceCardValuation valuation;

  /// Theme colours (pure widget — no provider watch).
  final AzamanColors colors;

  /// The shared frame's nested-gesture guard. Marked on pointer-down by
  /// this face's interactive affordances (the disclosure button) so
  /// operating them never also flips the card.
  final ValueNotifier<bool>? flipGuard;

  String _observedAtLabel() {
    final at = valuation.rate.observedAt;
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)} UTC';
  }

  /// The honest, STATE-AWARE disclosure for the figures on this card.
  ///
  /// Three contract states, each phrased so the user can never mistake a
  /// converted GHS display valuation for a native GHS wallet holding:
  ///   • fresh rate, no native-GHS wallet on the contract (the CURRENT
  ///     live state — backend PR #367 unmerged): the GH₵ figure is a
  ///     display valuation converted from the real USDC holding;
  ///   • fresh rate, native wallet present (future contract): the
  ///     total honestly combines the native holding with converted
  ///     USDC;
  ///   • saved/demo fallback rate: the existing indicative wording.
  String _disclosureBody() {
    final v = valuation;
    final rate = v.rate;
    final observed = _observedAtLabel();
    final source = rate.sourceLabel;

    if (rate.isFallback) {
      final isDemo = rate.kind == FxRateKind.demo;
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
      if (source != null && source.isNotEmpty) {
        buffer.write(', source: $source');
      }
      if (observed.isNotEmpty) buffer.write(', observed $observed');
      // Workstream J2: phrased narrowly — a display rate is not an
      // executable quote, and FX-dependent FLOWS may be unavailable
      // while a valid quote cannot be obtained. No blanket claim about
      // a universal USDC gate (backend #368's architecture is still
      // under review), and no authorization behaviour changes here.
      buffer.write(
        '. This is not a live rate, and a display rate is not an '
        'executable quote. Flows that require fresh FX or conversion '
        'may be unavailable while a valid quote cannot be obtained.',
      );
      return buffer.toString();
    }

    // Fresh rate — distinguish converted display valuation from native.
    final buffer = StringBuffer();
    if (v.nativeGhsAvailable == null) {
      buffer
        ..write(
          'Your available balance is held in USDC. The GH₵ figure is an '
          'approximate GHS display valuation converted from your USDC '
          'at the current rate',
        )
        ..write(' (${AzMoney.ghs(rate.ghsPerUsdc ?? 0)} per USDC)');
      if (source != null && source.isNotEmpty) {
        buffer.write(', source: $source');
      }
      if (observed.isNotEmpty) buffer.write(', observed $observed');
      buffer.write(
        '. It is not a native GHS wallet holding: no native-GHS wallet or '
        'combined valuation total is published by the backend yet. This '
        'conversion is not a guaranteed execution rate or a firm quote.',
      );
    } else {
      buffer
        ..write(
          'Your available total is approximate: it combines your native '
          'GHS wallet (${AzMoney.ghs(v.nativeGhsAvailable!)}) with your '
          'USDC converted at the current rate',
        )
        ..write(' (${AzMoney.ghs(rate.ghsPerUsdc ?? 0)} per USDC)');
      if (source != null && source.isNotEmpty) {
        buffer.write(', source: $source');
      }
      if (observed.isNotEmpty) buffer.write(', observed $observed');
      buffer.write(
        '. This is not a guaranteed execution rate or a firm quote.',
      );
    }
    return buffer.toString();
  }

  /// The disclosure trigger's semantic label — state-aware like the body.
  String _disclosureLabel() {
    if (valuation.rate.isFallback) {
      return 'About the USDC equivalent and saved rate';
    }
    return valuation.nativeGhsAvailable == null
        ? 'About the GHS valuation and USDC equivalent'
        : 'About the available balance breakdown';
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
      // WORKSTREAM J3 — the loading state is announced as LOADING, never
      // left as a bare 'GH₵' + dots artefact a screen reader cannot
      // classify.
      headline = Semantics(
        label: 'Available balance is loading',
        child: Row(
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
        ),
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
        // Workstream J2: the headline carries the ≈ whenever its total
        // includes a converted USDC component (nativeGhsAvailable == null
        // on the current contract — the whole figure is a converted
        // display valuation; a future native+USDC combined total also
        // converts). ONLY a genuinely native-GHS-only total renders
        // exact. GHS stays visually dominant; the marker is honesty,
        // never a redesign of the financial backend. The gutter column
        // stays so both lines' digits stay aligned.
        approx: v.headlineIncludesConvertedUsdc,
        // The semantics follow the visual state exactly (Workstream J2):
        // a total with a converted USDC component is announced as an
        // APPROXIMATE GHS display valuation — never a guaranteed GHS
        // amount or a native holding. Only a genuinely native-GHS-only
        // total keeps the exact 'in GHS' language.
        semanticsLabel: v.headlineIncludesConvertedUsdc
            ? (v.nativeGhsAvailable == null
                  ? 'Approximately ${AzMoney.ghs(v.availableGhsValue!)} — '
                        'a GHS display valuation converted from USDC at '
                        'the current rate, not a native GHS wallet holding'
                  : 'Approximately ${AzMoney.ghs(v.availableGhsValue!)} — '
                        'combines your native GHS wallet with USDC '
                        'converted at the current rate')
            : 'Available balance '
                  '${AzMoney.ghs(v.availableGhsValue!)} in GHS',
      );
    } else {
      // Confirmed balance, but the combined GHS value is not computable
      // (no usable rate, no native GHS wallet). Honest dash — never a
      // fabricated GH₵ 0.00, never USDC relabelled as GHS.
      // WORKSTREAM J3 — the unavailable state is announced as
      // UNAVAILABLE: no usable rate and no native GHS total published.
      // It must never read as a zero balance or a loading state.
      headline = Semantics(
        label:
            'Available balance in GHS is unavailable — no usable '
            'exchange rate',
        child: Row(
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
        ),
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
          // not by the GHS headline, not at the right edge. It is
          // visible whenever this line renders: in the CURRENT contract
          // state the GHS figure is a converted display valuation and
          // the disclosure says exactly that; on fallback rates it
          // explains the saved/demo rate.
          ...[
            const SizedBox(width: AzSpace.xs),
            FlipGuardMarker(
              flipGuard: flipGuard,
              child: _DisclosureIconButton(
                onTap: () => _showDisclosure(context),
                semanticLabel: _disclosureLabel(),
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
    // CONTENT INSET — AzSpace.md (12), not lg (16): the equivalent line's
    // disclosure control carries the full 44 x 44 dp accessibility touch
    // target, and the fixed 165px footprint must hold the headline, the
    // 44px equivalent row and the pinned rate row at the pair's 1.25x
    // text-scale clamp on every supported width (320dp included). The
    // denser inset buys that target without shrinking any glyph.
    return Padding(
      key: const ValueKey('balance-fx-card'),
      padding: const EdgeInsets.all(AzSpace.md),
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
          // ONE left-side status cluster: the animated dots and the
          // 'Updating rate…' caption live adjacent to the idle rate text
          // in this same slot. There is deliberately NO right-hand
          // status: the rate refresh is a passive background fact, and
          // the card never presents a second, competing status row —
          // nor anything that reads as a refresh ACTION (the rate
          // refreshes itself in the background; it is not user-armed).
          Align(
            key: const ValueKey('balance-fx-rate-row'),
            alignment: Alignment.centerLeft,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: rateStatus,
            ),
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
        // State-aware like the disclosure body itself: fresh-rate states
        // describe a converted display valuation, fallback states the
        // saved/demo rate.
        message: semanticLabel,
        // HIT TARGET CONTRACT: the control's effective touch target is the
        // full 44 x 44 dp mobile accessibility target (WCAG 2.5.8 /
        // Material), with the VISUAL glyph kept small (16px). shrinkWrap
        // keeps Material's extra default padding from inflating the
        // target further; the explicit 44px minimum is the target, and
        // the pair's internal 1.25x text-scale clamp guarantees the
        // resulting 44px row fits the fixed 165px card footprint at
        // every supported width and text scale (48px did not: it
        // overflowed the card at 1.25x+ scales).
        child: Theme(
          data: Theme.of(
            context,
          ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: IconButton(
            key: const ValueKey('balance-fx-equivalent-info'),
            onPressed: onTap,
            icon: Icon(
              HugeIconsSolid.informationCircle,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ),
      ),
    );
  }
}

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
