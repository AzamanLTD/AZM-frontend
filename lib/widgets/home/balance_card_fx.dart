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
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/fx_typing_dots.dart';

/// The redesigned Home balance card front face.
class BalanceCardFx extends StatelessWidget {
  const BalanceCardFx({
    super.key,
    required this.valuation,
    required this.colors,
    this.trailingRefresh,
  });

  /// The typed valuation the card renders.
  final BalanceCardValuation valuation;

  /// Theme colours (pure widget — no provider watch).
  final AzamanColors colors;

  /// The right-edge refresh affordance (the card's width contract pins it
  /// flush right, e.g. the Home wiring passes the live RateRefreshIndicator).
  final Widget? trailingRefresh;

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
        headline = Text(
          AzMoney.ghs(ghs),
          key: const ValueKey('balance-fx-headline'),
          semanticsLabel: 'Available balance ${AzMoney.ghs(ghs)}',
          style: AzText.money(
            colors.textPrimary,
            size: AzText.sizeHero,
            weight: FontWeight.w700,
          ),
        );
      } else {
        // Confirmed balance, but the combined value is not computable.
        // The known native GHS amount must remain visible — presented
        // WITH an explicit incomplete-valuation note, never alone as the
        // total.
        headline = Column(
          key: const ValueKey('balance-fx-headline-block'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AzMoney.ghs(v.nativeGhsAvailable),
              key: const ValueKey('balance-fx-headline-native'),
              semanticsLabel:
                  'GHS wallet ${AzMoney.ghs(v.nativeGhsAvailable)} — the '
                  'combined value is unavailable',
              style: AzText.money(
                colors.textPrimary,
                size: AzText.sizeHero,
                weight: FontWeight.w700,
              ),
            ),
          ],
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
                style: AzText.money(
                  colors.textSecondary,
                  size: 16,
                  weight: FontWeight.w600,
                  tracking: 0,
                ),
                children: const [
                  TextSpan(
                    text: ' equivalent',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          // The information icon sits IMMEDIATELY BESIDE the equivalent —
          // not by the GHS headline, not at the right edge by refresh.
          if (rate.isFallback) ...[
            const SizedBox(width: AzSpace.xs),
            _DisclosureIconButton(
              onTap: () => _showDisclosure(context),
              semanticLabel: 'About the USDC equivalent and saved rate',
            ),
          ],
        ],
      );
    } else if (valuationIncomplete) {
      equivalent = Text(
        'USDC equivalent unavailable — no valid FX rate',
        key: const ValueKey('balance-fx-equivalent-unavailable'),
        style: AzText.bodyS.copyWith(color: colors.textSecondary),
      );
    } else {
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
      rateStatus = SizedBox(
        height: 12 * 1.45,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FxTypingDots(
            key: const ValueKey('balance-fx-rate-dots'),
            color: colors.textSecondary,
          ),
        ),
      );
    } else {
      rateStatus = Text(
        'FX rate unavailable',
        key: const ValueKey('balance-fx-rate-unavailable'),
        style: AzText.caption.copyWith(color: colors.textTertiary),
      );
    }

    return Container(
      key: const ValueKey('balance-fx-card'),
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
            'AVAILABLE BALANCE',
            key: const ValueKey('balance-fx-label'),
            style: AzText.eyebrow.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AzSpace.sm),
          headline,
          if (valuationIncomplete) ...[
            const SizedBox(height: AzSpace.xs),
            Text(
              'GHS wallet only — the combined value with the USDC held '
              'cannot be shown without a valid FX rate',
              key: const ValueKey('balance-fx-valuation-incomplete'),
              style: AzText.bodyS.copyWith(color: colors.textSecondary),
            ),
          ],
          if (equivalent != null) ...[
            const SizedBox(height: AzSpace.xs),
            equivalent,
          ],
          const SizedBox(height: AzSpace.sm),
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
                Semantics(
                  key: const ValueKey('balance-fx-refresh-slot'),
                  label: 'Refresh FX rate',
                  child: trailingRefresh!,
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
