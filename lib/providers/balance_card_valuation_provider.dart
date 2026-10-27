// =============================================================================
// AZAMAN — BALANCE CARD VALUATION, PRODUCTION ADAPTER
//
// The single seam between the app's AUTHORITATIVE data providers and the
// typed BalanceCardValuation the redesigned main card renders. The widget
// never recalculates; this adapter is the only place production numbers
// enter the card.
//
// SOURCES OF TRUTH (all existing, all server-authoritative):
//   • balanceDataProvider / balanceReadinessProvider — the canonical USDC
//     ledger balance (availableBalance IS real USDC held) plus escrow,
//     dispute-escrow, vendor-unallocated and AZM-points fields.
//   • fxRateProvider — the canonical oracle snapshot. A rate is a rate
//     ONLY while snapshot.isUsable is true (the backend's full freshness
//     contract). There is NO saved/fallback rate store in the current
//     production stack: a rate that is not fresh is not displayed as a
//     rate at all — the card shows the honest unavailable/ updating
//     states. (The saved/demo FxRateView kinds exist for the backend
//     valuation contract, backend PR #367, still unmerged — they are
//     mapped here only when that contract actually lands.)
//   • vaultsProvider / savingsOverviewProvider / susuListProvider —
//     committed funds. While any of these lists is loading or failed,
//     the value is UNKNOWN (null): an empty loaded list is a real zero,
//     an unloaded list is not.
//
// CONTRACT GAP (honest): the current backend main publishes NO native
// GHS wallet and NO precomputed valuation totals (backend PR #367 is
// open). Therefore, while the balance response is LEGACY (no valuation
// block), nativeGhsAvailable is NULL (the GHS wallet row on the
// back face renders unknown, never GH₵ 0.00) and the combined GHS value
// is the honest interim derivation: (native ?? 0) + availableUsdc ×
// rate, applied ONLY while a usable rate exists — explicitly a
// DISPLAY-ONLY conversion, labelled as such in the disclosure and the
// screen-reader semantics.
//
// WHEN backend PR #367 SHIPS, the response carries `data.valuation` and
// this adapter consumes the strict typed parse of that exact contract
// (BackendBalanceValuation):
//   • valuation PRESENT + parses  → backend-authoritative everything:
//     native GHS, actual USDC held, the backend's own GHS total and USDC
//     equivalent (the card never recalculates), the backend's rate
//     status (CURRENT / SAVED_FALLBACK / DEMO_FALLBACK / UNAVAILABLE),
//     the AUTHORITATIVE usdcTransactionGateOpen verbatim, and the
//     locked.* buckets (committedSusuUsdc is PARSED for contract
//     compatibility but NOT displayed — see K2A at the mapping site).
//   • valuation EXPLICITLY NULL or malformed → the backend SAYS the
//     valuation is unavailable. The card shows no GHS figure at all —
//     never a silent client-side substitution for a backend failure.
//   • valuation key ABSENT (legacy) → the interim display-only
//     derivation above.
//
// UNKNOWN IS NOT ZERO, every branch below: readiness unresolved/failed →
// balanceConfirmed false (dots, never 0.00); vaults/savings/susu not
// loaded → null rows (dashes); no usable rate → no GHS equivalent, and
// no rate row masquerading as a valuation.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/models/balance_valuation_payload.dart'
    show BackendBalanceValuation, BackendRateStatus;
import 'package:azaman/providers/auth_provider.dart' show isVendorProvider;
import 'package:azaman/providers/currency_provider.dart' show fxRateProvider;
import 'package:azaman/providers/hologram_provider.dart'
    show balanceDataProvider, balanceReadinessProvider, BalanceReadiness;
import 'package:azaman/providers/savings_overview_provider.dart'
    show savingsOverviewProvider;
import 'package:azaman/providers/vault_provider.dart' show vaultsProvider;

