// =============================================================================
// AZAMAN — BALANCE CARD VALUATION VIEW-MODEL
// Final Balance Card Redesign (FX status + icon-based breakdown).
//
// CONTRACT SEAM — the authoritative balance/valuation API is being defined
// by the backend agent. Until the agreed schema is published, NOTHING in
// this file is wired to a production endpoint, and the Home card keeps its
// current provider wiring. This view-model is the typed frontend contract
// the redesigned widget renders: every field maps to a field the backend
// contract will own (native GHS available, available USDC held, separate
// locked amounts, canonical rate status, saved fallback rate, demo seed
// status, display-valuation basis, available-GHS total, overall USDC
// equivalent, USDC transaction gate). When the schema lands, an adapter
// translates the response into [BalanceCardValuation] and the tests are
// updated to the final field names — nothing in the widget changes.
//
// ARITHMETIC (valuation semantics, per the agreed product definition):
//   availableGhsValue     = nativeGhsAvailable + (availableUsdc * displayRate)
//   availableUsdcEquivalent = availableGhsValue / displayRate
// The backend's returned valuation is AUTHORITATIVE for the presented
// summary. [BalanceCardValuation.compute] implements the same formula for
// test fixtures and for the interim state where the backend does not yet
// return precomputed totals — a widget NEVER recalculates a valuation from
// a separately sourced rate; it renders what it is given.
//
// FX REVALUATION IS NOT FUNDS MOVEMENT — changing the rate changes the GHS
// valuation of the USDC component ONLY. It must never mutate a ledger
// balance, produce a deposit/withdrawal delta notification, or be presented
// as a transaction. The view-model therefore carries the rate purely as
// presentation data; there is no delta or movement channel in this model.
// =============================================================================

import 'package:flutter/foundation.dart';

/// How the displayed FX rate was obtained.
enum FxRateKind {
  /// A current canonical rate, genuinely fresh.
  fresh,

  /// The last saved validated rate, used as an eligible fallback while no
  /// fresh rate exists. Indicative only.
  saved,

  /// The demo-seeded fallback rate. Marked by the backend as a demo seed,
  /// never a real market observation.
  demo,

  /// No usable rate at all — fresh or fallback.
  none,
}

/// The FX rate presentation state for the card.
@immutable
class FxRateView {
  /// The display rate (GHS per USDC) when one exists. Null when none.
  final double? ghsPerUsdc;

  /// Provenance of the displayed rate.
  final FxRateKind kind;

  /// Whether an FX request is genuinely in progress right now.
  final bool loading;

  /// Honest provenance label when the backend provides one (e.g. the
  /// observation source). Null when unavailable.
  final String? sourceLabel;

  /// When this rate was observed (saved rate observation time, or the
  /// fresh observation time). Null when the backend does not return one.
  final DateTime? observedAt;

  const FxRateView({
    this.ghsPerUsdc,
    this.kind = FxRateKind.none,
    this.loading = false,
    this.sourceLabel,
    this.observedAt,
  });

  /// A rate is present only with a positive finite value.
  bool get hasRate =>
      ghsPerUsdc != null && ghsPerUsdc! > 0 && ghsPerUsdc!.isFinite;

  /// The saved-fallback states (saved or demo) — both are indicative-only
  /// and both require the information disclosure.
  bool get isFallback => kind == FxRateKind.saved || kind == FxRateKind.demo;

  /// Fresh means fresh — no stale-rate warning may be shown in this state.
  bool get isFresh => kind == FxRateKind.fresh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxRateView &&
          other.ghsPerUsdc == ghsPerUsdc &&
          other.kind == kind &&
          other.loading == loading &&
          other.sourceLabel == sourceLabel &&
          other.observedAt == observedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    ghsPerUsdc,
    kind,
    loading,
    sourceLabel,
    observedAt,
  ]);
}

/// The typed view-model the redesigned balance card renders.
@immutable
class BalanceCardValuation {
  // ── Available assets ───────────────────────────────────────────────────
  /// Actual native GHS available (the GHS wallet).
  final double nativeGhsAvailable;

  /// Actual liquid USDC held. This is a REAL holding; it is never the same
  /// number as the USDC equivalent of the GHS total.
  final double availableUsdc;

  /// Whether the balance figures are confirmed (backend readiness). An
  /// unconfirmed balance renders the loading placeholder, never a
  /// fabricated 0.00.
  final bool balanceConfirmed;

  // ── Locked or committed (separate fields, never merged) ────────────────
  final double escrowLocked;
  final double disputeEscrow;
  final double vaultLocked;

  /// Committed Susu total. Null when the susu list has not loaded or its
  /// fetch failed — unknown must never render as a zero.
  final double? susuCommitted;

  /// Savings total as held (locked). Withdrawability is separate.
  final double savingsLocked;

  /// The specific net savings amount currently withdrawable after all
  /// restrictions and penalties, when the backend provides it. Null when
  /// it does not — a null means savings CANNOT be included in the front
  /// headline, never that it counts as zero.
  final double? savingsWithdrawable;

  /// Vendor/unallocated balance, when relevant (vendor role).
  final double vendorUnallocated;

  /// Whether the vendor row applies to this account, and whether the
  /// unallocated amount is withdrawable. Vendor funds are INELIGIBLE for
  /// the headline unless the backend confirms immediate withdrawability.
  final bool vendorRowRelevant;
  final bool vendorUnallocatedEligible;

  // ── Non-cash ──────────────────────────────────────────────────────────
  /// AZM loyalty points. Never money: excluded from every monetary rail
  /// and from all totals.
  final double azmPoints;

