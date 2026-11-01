// =============================================================================
// AZAMAN — BACKEND BALANCE VALUATION PAYLOAD (TYPED MAPPER)
//
// The strict, typed parse of the AUTHORITATIVE balance-valuation contract
// published additively on GET /users/balance `data.valuation` by backend
// PR #367 (AzamanLTD/AZM-backend, feat/native-ghs-balance-and-fx-snapshot).
//
// PARSE RULES (strict — a malformed payload is UNUSABLE, never partially
// consumed):
//   • Only the DOCUMENTED fields of that contract are read. Unknown keys
//     are ignored (forward compatibility), but a documented REQUIRED
//     field that is missing or malformed rejects the whole payload.
//   • Monetary values are serialized by the backend as `{ exact, value }`
//     — `exact` is the authoritative decimal string and `value` is the
//     presentation projection. The card renders `value`; `exact` must be
//     present and a string, but is carried for evidence/audit and never
//     re-parsed into money.
//   • `usdcEquivalent` and `availableGhsValue` are genuinely NULLABLE
//     (null = the backend honestly could not value the balance; the card
//     must never fabricate them).
//   • rateStatus / valuationStatus are CLOSED enums; anything else is a
//     contract break and rejects the payload.
//   • `usdcTransactionGateOpen` is the backend's AUTHORITATIVE gate. It
//     is mapped verbatim — never derived from rate freshness.
//
// LEGACY vs EXPLICIT-NULL (a distinction the card depends on):
//   • `data.valuation` key ABSENT  → legacy response (the contract has
//     not shipped yet): the adapter keeps its interim display-only
//     derivation. See balanceCardValuationProvider.
//   • `data.valuation` explicitly null (or present but rejected here) →
//     the backend SAYS valuation is unavailable. The card must NOT
//     silently substitute a client-side conversion for that failure.
//
// This file invents no endpoints, no field names and no semantics: every
// field below is copied from the documented #367 response shape.
// =============================================================================

import 'package:flutter/foundation.dart';

/// How the displayed FX rate was obtained, per the backend contract.
enum BackendRateStatus { current, savedFallback, demoFallback, unavailable }

/// The backend's own valuation completeness verdict.
enum BackendValuationStatus {
  current,
  savedFallback,
  demoFallback,
  nativeGhsOnly,
  partialFxUnavailable,
}

/// A backend monetary `{ exact, value }` pair.
@immutable
class BackendMoney {
  /// The authoritative decimal string (never re-parsed into money here).
  final String exact;

  /// The presentation projection the card renders.
  final double value;

  const BackendMoney._(this.exact, this.value);
}

/// The `currentRate` / `savedRate` observation blocks (display metadata
/// only — they never feed the transaction gate).
@immutable
class BackendRateObservation {
  final double rate;
  final String rateExact;
  final bool isFresh;
  final String pair;
  final String? source;
  final DateTime? observedAt;

  const BackendRateObservation._({
    required this.rate,
    required this.rateExact,
    required this.isFresh,
    required this.pair,
    this.source,
    this.observedAt,
  });
}

/// The `displayRate` block: which basis produced the display figure.
@immutable
class BackendDisplayRate {
  final BackendRateStatus basis;
  final double rate;

  const BackendDisplayRate._(this.basis, this.rate);
}

/// The `locked` block — committed/restricted buckets, each in its NATIVE
/// unit, never summed across currencies.
@immutable
class BackendValuationLocked {
  final BackendMoney escrowUsdc;
  final BackendMoney disputesUsdc;
  final BackendMoney vaultsUsdc;
  final BackendMoney savingsGhs;
  final BackendMoney committedSusuUsdc;
  final BackendMoney vendorUnallocatedUsdc;

  const BackendValuationLocked._({
    required this.escrowUsdc,
    required this.disputesUsdc,
    required this.vaultsUsdc,
    required this.savingsGhs,
    required this.committedSusuUsdc,
    required this.vendorUnallocatedUsdc,
  });
}

/// The typed, validated `data.valuation` payload.
@immutable
class BackendBalanceValuation {
  final String pair;

  // ── Underlying real assets — DISTINCT concepts ─────────────────────────
  /// REAL native GHS owed to the customer (the GHS wallet).
  final BackendMoney nativeGhsAvailable;

  /// REAL liquid USDC held — never the same quantity as [usdcEquivalent].
  final BackendMoney availableUsdc;

  /// The DISPLAY valuation of the whole available GHS value expressed in
  /// USDC at the display rate. NOT USDC held. Null = cannot be valued.
  final BackendMoney? usdcEquivalent;

