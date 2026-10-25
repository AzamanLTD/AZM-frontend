// =============================================================================
// AZAMAN — BALANCE CARD (FX-STATUS FRONT FACE)
// Final Balance Card Redesign: the front is ALWAYS GHS-first. There is no
// currency toggle on this card and the global display preference cannot
// switch it to a USDC-primary layout.
//
// LAYOUT (front):
//   AVAILABLE BALANCE
//   GH₵ 1,234.56                     ← combined available value (GHS)
//   ≈ 102.79 USDC equivalent  ⓘ     ← overall equivalent + info icon when
//                                        a saved/demo fallback rate is shown
//   1 USDC ≈ GH₵ 12.03 · Using saved rate      [refresh]
//
// STATE LAWS (product contract):
//   • Balance readiness and FX readiness are SEPARATE states. FX loading
//     never replaces a known available-balance amount; the FX dots live
//     ONLY in the bottom-left rate row, and only while a request is
//     genuinely in progress with NO eligible saved fallback already shown.
//   • While a saved/demo fallback is displayed, a refresh keeps that value
//     and status in place — no dots.
//   • Fresh rate: no stale-rate warning. Saved/demo: explicit fallback
//     identification in the rate row plus an information disclosure
//     (touch, keyboard and screen-reader accessible) stating the rate is
//     indicative, not a live/guaranteed execution rate or firm quote.
//   • No rate and no eligible fallback: a STABLE unavailable state. If
//     available USDC cannot be valued, the combined GHS valuation is
//     presented as incomplete — the known native GHS amount stays visible
//     but is never presented alone as the total.
//   • The widget is PURE: it renders the typed valuation it is given and
//     never recalculates a valuation from a separately sourced rate. It
//     is not yet wired into the Home screen — the backend valuation
//     contract is pending and the wiring adapter lands with it.
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

    // ── Headline ──────────────────────────────────────────────────────
    // The combined available value in GHS. A known amount is NEVER
    // replaced by FX state: FX readiness and balance readiness are
    // separate, and only the BALANCE placeholder may occupy this slot.
    final Widget headline;
    if (v.balanceConfirmed) {
      final ghs = v.availableGhsValue;
      if (ghs != null) {
        headline = _FittedHeadline(
          key: const ValueKey('balance-fx-headline'),
          semanticsLabel: 'Available balance ${AzMoney.ghs(ghs)}',
          amount: AzMoney.amount(ghs),
          colors: colors,
        );
      } else {
        // Confirmed balance, but the combined value is not computable.
        // The known native GHS amount must remain visible — presented
        // WITH an explicit incomplete-valuation note, never alone as the
        // total.
        headline = _FittedHeadline(
          key: const ValueKey('balance-fx-headline-native'),
          semanticsLabel:
              'GHS wallet ${AzMoney.ghs(v.nativeGhsAvailable)} — the '
              'combined value is unavailable',
          amount: AzMoney.amount(v.nativeGhsAvailable),
          colors: colors,
        );
      }
    } else {
      // Balance readiness placeholder — three dots for the still-loading
      // BALANCE. FX state never occupies this slot.
      headline = FxTypingDots(
        key: const ValueKey('balance-fx-amount-dots'),
        color: colors.textPrimary,
      );
    }

    final valuationIncomplete = v.valuationIncomplete;

    // ── USDC equivalent ──────────────────────────────────────────────
    final Widget? equivalent;
    if (!v.balanceConfirmed) {
      equivalent = null;
    } else if (v.availableUsdcEquivalent != null) {
      equivalent = Row(
        key: const ValueKey('balance-fx-equivalent-row'),
        children: [
          Flexible(
            child: Text.rich(
              key: const ValueKey('balance-fx-equivalent'),
              TextSpan(
                text: '≈ ${AzMoney.amount(v.availableUsdcEquivalent!)} USDC',
                semanticsLabel:
                    'USDC equivalent of the available balance, '
                    '${AzMoney.amount(v.availableUsdcEquivalent!)} USDC — '
                    'an equivalent, not USDC held',
                // E1: the squiggly ≈ already SAYS 'equivalent' — the
                // trailing word is dropped from the visual line; the
                // semantics label keeps the honest full explanation.
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
    } else {
      // When the equivalent is unavailable the incomplete NOTE above
      // already states exactly that, in user terms — a second caption
      // would only repeat the same sentence inside a fixed footprint.
      equivalent = null;
    }

    // ── Bottom-left FX rate/status ───────────────────────────────────
    // Dots appear here ONLY while genuinely loading without an eligible
    // fallback already shown. A displayed saved/demo value is kept in
    // place while a refresh runs — never swapped for dots.
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
      // E1 — ONE coherent updating row: the dots and the 'Updating
      // rate…' caption read as a single status in the SAME slot the
      // rate occupies when idle, so nothing on the card moves between
      // the loading and idle states.
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
    // fixed footprint; the rate row pins flush to the card's bottom edge
    // (the same proportions as the live Home card), and nothing here can
    // influence the card's layout size.
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
          headline,
          // The middle block lives in the REMAINING space of the fixed
          // footprint: whatever the FX state renders (the incomplete
          // note, the equivalent row), it can never push the rate row
          // past the card's bottom edge — the note caps at two lines and
          // the rate row stays pinned flush to the bottom.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (valuationIncomplete) ...[
                  const SizedBox(height: AzSpace.sm),
                  Text(
                    'GHS wallet only — the combined value with the USDC '
                    'held cannot be shown without a valid FX rate',
                    key: const ValueKey('balance-fx-valuation-incomplete'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AzText.bodyS.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (equivalent != null) ...[
                  const SizedBox(height: AzSpace.sm),
                  equivalent,
                ],
              ],
            ),
          ),
          // The rate/status row spans the card: status anchored bottom
          // LEFT, the refresh affordance flush RIGHT.
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

// E2 — THE ONE-LINE RESPONSIVE HEADLINE.
//
// The PR #190 review documented the defect: a 4-digit combined headline
// ("GH₵ 5,234.50"-scale) wraps and overflows the fixed 165px frame at
// 320dp. The fix is the CAUSE, not the fixture: the headline is a single
// typographic line (subordinate GH₵ marker + hero digits, E1) laid out at
// its NATURAL size and scaled down ONLY as much as the card width demands
// (FittedBox scaleDown, bounded to the card's interior width). At 320dp a
// 4-digit figure still reads large; nothing is pre-shrunk and nothing is
// ever unreadable. The rate row is pinned by the frame's fixed footprint
// and never competes with the headline for space.
class _FittedHeadline extends StatelessWidget {
  const _FittedHeadline({
    super.key,
    required this.amount,
    required this.colors,
    required this.semanticsLabel,
  });

  /// The pre-formatted digit string (no currency marker — the marker is
  /// rendered as its own subordinate span).
  final String amount;
  final AzamanColors colors;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text.rich(
          semanticsLabel: semanticsLabel,
          maxLines: 1,
          TextSpan(
            // E1 — the GH₵ marker is SMALLER + subordinate to the
            // digits: the amount is the hero, the currency marker is a
            // quiet label beside it (never part of the giant block).
            text: '${AzMoney.ghsSymbol}${AzMoney.nbsp}',
            style: AzText.money(
              colors.textSecondary,
              size: 16,
              weight: FontWeight.w600,
              tracking: 0,
            ),
            children: [
              TextSpan(
                text: amount,
                style: AzText.money(
                  colors.textPrimary,
                  size: AzText.sizeHero,
                  weight: FontWeight.w700,
                  tracking: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
