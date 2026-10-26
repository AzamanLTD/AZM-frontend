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
// open). Therefore nativeGhsAvailable is NULL (the GHS wallet row on the
// back face renders unknown, never GH₵ 0.00) and the combined GHS value
// is the honest interim derivation: (native ?? 0) + availableUsdc ×
// rate, applied ONLY while a usable rate exists. The headline USDC figure
// is the REAL holding; the GHS figure is its equivalent — exactly the
// old HologramBalanceCard semantics, now typed.
//
// UNKNOWN IS NOT ZERO, every branch below: readiness unresolved/failed →
// balanceConfirmed false (dots, never 0.00); vaults/savings/susu not
// loaded → null rows (dashes); no usable rate → no GHS equivalent, and
// no rate row masquerading as a valuation.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/auth_provider.dart' show isVendorProvider;
import 'package:azaman/providers/currency_provider.dart' show fxRateProvider;
import 'package:azaman/providers/hologram_provider.dart'
    show balanceDataProvider, balanceReadinessProvider, BalanceReadiness;
import 'package:azaman/providers/savings_overview_provider.dart'
    show savingsOverviewProvider;
import 'package:azaman/providers/susu_provider.dart' show susuListProvider;
import 'package:azaman/providers/vault_provider.dart' show vaultsProvider;
import 'package:azaman/models/susu_model.dart'
    show SusuMemberStatus, SusuStatus;

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
  final susu = ref.watch(susuListProvider);
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

  double? susuTotal;
  if (susu.hasValue) {
    // Committed Susu requires BOTH: an ACTIVE group and the caller's
    // OWN membership being ACTIVE (SusuGroup.myStatus is parsed from
    // the caller's member record). A pending-vouch, pending-contract,
    // defaulted or removed member has NOTHING committed by this user —
    // an active group alone does not commit the caller's funds.
    susuTotal = susu.value!
        .where((s) =>
            s.status == SusuStatus.active &&
            s.myStatus == SusuMemberStatus.active)
        .fold<double>(0.0, (sum, s) => sum + s.contributionUsdc);
  }

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