  /// The backend-authoritative combined available value in GHS.
  /// Null = cannot be valued (honestly partial/unavailable).
  final BackendMoney? availableGhsValue;

  // ── Rate situation ─────────────────────────────────────────────────────
  final BackendRateStatus rateStatus;
  final BackendValuationStatus valuationStatus;
  final BackendRateObservation? currentRate;
  final BackendRateObservation? savedRate;
  final BackendDisplayRate? displayRate;

  // ── Transaction gate — AUTHORITATIVE backend authorisation ────────────
  final bool usdcTransactionGateOpen;
  final String? usdcTransactionGateReason;

  // ── Locked / committed / non-cash ──────────────────────────────────────
  final BackendValuationLocked locked;
  final BackendMoney azmPoints;
  final DateTime? evaluatedAt;

  const BackendBalanceValuation._({
    required this.pair,
    required this.nativeGhsAvailable,
    required this.availableUsdc,
    this.usdcEquivalent,
    this.availableGhsValue,
    required this.rateStatus,
    required this.valuationStatus,
    this.currentRate,
    this.savedRate,
    this.displayRate,
    required this.usdcTransactionGateOpen,
    this.usdcTransactionGateReason,
    required this.locked,
    required this.azmPoints,
    this.evaluatedAt,
  });

  /// Strict parse of the documented `data.valuation` shape.
  ///
  /// Returns null when ANY documented required field is missing or
  /// malformed, or an enum carries an unknown value — the payload is then
  /// unusable as a whole and the adapter treats it exactly like an
  /// explicit backend "valuation unavailable".
  static BackendBalanceValuation? parse(Map<String, dynamic> json) {
    // ── Money helper: { exact: String, value: num } — both required.
    BackendMoney? money(dynamic raw) {
      if (raw is! Map) return null;
      final exact = raw['exact'];
      final value = raw['value'];
      if (exact is! String || exact.isEmpty) return null;
      if (value is! num || !value.isFinite) return null;
      return BackendMoney._(exact, value.toDouble());
    }

    BackendMoney? requireMoney(dynamic raw) => raw == null ? null : money(raw);

    final pair = json['pair'];
    if (pair is! String || pair.isEmpty) return null;

    final nativeGhsAvailable = money(json['nativeGhsAvailable']);
    final availableUsdc = money(json['availableUsdc']);
    if (nativeGhsAvailable == null || availableUsdc == null) return null;

    // Nullable by contract — null is an honest "cannot be valued".
    final usdcEquivalentRaw = json['usdcEquivalent'];
    final usdcEquivalent = usdcEquivalentRaw == null
        ? null
        : money(usdcEquivalentRaw);
    if (usdcEquivalentRaw != null && usdcEquivalent == null) return null;

    final availableGhsValueRaw = json['availableGhsValue'];
    final availableGhsValue = availableGhsValueRaw == null
        ? null
        : money(availableGhsValueRaw);
    if (availableGhsValueRaw != null && availableGhsValue == null) return null;

    // ── Closed enums — unknown values are a contract break.
    final rateStatusRaw = json['rateStatus'];
    final BackendRateStatus? rateStatus = switch (rateStatusRaw) {
      'CURRENT' => BackendRateStatus.current,
      'SAVED_FALLBACK' => BackendRateStatus.savedFallback,
      'DEMO_FALLBACK' => BackendRateStatus.demoFallback,
      'UNAVAILABLE' => BackendRateStatus.unavailable,
      _ => null,
    };
    final valuationStatusRaw = json['valuationStatus'];
    final BackendValuationStatus? valuationStatus =
        switch (valuationStatusRaw) {
          'CURRENT' => BackendValuationStatus.current,
          'SAVED_FALLBACK' => BackendValuationStatus.savedFallback,
          'DEMO_FALLBACK' => BackendValuationStatus.demoFallback,
          'NATIVE_GHS_ONLY' => BackendValuationStatus.nativeGhsOnly,
          'PARTIAL_FX_UNAVAILABLE' =>
            BackendValuationStatus.partialFxUnavailable,
          _ => null,
        };
    if (rateStatus == null || valuationStatus == null) return null;

    // ── Optional observation blocks — strict when present.
    BackendRateObservation? observation(dynamic raw, {required bool isFresh}) {
      if (raw == null) return null;
      if (raw is! Map) return null;
      final rate = raw['rate'];
      final rateExact = raw['rateExact'];
      final obsPair = raw['pair'];
      final source = raw['source'];
      final observedRaw = raw['observedAt'];
      if (rate is! num || !rate.isFinite || rate <= 0) return null;
      if (rateExact is! String || rateExact.isEmpty) return null;
      if (obsPair is! String || obsPair.isEmpty) return null;
      if (source != null && source is! String) return null;
      DateTime? observedAt;
      if (observedRaw != null) {
        if (observedRaw is! String) return null;
        observedAt = DateTime.tryParse(observedRaw);
        if (observedAt == null) return null;
      }
      return BackendRateObservation._(
        rate: rate.toDouble(),
        rateExact: rateExact,
        isFresh: isFresh,
        pair: obsPair,
        source: source is String ? source : null,
        observedAt: observedAt,
      );
    }

    final currentRateRaw = json['currentRate'];
    final currentRate = observation(currentRateRaw, isFresh: true);
    if (currentRateRaw != null && currentRate == null) return null;

    final savedRateRaw = json['savedRate'];
    final savedRate = observation(savedRateRaw, isFresh: false);
    if (savedRateRaw != null && savedRate == null) return null;

    final displayRateRaw = json['displayRate'];
    BackendDisplayRate? displayRate;
    if (displayRateRaw != null) {
      if (displayRateRaw is! Map) return null;
      final basis = displayRateRaw['basis'];
      final rate = displayRateRaw['rate'];
      final BackendRateStatus? basisStatus = switch (basis) {
        'CURRENT' => BackendRateStatus.current,
        'SAVED_FALLBACK' => BackendRateStatus.savedFallback,
        'DEMO_FALLBACK' => BackendRateStatus.demoFallback,
        _ => null,
      };
      if (basisStatus == null) return null;
      if (rate is! num || !rate.isFinite || rate <= 0) return null;
      displayRate = BackendDisplayRate._(basisStatus, rate.toDouble());
    }

    // ── Gate — the backend's authoritative boolean, verbatim.
    final gate = json['usdcTransactionGateOpen'];
    if (gate is! bool) return null;
    final gateReason = json['usdcTransactionGateReason'];
    if (gateReason != null && gateReason is! String) return null;

    // ── locked block — every documented bucket required, native units.
    final lockedRaw = json['locked'];
    if (lockedRaw is! Map) return null;
    final escrowUsdc = requireMoney(lockedRaw['escrowUsdc']);
    final disputesUsdc = requireMoney(lockedRaw['disputesUsdc']);
    final vaultsUsdc = requireMoney(lockedRaw['vaultsUsdc']);
    final savingsGhs = requireMoney(lockedRaw['savingsGhs']);
    final committedSusuUsdc = requireMoney(lockedRaw['committedSusuUsdc']);
    final vendorUnallocatedUsdc = requireMoney(
      lockedRaw['vendorUnallocatedUsdc'],
    );
    if (escrowUsdc == null ||
        disputesUsdc == null ||
        vaultsUsdc == null ||
        savingsGhs == null ||
        committedSusuUsdc == null ||
        vendorUnallocatedUsdc == null) {
      return null;
    }

    // ── non-cash loyalty points.
    final nonCashRaw = json['nonCash'];
    if (nonCashRaw is! Map) return null;
    final azmPoints = money(nonCashRaw['azmPoints']);
    if (azmPoints == null) return null;

    // ── evaluatedAt — optional but strict when present.
    DateTime? evaluatedAt;
    final evaluatedRaw = json['evaluatedAt'];
    if (evaluatedRaw != null) {
      if (evaluatedRaw is! String) return null;
      evaluatedAt = DateTime.tryParse(evaluatedRaw);
      if (evaluatedAt == null) return null;
    }

    return BackendBalanceValuation._(
      pair: pair,
      nativeGhsAvailable: nativeGhsAvailable,
      availableUsdc: availableUsdc,
      usdcEquivalent: usdcEquivalent,
      availableGhsValue: availableGhsValue,
      rateStatus: rateStatus,
      valuationStatus: valuationStatus,
      currentRate: currentRate,
      savedRate: savedRate,
      displayRate: displayRate,
      usdcTransactionGateOpen: gate,
      usdcTransactionGateReason: gateReason is String ? gateReason : null,
      locked: BackendValuationLocked._(
        escrowUsdc: escrowUsdc,
        disputesUsdc: disputesUsdc,
        vaultsUsdc: vaultsUsdc,
        savingsGhs: savingsGhs,
        committedSusuUsdc: committedSusuUsdc,
        vendorUnallocatedUsdc: vendorUnallocatedUsdc,
      ),
      azmPoints: azmPoints,
      evaluatedAt: evaluatedAt,
    );
  }
}
