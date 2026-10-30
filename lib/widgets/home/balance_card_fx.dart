// =============================================================================
// AZAMAN — BALANCE CARD (FX-STATUS FRONT FACE)
//
// FRONT LAYOUT (owner-corrected 2026-10-27 — GHS is the app's MAIN
// currency; the headline is exact, never USDC-first):
//
//   AVAILABLE BALANCE
//   GH₵ 1,234.56             ← the dominant headline — the canonical
//                               balance in GHS, the app's main currency.
//                               It is NEVER marked ≈: GHS is the money
//                               frame of record, not a derivation.
//   ≈  102.79 USDC    ⓘ     ← the USDC EQUIVALENT, the estimate — the
//                               ONLY line the ≈ marks. It is converted
//                               FROM the GHS balance at the display
//                               rate. The ⓘ renders whenever this line
//                               renders (its disclosure wording is
//                               state-aware: the equivalent-from-GHS
//                               explanation on a fresh rate, the
//                               fallback-rate explanation on saved/demo
//                               rates)
//   [••• Updating rate…]            [refresh]
//
// The two amount lines share ONE leading gutter column and ONE
// unit-label column, so their digits sit in a clean vertical
// alignment. The ≈ lives ONLY on the USDC line — the equivalent is
// the estimate; the GHS headline is the app's canonical figure and
// renders exact. The visual USDC line never says the word
// "equivalent": ≈ already communicates the relationship; the full
// accessible semantics keep the honest explanation (an equivalent
// calculation, not necessarily USDC actually held).
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
import 'package:azaman/widgets/home/money_privacy.dart';
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
/// (AzText.money, w600, tabular figures) scaled to the pair card's 180dp
/// footprint with the secondary line beneath.
const double _kHeadlineSize = AzText.sizeHero;

/// Fixed slots for the two scale-dependent text rows. With these reserved, the
/// front face's rows sum to a constant that always fits the measured safe area
/// (20 + 2 + 40 + 2 + 44 + 13 = 121 of the 124px available at a 180px card),
/// so the money block cannot overflow at ANY width or text scale — the content
/// that would grow scales DOWN inside its own slot instead of pushing the
/// column past the card edge.
const double _kLabelSlot = 20;
const double _kRateSlot = 13;

/// The redesigned Home balance card front face.
/// A figure the card may not show while money is locked. `vis` decides; the
/// caller has already formatted the value, and the mask replaces it wholesale.
String _money(MoneyVisibility vis, String formatted) =>
    vis.masked(() => formatted);

class BalanceCardFx extends StatelessWidget {
  const BalanceCardFx({
    super.key,
    required this.valuation,
    required this.colors,
    this.flipGuard,
    this.visibility = MoneyVisibility.visible,
  });

  /// The typed valuation the card renders.
  final BalanceCardValuation valuation;

  /// Theme colours (pure widget — no provider watch).
  final AzamanColors colors;

  /// The shared frame's nested-gesture guard. Marked on pointer-down by
  /// this face's interactive affordances (the disclosure button) so
  /// operating them never also flips the card.
  final ValueNotifier<bool>? flipGuard;

  /// Whether the member may see money right now. Redacted keeps the whole
  /// face — artwork, chip, gradients — and masks the figures.
  final MoneyVisibility visibility;

  MoneyVisibility get vis => visibility;