/// The production valuation the main Home card renders.
///
/// Rebuilt whenever any authoritative source changes; derived totals are
/// computed by [BalanceCardValuation.compute], never by the widget.
final balanceCardValuationProvider = Provider<BalanceCardValuation>((ref) {
  final balance = ref.watch(balanceDataProvider);
  final readiness = ref.watch(balanceReadinessProvider);
  final fxSnapshot = ref.watch(fxRateProvider);
  final vaults = ref.watch(vaultsProvider);
  final savings = ref.watch(savingsOverviewProvider);
  final isVendor = ref.watch(isVendorProvider);

  // ── Balance readiness: unresolved/failed is NOT zero, and a failure
  // after a load keeps the last confirmed figure (readiness stays
  // [loaded] — the hologram ledger's own law).
  final confirmed = readiness == BalanceReadiness.loaded;

  // ── FX: the oracle snapshot is a usable rate only while its full
  // freshness contract holds. Loading is genuine when the fetch is in
  // flight AND no usable snapshot is being displayed.
  final rateUsable = fxSnapshot.asData?.value?.isUsable ?? false;
  final usableRate = rateUsable ? fxSnapshot.asData!.value! : null;
  final rateView = FxRateView(
    ghsPerUsdc: usableRate?.ghsPerUsdc,
    kind: rateUsable ? FxRateKind.fresh : FxRateKind.none,
    loading: fxSnapshot.isLoading && !rateUsable,
    observedAt: usableRate?.lastExternalSync,
  );

  // ── Committed funds: each list is a value only once loaded; an empty
  // loaded list is a real zero, an unloaded/failed list is unknown.
  //
  // WORKSTREAM K2B AUDIT (savings currentAmountGhs, backend evidence):
  // the backend deposit path debits user.availableBalance and
  // increments user.escrowLockedBalance inside the SAME money
  // transaction that increments SavingsGoal.currentAmountGhs
  // (savingsController deposit, locked-row FOR UPDATE, r25 rigor); goal
  // creation cannot seed it (schema default 0.0, create() never accepts
  // it from the client); the withdraw path decrements it and releases
  // the escrow. currentAmountGhs is therefore NOT user-maintained goal
  // progress: it is the GHS-denominated figure of a REAL escrow-backed
  // commitment, and mapping it into the committed-savings bucket is
  // correct under the existing contract. (Contrast Susu, K2A: there the
  // customer-facing meaning of the #367 field is still unsettled, so
  // that row stays UNKNOWN.)
  double? vaultTotal;
  if (vaults.hasValue) {
    vaultTotal = vaults.value!
        .where((v) => v.isLocked && v.status == 'ACTIVE')
        .fold<double>(0.0, (sum, v) => sum + v.currentAmountUsdc);
  }

  double? savingsGhs;
  if (savings.hasValue) {
    // INSPECT THE RAW SHAPE — SavingsOverview.goals collapses every
    // unknown into an empty list (missing key, non-List, malformed
    // entries), which would read as a confirmed zero. The current
    // /savings/overview contract does NOT guarantee that an absent or
    // malformed goals collection means 'no savings'. Honesty rules:
    //   • goals is a real List → fold; but ANY entry with a missing /
    //     invalid currentAmountGhs makes the aggregate UNKNOWN (null)
    //     — a missing amount is never read as 0.
    //   • goals absent / not a List → UNKNOWN (null), never zero.
    // A valid loaded EMPTY list is the only shape that yields a real 0.
    final rawGoals = savings.value!.data['goals'];
    if (rawGoals is List) {
      var sum = 0.0;
      var allKnown = true;
      for (final entry in rawGoals) {
        if (entry is! Map) {
          allKnown = false;
          break;
        }
        // STATUS FILTER — the agreed backend valuation contract counts
        // ONLY the ACTIVE and PAUSED statuses in the committed-savings
        // bucket (backend PR #367, SAVINGS_ACTIVE_STATUSES). COMPLETED
        // and CANCELLED goals are settled history, not currently
        // committed savings. A missing or non-String status is a
        // MALFORMED entry: the aggregate goes UNKNOWN (null) — never
        // silently included or excluded.
        final status = entry['status'];
        if (status is! String) {
          allKnown = false;
          break;
        }
        if (status != 'ACTIVE' && status != 'PAUSED') continue;
        final amount = entry['currentAmountGhs'];
        if (amount is! num || amount < 0 || !amount.isFinite) {
          allKnown = false;
          break;
        }
        sum += amount.toDouble();
      }
      savingsGhs = allKnown ? sum : null;
    }
    // else: goals collection absent/malformed → savingsGhs stays null.
  }

  // ── Committed Susu: UNKNOWN until the backend says otherwise ───────
  //
  // SusuSummary.contributionUsdc is the group's RECURRING CONTRIBUTION
  // AMOUNT — a schedule figure, NOT proof of paid funds currently held
  // for the caller. An ACTIVE group plus the caller's ACTIVE membership
  // do not, by themselves, establish that any funds are committed. The
  // ONLY legitimate source of a committed-Susu amount is the backend
  // valuation contract's `locked.committedSusuUsdc` (backend PR #367:
  // PAID contributions in COLLECTING/COLLECTING_GRACE cycles) — and
  // even when that field IS published it stays parsed-not-displayed
  // until the approved money architecture settles its final
  // customer-facing meaning (K2A). In every branch the committed-Susu
  // row renders UNKNOWN (—) — never a scheduled contribution summed
  // as though it were held funds.
  double? susuTotal;

  // ── Backend valuation block (backend PR #367, additive) ──────────────
  //
  // Three states, never conflated:
  //   • valuation key ABSENT            → LEGACY contract: interim
  //     display-only client derivation (below), gate honestly closed.
  //   • valuation EXPLICITLY null / malformed → the backend SAYS the
  //     valuation is unavailable: NO GHS figure at all, and NEVER a
  //     silent client-side substitution for the backend's failure.
  //   • valuation present + strict parse ok → backend-authoritative.
  BackendBalanceValuation? backendValuation;
  var backendSaysUnavailable = false;
  if (balance.valuationFieldPresent) {
    final raw = balance.valuationRaw;
    if (raw == null) {
      backendSaysUnavailable = true;
    } else {
      backendValuation = BackendBalanceValuation.parse(raw);
      if (backendValuation == null) backendSaysUnavailable = true;
    }
  }

  if (backendValuation != null) {
    // ── BACKEND-AUTHORITATIVE branch ────────────────────────────────
    // Every figure below is a documented #367 field, mapped verbatim.
    // The card NEVER recalculates: the GHS total and the USDC
    // equivalent are the backend's own computed values.
    final rateKind = switch (backendValuation.rateStatus) {
      BackendRateStatus.current => FxRateKind.fresh,
      BackendRateStatus.savedFallback => FxRateKind.saved,
      BackendRateStatus.demoFallback => FxRateKind.demo,
      BackendRateStatus.unavailable => FxRateKind.none,
    };
    final displayRate = backendValuation.displayRate;
    final obs = backendValuation.currentRate ?? backendValuation.savedRate;
    return BalanceCardValuation(
      nativeGhsAvailable: backendValuation.nativeGhsAvailable.value,
      availableUsdc: backendValuation.availableUsdc.value,
      balanceConfirmed: confirmed,
      escrowLocked: backendValuation.locked.escrowUsdc.value,
      disputeEscrow: backendValuation.locked.disputesUsdc.value,
      vaultLocked: backendValuation.locked.vaultsUsdc.value,
      // WORKSTREAM K2A — committedSusuUsdc is PARSED for contract
      // compatibility but deliberately NOT displayed. #367 computes it
      // as the sum of PAID SusuContribution.amountUsdc in
      // COLLECTING/COLLECTING_GRACE cycles — real paid-in USDC — but
      // the money architecture has NOT yet approved it as the final
      // customer-facing meaning of a Susu commitment: a domestic Susu
      // product should default to a fixed GHS obligation, and GHS and
      // USDC remain DISTINCT funding assets. A raw USDC sum therefore
      // cannot be shown as the amount the customer is owed by a
      // domestic Susu product until the approved contract establishes
      // the field's meaning, currency and relation to the promised
      // payout. Until then the committed-Susu row renders UNKNOWN (—).
      susuCommitted: null,
      savingsLockedGhs: backendValuation.locked.savingsGhs.value,
      vendorUnallocatedUsdc:
          backendValuation.locked.vendorUnallocatedUsdc.value,
      vendorRowRelevant: isVendor,
      azmPoints: backendValuation.azmPoints.value,
      rate: FxRateView(
        ghsPerUsdc: displayRate?.rate,
        kind: rateKind,
        loading: false,
        sourceLabel: obs?.source,
        observedAt: obs?.observedAt,
      ),
      availableGhsValue: backendValuation.availableGhsValue?.value,
      availableUsdcEquivalent: backendValuation.usdcEquivalent?.value,
      // AUTHORITATIVE gate — the backend's own transaction
      // authorisation boolean, verbatim. Never derived from the rate.
      usdcTransactionGateOpen: backendValuation.usdcTransactionGateOpen,
      // NO compute() here: [BalanceCardValuation.compute] re-derives the
      // totals from the rate, and the backend's own availableGhsValue /
      // usdcEquivalent are AUTHORITATIVE — the card renders them as
      // given, never recalculated client-side.
    );
  }

  if (backendSaysUnavailable) {
    // ── EXPLICIT BACKEND FAILURE branch ─────────────────────────────
    // The backend declared the valuation unavailable. Show the REAL
    // USDC holding and the honest committed buckets from the legacy
    // fields/lists, but NO GHS figure and NO USDC equivalent: the
    // client-side rate must never masquerade as a valuation the backend
    // just said it could not produce. The rate row keeps its own
    // informational state (a rate fact is not a valuation).
    return BalanceCardValuation(
      nativeGhsAvailable: null,
      availableUsdc: balance.availableBalance,
      balanceConfirmed: confirmed,
      escrowLocked: balance.escrowLockedBalance,
      disputeEscrow: balance.disputeEscrowBalance,
      vaultLocked: vaultTotal,
      susuCommitted: susuTotal,
      savingsLockedGhs: savingsGhs,
      vendorUnallocatedUsdc: balance.vendorUnallocatedBalance,
      vendorRowRelevant: isVendor,
      azmPoints: balance.azmBalance,
      rate: rateView,
      availableGhsValue: null,
      availableUsdcEquivalent: null,
      // No gate field accompanies an unavailable valuation — the gate
      // stays honestly closed.
      usdcTransactionGateOpen: false,
      // NO compute(): compute() would re-derive a GHS figure from the
      // client-side rate and silently substitute it for the backend's
      // declared-unavailable valuation — exactly the substitution this
      // branch exists to prevent. The nulls are final.
    );
  }

  // ── LEGACY branch: interim display-only derivation ────────────────────
  return BalanceCardValuation(
    // No native GHS wallet exists on the current contract — NULL, and
    // the back-face row renders unknown. Never 0.
    nativeGhsAvailable: null,
    availableUsdc: balance.availableBalance,
    balanceConfirmed: confirmed,
    escrowLocked: balance.escrowLockedBalance,
    disputeEscrow: balance.disputeEscrowBalance,
    vaultLocked: vaultTotal,
    susuCommitted: susuTotal,
    savingsLockedGhs: savingsGhs,
    vendorUnallocatedUsdc: balance.vendorUnallocatedBalance,
    vendorRowRelevant: isVendor,
    azmPoints: balance.azmBalance,
    rate: rateView,
    // The USDC transaction gate is the BACKEND's transaction-
    // AUTHORISATION contract — it is NOT a client-side FX predicate.
    // No authoritative gate field exists on the current contract, so
    // the gate is honestly CLOSED: rate usability alone must never be
    // read as financial permission. When the backend publishes a gate
    // field, this maps it explicitly.
    usdcTransactionGateOpen: false,
  ).compute();
});
