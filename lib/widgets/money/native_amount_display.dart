// =============================================================================
// AZAMAN — NATIVE AMOUNT DISPLAY (personal + business money surfaces)
//
// ONE honest renderer for an amount whose NATIVE denomination is USDC.
//
// ── THE CONTRACT THIS FILE ENFORCES (Workstream D1/D2) ───────────────────────
//
// The stored amount is the amount of record. A USDC-denominated record has NO
// GHS principal, and GHS settlement is not authorised by the backend plan v3.
// So a GHS figure next to it can only ever be one of three things, and the
// renderer must say WHICH one:
//
//   1. a RECORDED historical GHS equivalent (`recordedGhs`, optionally with
//      `recordedRate` persisted at initiation) — a quote captured when the
//      record was made, NOT a GHS principal and NOT evidence that anything
//      settled in GHS. It is shown as "recorded", never as an "estimate",
//      and NEVER re-derived from today's rate;
//   2. a LIVE conversion at the fresh oracle rate — always labelled
//      "current estimate", i.e. explicitly NOT payable value;
//   3. nothing — when no usable rate exists, the native amount stands alone
//      and the equivalence is named unavailable. It is never fabricated.
//
// ── WHY PURE FUNCTIONS ───────────────────────────────────────────────────────
// The strings and the ordering decision are produced by [resolveNativeAmount],
// a pure function with no Flutter dependency, so the financial-truth battery
// (ordering, missing/stale rate, recorded-history behaviour) tests the real
// arithmetic rather than a widget tree.
//
// ── WHAT THIS FILE MUST NEVER DO ─────────────────────────────────────────────
// • never mutate, round or re-denominate the native amount for storage;
//   `NativeAmountDisplay` is display-only and writes nothing.
// • never call today's rate a historical amount;
// • never claim a GHS settlement on a USDC rail.
//
// Conversion is delegated to the #165 currency services (`CurrencyMath` +
// `FxRateSnapshot` + `CurrencyPrefs`); this file adds NO second rate source
// and NO second conversion path.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/utils/currency_math.dart';

/// The honest decomposition of one native-USDC amount into what may be shown.
enum EquivalenceKind {
  /// A GHS amount persisted with the record itself (`recordedGhs`).
  recorded,

  /// A live conversion at the current fresh oracle rate.
  currentEstimate,

  /// Nothing may be shown — no recorded GHS amount and no usable rate.
  unavailable,
}

/// A resolved, ready-to-render pair of strings plus the honest label.
@immutable
class ResolvedNativeAmount {
  const ResolvedNativeAmount({
    required this.primary,
    required this.secondary,
    required this.inlineLead,
    required this.inlineTail,
    required this.kind,
    required this.semanticsLabel,
  });

  /// The figure that leads, per the display preference.
  final String primary;

  /// The supporting line: the other denomination, or the unavailable notice.
  final String secondary;

  /// The one-line composition: the leading figure WITH its caveat, then the
  /// remaining denomination. Both parts are ALWAYS visible on screen — the
  /// inline variant never shows an unlabeled GHS conversion, and it never
  /// shows a GHS figure without the native USDC amount beside it.
  final String inlineLead;

  /// The trailing part of the one-line form (may be the unavailable notice).
  /// Empty when the caller explicitly asked to omit the equivalent line.
  final String inlineTail;

  final EquivalenceKind kind;

  /// Full spoken truth for assistive tech — includes the estimate caveat that
  /// the compact visual form abbreviates.
  final String semanticsLabel;

  /// True when a GHS figure is on screen as a live estimate (never payable).
  bool get isEstimate => kind == EquivalenceKind.currentEstimate;
}

