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
// ARITHMETIC (owner-corrected product contract, 2026-10-27):
//   availableGhsValue       = nativeGhsAvailable        — the AUTHORITATIVE
//     native-GHS balance ONLY, verbatim from the backend's documented
//     field. NEVER derived from USDC, NEVER combined with it.
//   availableUsdcEquivalent = availableGhsValue / displayRate — a
//     DISPLAY estimate converted FROM that GHS balance, marked ≈.
// Actual USDC held ([availableUsdc]) is a SEPARATE concept: it never
// feeds the GHS headline and never feeds the equivalent calculation.
// It appears only as its own fact (the back-face "USDC held" row).
// [BalanceCardValuation.compute] implements exactly this: it maps the
// native-GHS balance through verbatim and derives ONLY the equivalent
// estimate from it. A widget NEVER recalculates a valuation from a
// separately sourced rate; it renders what it is given.
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
  /// Actual native GHS available (the GHS wallet). NULL when the current
  /// backend contract publishes no native-GHS wallet at all — the absence
  /// of the wallet is not a GH₵ 0.00 holding, and the breakdown row must
  /// render unknown, never zero.
  final double? nativeGhsAvailable;

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

  /// Committed vault total (USDC). NULL when the vault list has not
  /// loaded or its fetch failed — unknown must never render as a zero.
  final double? vaultLocked;

  /// Committed Susu total. Null when the susu list has not loaded or its
  /// fetch failed — unknown must never render as a zero.
  final double? susuCommitted;

  /// PARSED-ONLY on the card this release (K2B-2): the aggregate of
  /// ACTIVE/PAUSED SavingsGoal.currentAmountGhs (backend valuation:
  /// locked.savingsGhs). Four distinct meanings, never conflated:
  ///   1. the NOMINAL GHS amount recorded toward savings goals,
  ///   2. the actual USDC the deposits moved into escrow accounting
  ///      (the backend debits availableBalance and increments
  ///      escrowLockedBalance in USDC while incrementing the goal in
  ///      GHS — savingsController),
  ///   3. a current GHS display valuation of those USDC assets (it
  ///      changes with the rate),
  ///   4. a guaranteed/promised GHS payout (none on the contract).
  /// This figure is #1 only — it is NOT native GHS held, NOT a
  /// guaranteed value, and never implies GHS spendability or
  /// withdrawability. The balance-card breakdown therefore renders it
  /// UNKNOWN (—) while the K2B-2 display gate is closed
  /// (kCardDisplaysSavingsAggregate); the Savings screen keeps the
  /// factual goal progress under its own contract. The GHS-suffixed
  /// name still exists so a cross-currency mapping error fails loudly
  /// at the call site. NULL when the savings overview has not loaded
  /// or its fetch failed — unknown, never zero.
  final double? savingsLockedGhs;

  // NOTE (contract gap, deliberate): there is NO savings-withdrawable
  // field. The backend balance valuation does not publish a verified
  // withdrawable amount, and withdrawability must never be derived from
  // the savings total. When an authoritative field is contracted it will
  // arrive typed and GHS-denominated (e.g. savingsWithdrawableGhs); until
  // then the UI keeps that detail absent — not fabricated, not zero.

  /// Vendor/unallocated balance, when relevant (vendor role). USDC
  /// units — matches the backend field locked.vendorUnallocatedUsdc.
  final double vendorUnallocatedUsdc;

  /// Whether the vendor row applies to this account. There is
  /// deliberately NO eligibility/withdrawability flag: the backend does
  /// not publish one, withdrawability is never inferred from the amount,
  /// and an omitted field is never read as a confirmed status. The row
  /// describes the balance as unallocated and restricted — nothing more.
  final bool vendorRowRelevant;

  // ── Non-cash ──────────────────────────────────────────────────────────
  /// AZM loyalty points. Never money: excluded from every monetary rail
  /// and from all totals.
  final double azmPoints;

  // ── FX + valuation ─────────────────────────────────────────────────────
  final FxRateView rate;

  /// The AUTHORITATIVE native-GHS available balance — the GHS headline,
  /// verbatim from the backend's documented field (the wallet balance in
  /// the app's MAIN currency). NEVER includes a converted USDC component
  /// and NEVER derives from USDC in any way. Null means the backend
  /// published no authoritative native-GHS balance: the card presents
  /// the honest unavailable state (never a derived figure, never a
  /// fabricated GH₵ 0.00).
  final double? availableGhsValue;

  /// The approximate USDC EQUIVALENT of [availableGhsValue] — a display
  /// estimate converted FROM the GHS balance at the display rate, marked
  /// ≈ on the card. Null when the GHS headline is unknown or no usable
  /// rate exists. This is an EQUIVALENT — it must be labelled as one and
  /// never read as USDC actually held (the real holding is the separate
  /// [availableUsdc]).
  final double? availableUsdcEquivalent;

  /// Whether USDC-enabled transactions are allowed, per the backend gate.
  /// Frontend presentation follows this contract; it is never derived from
  /// a frontend clock or a cached boolean.
  final bool usdcTransactionGateOpen;

  const BalanceCardValuation({
    this.nativeGhsAvailable,
    this.availableUsdc = 0,
    this.balanceConfirmed = false,
    this.escrowLocked = 0,
    this.disputeEscrow = 0,
    this.vaultLocked,
    this.susuCommitted,
    this.savingsLockedGhs,
    this.vendorUnallocatedUsdc = 0,
    this.vendorRowRelevant = false,
    this.azmPoints = 0,
    this.rate = const FxRateView(),
    this.availableGhsValue,
    this.availableUsdcEquivalent,
    this.usdcTransactionGateOpen = false,
  });

  /// Applies the owner-corrected valuation contract (2026-10-27):
  ///   • the GHS headline maps the AUTHORITATIVE native-GHS balance
  ///     through VERBATIM — USDC held never enters it, whatever the rate;
  ///   • the USDC equivalent is the display estimate converted FROM that
  ///     GHS balance (ghs / displayRate), and exists ONLY when both the
  ///     native-GHS balance and a usable rate exist — otherwise it is
  ///     honestly unavailable (null), never a fabricated zero.
  /// A widget renders [availableGhsValue]/[availableUsdcEquivalent] and
  /// never recalculates.
  BalanceCardValuation compute() {
    final ghs = nativeGhsAvailable;
    final r = rate.hasRate ? rate.ghsPerUsdc! : null;
    final usdcEquiv = ghs != null && r != null ? ghs / r : null;
    return BalanceCardValuation(
      nativeGhsAvailable: nativeGhsAvailable,
      availableUsdc: availableUsdc,
      balanceConfirmed: balanceConfirmed,
      escrowLocked: escrowLocked,
      disputeEscrow: disputeEscrow,
      vaultLocked: vaultLocked,
      susuCommitted: susuCommitted,
      savingsLockedGhs: savingsLockedGhs,
      vendorUnallocatedUsdc: vendorUnallocatedUsdc,
      vendorRowRelevant: vendorRowRelevant,
      azmPoints: azmPoints,
      rate: rate,
      availableGhsValue: ghs,
      availableUsdcEquivalent: usdcEquiv,
      usdcTransactionGateOpen: usdcTransactionGateOpen,
    );
  }

  /// The headline can only be shown as a confirmed combined value.
  bool get headlineKnown => balanceConfirmed && availableGhsValue != null;



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
          other.savingsLockedGhs == savingsLockedGhs &&
          other.vendorUnallocatedUsdc == vendorUnallocatedUsdc &&
          other.vendorRowRelevant == vendorRowRelevant &&
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
    savingsLockedGhs,
    vendorUnallocatedUsdc,
    vendorRowRelevant,
    azmPoints,
    rate,
    availableGhsValue,
    availableUsdcEquivalent,
    usdcTransactionGateOpen,
  ]);
}