  String _observedAtLabel() {
    final at = valuation.rate.observedAt;
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)} UTC';
  }

  /// The honest, STATE-AWARE disclosure for the figures on this card.
  ///
  /// GHS is the app's MAIN currency: the GH₵ headline is the canonical
  /// balance figure and the USDC line is the EQUIVALENT derived from
  /// it — never the other way round. Two contract states:
  ///   • fresh rate: the USDC figure is the approximate equivalent of
  ///     the available GHS balance at the current rate;
  ///   • saved/demo fallback rate: the same equivalent explanation plus
  ///     the indicative-rate wording.
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
      buffer.write(
        ' (${_money(vis, AzMoney.ghs(rate.ghsPerUsdc ?? 0))} per USDC)',
      );
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

    // Fresh rate — GHS is the main currency; the USDC line is the
    // equivalent derived FROM the GHS balance, never GHS derived from
    // USDC.
    final buffer = StringBuffer()
      ..write(
        'Your available balance is shown in GH₵ — Azaman\u2019s main '
        'currency. The USDC figure is the approximate USDC equivalent '
        'of that balance, converted from it at the current rate',
      )
      ..write(' (${_money(vis, AzMoney.ghs(rate.ghsPerUsdc ?? 0))} per USDC)');
    if (source != null && source.isNotEmpty) {
      buffer.write(', source: $source');
    }
    if (observed.isNotEmpty) buffer.write(', observed $observed');
    buffer.write(
      '. It is an equivalent calculation, not necessarily USDC held, and '
      'this rate is not a guaranteed execution rate or a firm quote.',
    );
    return buffer.toString();
  }

  /// The disclosure trigger's semantic label — state-aware like the body.
  String _disclosureLabel() {
    if (valuation.rate.isFallback) {
      return 'About the USDC equivalent and saved rate';
    }
    return 'About the USDC equivalent';
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
        amount: _money(vis, AzMoney.amount(v.availableGhsValue!)),
        amountStyle: AzText.money(
          colors.textPrimary,
          size: _kHeadlineSize,
          weight: FontWeight.w600,
          tracking: 0,
        ),
        unitStyle: AzText.label.copyWith(color: colors.textTertiary),
        // GHS is the app's MAIN currency — the headline is the
        // canonical balance figure and NEVER carries the ≈. Only the
        // USDC equivalent line is an estimate (it is converted FROM
        // this GHS balance at the display rate). The shared gutter
        // column stays so both lines' digits stay aligned; the ≈
        // glyph itself renders only on the USDC line.
        approx: false,
        // The semantics follow the visual state exactly: the GHS
        // headline is announced as the available balance in GHS —
        // the app's main currency, never as a USDC-derived estimate.
        // The estimate language lives ONLY on the USDC line.
        semanticsLabel:
            'Available balance '
            '${_money(vis, AzMoney.ghs(v.availableGhsValue!))} in GHS',
      );
    } else {
      // Confirmed balance, but the backend published NO authoritative
      // native-GHS balance (the only source the headline may consume —
      // owner-corrected contract 2026-10-27). Honest dash — never a
      // fabricated GH₵ 0.00, never USDC-derived GHS.
      // WORKSTREAM J3 — the unavailable state is announced as
      // UNAVAILABLE. It must never read as a zero balance or a loading
      // state.
      headline = Semantics(
        label:
            'Available balance in GHS is unavailable — the backend '
            'published no authoritative GHS balance',
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
                text: _money(vis, AzMoney.amount(v.availableUsdcEquivalent!)),
                semanticsLabel:
                    '${_money(vis, AzMoney.amount(v.availableUsdcEquivalent!))} USDC — '
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
          // visible whenever this line renders: the USDC line is the
          // estimate (the equivalent converted from the GHS balance)
          // and the disclosure explains exactly that; on fallback rates
          // it also explains the saved/demo rate.
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
    } else {
      // No equivalent exists (no authoritative GHS balance, or no usable
      // rate): the estimate is honestly UNAVAILABLE in this slot. The
      // REAL USDC holding is a separate concept (owner-corrected
      // contract 2026-10-27) — it never sits in the estimate slot; it
      // shows on the back face as its own fact. The leading slot stays
      // empty: ≈ would claim a relationship that does not exist in this
      // state.
      secondary = Semantics(
        label:
            'The USDC equivalent is unavailable — the GHS balance or a '
            'usable exchange rate is missing',
        child: Row(
          key: const ValueKey('balance-fx-equivalent-unavailable'),
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
              '—',
              key: const ValueKey('balance-fx-equivalent-dash'),
              style: AzText.money(
                colors.textTertiary,
                size: 16,
                weight: FontWeight.w600,
                tracking: 0,
              ),
            ),
          ],
        ),
      );
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
      final rateWidget = Text(
        '1 USDC ≈ ${_money(vis, AzMoney.ghs(rate.ghsPerUsdc!))}$suffix',
        key: ValueKey(switch (rate.kind) {
          FxRateKind.saved => 'balance-fx-rate-saved',
          FxRateKind.demo => 'balance-fx-rate-demo',
          _ => 'balance-fx-rate-fresh',
        }),
        style: AzText.caption.copyWith(color: colors.textTertiary),
      );
      // REFRESH WITH A RATE ON SCREEN: the provider is truthfully
      // reporting an in-flight fetch while a usable rate is already
      // displayed (fxRateProvider keeps its previous value through an
      // invalidate/refresh). The valid rate STAYS visible — it is never
      // swapped for dots — and a compact updating indication appears
      // beside it in the SAME reserved slot, same cluster height as the
      // initial-fetch dots so nothing around the row reflows.
      rateStatus = rate.loading
          ? SizedBox(
              height: 12 * 1.45,
              child: Row(
                key: const ValueKey('balance-fx-rate-refreshing'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  rateWidget,
                  const SizedBox(width: AzSpace.sm),
                  Semantics(
                    label: 'Updating exchange rate',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FxTypingDots(
                          key: const ValueKey('balance-fx-rate-refresh-dots'),
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: AzSpace.xs),
                        Text(
                          'Updating…',
                          key: const ValueKey('balance-fx-rate-refresh-label'),
                          style: AzText.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : rateWidget;
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
    // target, and the fixed 180px footprint must hold the headline, the
    // 44px equivalent row and the pinned rate row at the pair's 1.25x
    // text-scale clamp on every supported width (320dp included). The
    // denser inset buys that target without shrinking any glyph.
    // NO PADDING OF ITS OWN: the painted card surface has already applied the
    // measured safe area (below the brand block, left of the chip), so the
    // money content can never cover the mark, the chip or the contour focal
    // point. This face owns only the vertical rhythm inside that area.
    return Column(
      key: const ValueKey('balance-fx-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THE LABEL SLOT IS FIXED, like the two money slots below it. The
        // eyebrow's line box grows with the platform text scale, and at the
        // pair's 1.25x clamp the four fixed rows summed to 125.7px inside a
        // 124px safe area — a 1.7px bottom overflow at every width. Reserving
        // a fixed 22px slot keeps the card's footprint data- and scale-stable:
        // the all-caps label scales down inside its slot when the platform
        // asks for more than it can give, and NOTHING below it moves.
        SizedBox(
          key: const ValueKey('balance-fx-label'),
          height: _kLabelSlot,
          width: double.infinity,
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              'AVAILABLE BALANCE',
              style: AzText.eyebrow.copyWith(color: colors.textTertiary),
            ),
          ),
        ),
        const SizedBox(height: AzSpace.xxs),
        // The dominant GHS line, scaled down only as much as the card
        // width demands (never pre-shrunk, never unreadable).
        //
        // PERMANENT SLOT: every headline state (value, loading dots,
        // unavailable dash) occupies the SAME fixed-height region — the
        // money style's own line height (_kHeadlineSize at height 1.0) —
        // so the secondary line below can never shift vertically when a
        // value is absent, loading or unavailable. The GHS headline is
        // the card's dominant region; its geometry is data-independent.
        SizedBox(
          key: const ValueKey('balance-fx-headline-slot'),
          height: _kHeadlineSize,
          width: double.infinity,
          child: FittedBox(
            key: const ValueKey('balance-fx-headline-fitted'),
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: headline,
          ),
        ),
        const SizedBox(height: AzSpace.xxs),
        // PERMANENT SLOT, same doctrine as the headline: the USDC line
        // occupies ONE fixed-height region (the equivalent row's own
        // 44dp accessibility-target height) in EVERY state — equivalent,
        // held-without-rate, balance-loading, empty — so the section's
        // geometry is data-independent and the rate row below never
        // moves. Content is center-aligned inside the region.
        SizedBox(
          key: const ValueKey('balance-fx-secondary-slot'),
          height: 44,
          width: double.infinity,
          child: Align(alignment: Alignment.centerLeft, child: secondary),
        ),
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
        // THE RATE SLOT IS FIXED TOO. Its line box is the one remaining
        // scale-dependent row: at 1.3x the caption grew the column to 3.4px
        // past the safe area. Reserving a fixed slot means the four rows below
        // the label sum to a CONSTANT, so the money block can never overflow
        // its 180px card at any width or text scale.
        SizedBox(
          key: const ValueKey('balance-fx-rate-row'),
          height: _kRateSlot,
          width: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: rateStatus,
            ),
          ),
        ),
      ],
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
        // explain the USDC equivalent, fallback states the saved/demo
        // rate.
        message: semanticLabel,
        // HIT TARGET CONTRACT: the control's effective touch target is the
        // full 44 x 44 dp mobile accessibility target (WCAG 2.5.8 /
        // Material), with the VISUAL glyph kept small (16px). shrinkWrap
        // keeps Material's extra default padding from inflating the
        // target further; the explicit 44px minimum is the target, and
        // the pair's internal 1.25x text-scale clamp guarantees the
        // resulting 44px row fits the fixed 180px card footprint at
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