/// The single source of truth for a native-USDC amount's presentation.
///
/// [amountUsdc] is the amount of record and is used verbatim — the display
/// preference and the rate availability change ONLY which figure leads and
/// what the second line says. They can never change the amount.
///
/// [recordedGhs] is a historical GHS equivalent persisted with the record at
/// initiation (with an approved GHS settlement contract it could someday be a
/// real GHS principal; the backend plan v3 does not authorise that yet). It
/// wins outright over a live conversion: no estimate is computed for it and
/// it is labelled "recorded", never "estimate". Showing it never implies that
/// the record settled in GHS.
///
/// [forceNative] keeps the native USDC amount leading regardless of the
/// display preference — for same-unit comparisons (current vs target), where
/// a converted figure in one slot would silently mix denominations.
ResolvedNativeAmount resolveNativeAmount({
  required double amountUsdc,
  required DisplayCurrency preference,
  FxRateSnapshot? snapshot,
  DateTime? now,
  double? recordedGhs,
  String nativeSuffix = '',
  bool forceNative = false,
}) {
  final native = '${AzMoney.amount(amountUsdc)} USDC$nativeSuffix';
  final ghsFirst = preference == DisplayCurrency.ghs && !forceNative;

  // ── Case 1: a recorded historical GHS equivalent persisted at initiation.
  if (recordedGhs != null && recordedGhs.isFinite && recordedGhs >= 0) {
    final ghs = AzMoney.ghs(recordedGhs);
    const recordedLabel = 'recorded equivalent';
    if (ghsFirst) {
      return ResolvedNativeAmount(
        primary: ghs,
        secondary: '$native · native amount',
        inlineLead: '$ghs ($recordedLabel)',
        inlineTail: native,
        kind: EquivalenceKind.recorded,
        semanticsLabel:
            '$ghs recorded historical GHS equivalent, $native native amount.',
      );
    }
    return ResolvedNativeAmount(
      primary: native,
      secondary: '$ghs · $recordedLabel',
      inlineLead: native,
      inlineTail: '$ghs ($recordedLabel)',
      kind: EquivalenceKind.recorded,
      semanticsLabel: '$native. $ghs recorded historical GHS equivalent.',
    );
  }

  // ── Case 2/3: no recorded GHS amount. A live estimate, or nothing. ────────
  final at = now ?? DateTime.now().toUtc();
  final hasUsableRate = snapshot != null && snapshot.isUsableAt(at) && snapshot.ghsPerUsdc > 0;

  if (!hasUsableRate) {
    // Fail honest: the native amount stands, the equivalence is NAMED.
    return ResolvedNativeAmount(
      primary: native,
      secondary: 'GHS equivalent unavailable',
      inlineLead: native,
      inlineTail: 'GHS equivalent unavailable',
      kind: EquivalenceKind.unavailable,
      semanticsLabel:
          '$native. GHS equivalent unavailable: no current rate is usable.',
    );
  }

  final ghsValue = CurrencyMath.convert(
    amount: amountUsdc,
    from: CurrencyCatalog.usdc,
    to: CurrencyCatalog.ghs,
    ghsPerUsdc: snapshot.ghsPerUsdc,
  );
  if (ghsValue == null) {
    return ResolvedNativeAmount(
      primary: native,
      secondary: 'GHS equivalent unavailable',
      inlineLead: native,
      inlineTail: 'GHS equivalent unavailable',
      kind: EquivalenceKind.unavailable,
      semanticsLabel:
          '$native. GHS equivalent unavailable: no current rate is usable.',
    );
  }

  final estimate = AzMoney.ghs(ghsValue);
  if (ghsFirst) {
    return ResolvedNativeAmount(
      primary: estimate,
      secondary: 'current estimate · $native',
      inlineLead: '$estimate (estimate)',
      inlineTail: native,
      kind: EquivalenceKind.currentEstimate,
      semanticsLabel:
          '$estimate, a current estimate converted from $native. Not a settled '
          'GHS amount.',
    );
  }

  return ResolvedNativeAmount(
    primary: native,
    secondary: '≈ $estimate · current estimate',
    inlineLead: native,
    inlineTail: '≈ $estimate (estimate)',
    kind: EquivalenceKind.currentEstimate,
    semanticsLabel:
        '$native. A current estimate of approximately $estimate. '
        'Not a settled GHS amount.',
  );
}

/// Inline variant for tiles, list rows and receipt lines.
///
/// Renders the FULL truth on one line: the lead figure, its caveat when the
/// figure is an estimate or a recorded equivalent, and the other denomination.
/// A GHS conversion is never shown without the word "estimate"; the native
/// USDC amount is never dropped from the visible text.
///
/// [forceNative] keeps USDC leading even under a GHS preference — use it for
/// same-unit comparison slots (current vs target) so a converted figure can
/// never mix denominations inside one comparison.
///
/// [showEquivalent] omits the second part entirely (native amount alone) for
/// ultra-compact slots (rails, deposit rows) where a conversion would only
/// get truncated — an omitted estimate is honest; a truncated one is not.
class NativeAmountText extends ConsumerWidget {
  const NativeAmountText({
    super.key,
    required this.amountUsdc,
    this.recordedGhs,
    this.snapshotOverride,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.forceNative = false,
    this.showEquivalent = true,
  });

