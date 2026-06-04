// =============================================================================
// HOLOGRAM LEDGER — RIVERPOD STATE LAYER (V4)
//
// Architecture:
//   balanceDataProvider      → full V2 ledger (5 balance fields)
//   userUsdcBalanceProvider  → legacy: total USDC (available + vendorUnallocated)
//   oracleRateProvider       → live GHS/USDC rate (updated via socket)
//   hologramBalanceProvider  → derived: total USDC × rate = display GHS value
//
// The socket service writes to balanceDataProvider on every balance_update
// event. All UI widgets should prefer watching balanceDataProvider for
// granular access to individual balance buckets.
//
// Phase J (2026-05-25): legacy `lockedBalance` and `ghsBalance` fields
// dropped from BalanceData. They were write-dead V1 columns on the BE.
// Active escrow now lives in `escrowLockedBalance`; GHS is derived as
// `availableBalance × oracleRate` via hologramBalanceProvider.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -----------------------------------------------------------------------------
// BALANCE DATA MODEL — Full V2 Ledger
// -----------------------------------------------------------------------------
class BalanceData {
  final double availableBalance;
  final double vendorUnallocatedBalance;
  final double escrowLockedBalance;
  final double disputeEscrowBalance;
  final double azmBalance;

  const BalanceData({
    this.availableBalance = 0.0,
    this.vendorUnallocatedBalance = 0.0,
    this.escrowLockedBalance = 0.0,
    this.disputeEscrowBalance = 0.0,
    this.azmBalance = 0.0,
  });

  /// Total available balance (what the user can spend)
  double get totalBalance => availableBalance + vendorUnallocatedBalance;

  /// Total locked (V2: active-trade escrow + dispute quarantine)
  double get totalLocked => escrowLockedBalance + disputeEscrowBalance;

  /// Net worth (all balances combined)
  double get netWorth => totalBalance + totalLocked + azmBalance;

  BalanceData copyWith({
    double? availableBalance,
    double? vendorUnallocatedBalance,
    double? escrowLockedBalance,
    double? disputeEscrowBalance,
    double? azmBalance,
  }) {
    return BalanceData(
      availableBalance: availableBalance ?? this.availableBalance,
      vendorUnallocatedBalance: vendorUnallocatedBalance ?? this.vendorUnallocatedBalance,
      escrowLockedBalance: escrowLockedBalance ?? this.escrowLockedBalance,
      disputeEscrowBalance: disputeEscrowBalance ?? this.disputeEscrowBalance,
      azmBalance: azmBalance ?? this.azmBalance,
    );
  }
}

// -----------------------------------------------------------------------------
// 1. Full Balance Data Provider (V4 — canonical)
// -----------------------------------------------------------------------------
final balanceDataProvider = StateProvider<BalanceData>((ref) => const BalanceData());

// -----------------------------------------------------------------------------
// 2. USDC Balance Provider (legacy compat — total available)
// -----------------------------------------------------------------------------
final userUsdcBalanceProvider = StateProvider<double>((ref) => 0.0);

// -----------------------------------------------------------------------------
// 3. Oracle Rate Provider
//    Live GHS-per-USDC exchange rate from backend oracle.
// -----------------------------------------------------------------------------
final oracleRateProvider = StateProvider<double>((ref) => 12.50);

// -----------------------------------------------------------------------------
// 4. Hologram Balance Provider (computed / derived)
//    Total USDC × oracle rate → GHS display value. This IS the GHS hologram —
//    there is no persistent ghsBalance column; the value is derived on read.
// -----------------------------------------------------------------------------
final hologramBalanceProvider = Provider<double>((ref) {
  final balances = ref.watch(balanceDataProvider);
  final rate = ref.watch(oracleRateProvider);
  return balances.totalBalance * rate;
});

// -----------------------------------------------------------------------------
// 5. Balance Visibility Toggle
//    Lets the user hide/reveal the balance on the hologram card.
// -----------------------------------------------------------------------------
final balanceVisibleProvider = StateProvider<bool>((ref) => true);

// -----------------------------------------------------------------------------
// 6. Individual balance selectors (for granular widget rebuilds)
// -----------------------------------------------------------------------------
final availableBalanceProvider = Provider<double>((ref) {
  return ref.watch(balanceDataProvider).availableBalance;
});

final escrowBalanceProvider = Provider<double>((ref) {
  return ref.watch(balanceDataProvider).escrowLockedBalance;
});

final azmBalanceProvider = Provider<double>((ref) {
  return ref.watch(balanceDataProvider).azmBalance;
});

// Phase J: ghsBalanceProvider removed. Use hologramBalanceProvider for the
// derived GHS display value (availableBalance × oracleRate).