  // ── FX + valuation ─────────────────────────────────────────────────────
  final FxRateView rate;

  /// The backend-authoritative combined available value in GHS, when it
  /// could be computed (backend-returned, or the honest derivation in
  /// [compute]). Null means the combined valuation is NOT available — the
  /// card must present an incomplete-valuation state, never native GHS
  /// alone masquerading as the total.
  final double? availableGhsValue;

  /// The overall USDC equivalent of the entire available GHS value.
  /// Null when no valid valuation rate exists. This is an EQUIVALENT —
  /// it must be labelled as one and never read as USDC actually held.
  final double? availableUsdcEquivalent;

  /// Whether USDC-enabled transactions are allowed, per the backend gate.
  /// Frontend presentation follows this contract; it is never derived from
  /// a frontend clock or a cached boolean.
  final bool usdcTransactionGateOpen;

  const BalanceCardValuation({
    this.nativeGhsAvailable = 0,
    this.availableUsdc = 0,
    this.balanceConfirmed = false,
    this.escrowLocked = 0,
    this.disputeEscrow = 0,
    this.vaultLocked = 0,
    this.susuCommitted,
    this.savingsLocked = 0,
    this.savingsWithdrawable,
    this.vendorUnallocated = 0,
    this.vendorRowRelevant = false,
    this.vendorUnallocatedEligible = false,
    this.azmPoints = 0,
    this.rate = const FxRateView(),
    this.availableGhsValue,
    this.availableUsdcEquivalent,
    this.usdcTransactionGateOpen = false,
  });

  /// Applies the agreed valuation semantics to derive the presentation
  /// totals. Used by test fixtures and by the interim derivation until the
  /// backend returns precomputed authoritative totals; a widget renders
  /// [availableGhsValue]/[availableUsdcEquivalent] and never recalculates.
  ///
  /// A combined GHS value exists when the USDC component is zero (native
  /// GHS alone is the whole total — no rate needed) or a valid rate exists.
  /// The USDC equivalent, however, ALWAYS needs a usable rate: with zero
  /// USDC held it is nativeGhsAvailable / rate, and without a usable rate it
  /// is honestly unavailable (null) — never a fabricated zero. With USDC
  /// held and no usable rate, the combined total itself is honestly
  /// unavailable (null) even though native GHS is known.
  BalanceCardValuation compute() {
    final hasUsdc = availableUsdc > 0;
    final r = rate.hasRate ? rate.ghsPerUsdc! : null;

    double? ghs;
    double? usdcEquiv;
    if (!hasUsdc) {
      ghs = nativeGhsAvailable;
      // hasRate guarantees a positive, finite rate.
      usdcEquiv = r != null ? nativeGhsAvailable / r : null;
    } else if (r != null) {
      ghs = nativeGhsAvailable + availableUsdc * r;
      usdcEquiv = ghs / r;
    }
    return BalanceCardValuation(
      nativeGhsAvailable: nativeGhsAvailable,
      availableUsdc: availableUsdc,
      balanceConfirmed: balanceConfirmed,
      escrowLocked: escrowLocked,
      disputeEscrow: disputeEscrow,
      vaultLocked: vaultLocked,
      susuCommitted: susuCommitted,
      savingsLocked: savingsLocked,
      savingsWithdrawable: savingsWithdrawable,
      vendorUnallocated: vendorUnallocated,
      vendorRowRelevant: vendorRowRelevant,
      vendorUnallocatedEligible: vendorUnallocatedEligible,
      azmPoints: azmPoints,
      rate: rate,
      availableGhsValue: ghs,
      availableUsdcEquivalent: usdcEquiv,
      usdcTransactionGateOpen: usdcTransactionGateOpen,
    );
  }

  /// The headline can only be shown as a confirmed combined value.
  bool get headlineKnown => balanceConfirmed && availableGhsValue != null;

  /// A known USDC holding that cannot be valued: the combined GHS valuation
  /// is incomplete and must be presented as such — native GHS alone may
  /// never appear to be the whole total.
  bool get valuationIncomplete =>
      balanceConfirmed &&
      availableGhsValue == null &&
      nativeGhsAvailable > 0 &&
      availableUsdc > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BalanceCardValuation &&
          other.nativeGhsAvailable == nativeGhsAvailable &&
          other.availableUsdc == availableUsdc &&
          other.balanceConfirmed == balanceConfirmed &&
          other.escrowLocked == escrowLocked &&
          other.disputeEscrow == disputeEscrow &&
          other.vaultLocked == vaultLocked &&
          other.susuCommitted == susuCommitted &&
          other.savingsLocked == savingsLocked &&
          other.savingsWithdrawable == savingsWithdrawable &&
          other.vendorUnallocated == vendorUnallocated &&
          other.vendorRowRelevant == vendorRowRelevant &&
          other.vendorUnallocatedEligible == vendorUnallocatedEligible &&
          other.azmPoints == azmPoints &&
          other.rate == rate &&
          other.availableGhsValue == availableGhsValue &&
          other.availableUsdcEquivalent == availableUsdcEquivalent &&
          other.usdcTransactionGateOpen == usdcTransactionGateOpen;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    nativeGhsAvailable,
    availableUsdc,
    balanceConfirmed,
    escrowLocked,
    disputeEscrow,
    vaultLocked,
    susuCommitted,
    savingsLocked,
    savingsWithdrawable,
    vendorUnallocated,
    vendorRowRelevant,
    vendorUnallocatedEligible,
    azmPoints,
    rate,
    availableGhsValue,
    availableUsdcEquivalent,
    usdcTransactionGateOpen,
  ]);
}