  final double amountUsdc;
  final double? recordedGhs;

  /// Test/preview seam: pins one rate instead of watching the live provider.
  final FxRateSnapshot? snapshotOverride;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final bool forceNative;
  final bool showEquivalent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(currencyProvider);
    final colors = ref.watch(themeProvider).colors;
    final snapshot =
        snapshotOverride ?? ref.watch(fxRateProvider).valueOrNull;

    final resolved = resolveNativeAmount(
      amountUsdc: amountUsdc,
      preference: preference,
      snapshot: snapshot,
      recordedGhs: recordedGhs,
      forceNative: forceNative,
    );

    final base = (style ??
            TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ))
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    final tail = resolved.inlineTail;
    final hasTail = showEquivalent && tail.isNotEmpty;

    return Semantics(
      label: resolved.semanticsLabel,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: resolved.inlineLead,
          style: base,
          children: hasTail
              ? [
                  TextSpan(
                    text: ' · $tail',
                    style: base.copyWith(
                      fontWeight: FontWeight.w600,
                      color: (base.color ?? colors.textPrimary)
                          .withValues(alpha: 0.72),
                    ),
                  ),
                ]
              : null,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      ),
    );
  }
}

/// Stacked variant for panels, detail summaries and confirmations: the lead
/// figure, then the honest supporting line underneath.
class NativeAmountDisplay extends ConsumerWidget {
  const NativeAmountDisplay({
    super.key,
    required this.amountUsdc,
    this.recordedGhs,
    this.snapshotOverride,
    this.primaryStyle,
    this.secondaryStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.forceNative = false,
  });

  final double amountUsdc;
  final double? recordedGhs;
  final FxRateSnapshot? snapshotOverride;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final CrossAxisAlignment crossAxisAlignment;
  final bool forceNative;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(currencyProvider);
    final colors = ref.watch(themeProvider).colors;
    final snapshot =
        snapshotOverride ?? ref.watch(fxRateProvider).valueOrNull;

    final resolved = resolveNativeAmount(
      amountUsdc: amountUsdc,
      preference: preference,
      snapshot: snapshot,
      recordedGhs: recordedGhs,
      forceNative: forceNative,
    );

    final primary = (primaryStyle ??
            TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ))
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final secondary = (secondaryStyle ??
            TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ))
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return Semantics(
      label: resolved.semanticsLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(resolved.primary, style: primary),
          const SizedBox(height: 2),
          Text(
            resolved.secondary,
            style: secondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The amount-entry companion: the field itself keeps submitting the NATIVE
/// denomination (USDC — the only rail the current contracts settle), and this
/// line quietly states the live GHS reading of what is typed.
///
/// This is deliberately NOT a currency wheel. A wheel on an editable amount
/// would imply the chosen unit is the authoritative principal, and the
/// reviewed GHS-authority backend contract that would make that true does not
/// exist yet (plan v3 is design-only). Display, not authority — see the
/// Workstream D1 notes in the planning document.
class AmountEntryEquivalent extends ConsumerWidget {
  const AmountEntryEquivalent({
    super.key,
    required this.amountUsdc,
    this.snapshotOverride,
    this.railNote = 'entered and settled in USDC',
  });

  final double amountUsdc;
  final FxRateSnapshot? snapshotOverride;
  final String railNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final snapshot =
        snapshotOverride ?? ref.watch(fxRateProvider).valueOrNull;

    final at = DateTime.now().toUtc();
    final usable = snapshot != null &&
        snapshot.isUsableAt(at) &&
        snapshot.ghsPerUsdc > 0;

    final String estimate;
    if (!usable || amountUsdc <= 0) {
      estimate = 'GHS equivalent unavailable';
    } else {
      final ghs = CurrencyMath.convert(
        amount: amountUsdc,
        from: CurrencyCatalog.usdc,
        to: CurrencyCatalog.ghs,
        ghsPerUsdc: snapshot.ghsPerUsdc,
      );
      estimate = ghs != null
          ? '≈ ${AzMoney.ghs(ghs)} · current estimate'
          : 'GHS equivalent unavailable';
    }

    final visible =
        railNote.isEmpty ? estimate : '$estimate · $railNote';

    return Semantics(
      label: 'Amount is $railNote. $estimate.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text(
          visible,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
