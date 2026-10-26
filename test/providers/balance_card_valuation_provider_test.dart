// =============================================================================
// BALANCE CARD VALUATION — PRODUCTION ADAPTER CONTRACT
//
// Pins the authoritative-source mapping rules of
// balanceCardValuationProvider (the ONLY seam production numbers enter
// the redesigned card through), with the honesty laws this PR exists
// to enforce:
//   • Susu 'committed' requires an ACTIVE group AND the caller's OWN
//     ACTIVE membership — a pending/defaulted/removed member has
//     NOTHING committed by this user, even in an active group.
//   • Savings is a real number ONLY when the RAW goals shape is a
//     List whose every entry carries a valid currentAmountGhs. A
//     missing/malformed goals collection or a missing amount is
//     UNKNOWN (null) — never a confirmed zero.
//   • The USDC transaction gate is a BACKEND authorisation fact. No
//     gate field exists on the current contract, so the gate is
//     CLOSED — rate usability alone must NEVER open it.
//   • Native GHS is NULL on the current contract (backend PR #367
//     unmerged) — the back-face wallet row stays unknown, never 0.
//   • Balance unresolved/failed → balanceConfirmed false; loaded →
//     true even for a genuine zero; vaults/savings/susu unloaded →
//     null committed values, empty-loaded-list → real zero.
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart' show isVendorProvider;
import 'package:azaman/providers/balance_card_valuation_provider.dart';
import 'package:azaman/providers/currency_provider.dart'
    show FxRateSnapshot, fxRateProvider;
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/savings_overview_provider.dart';
import 'package:azaman/providers/susu_provider.dart'
    show SusuListNotifier, susuListProvider;
import 'package:azaman/providers/vault_provider.dart';

// ── Test doubles ───────────────────────────────────────────────────────────

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

class _FakeSavingsNotifier extends SavingsOverviewNotifier {
  _FakeSavingsNotifier(this.overview);
  final SavingsOverview overview;
  @override
  Future<SavingsOverview> build() async => overview;
}

class _NeverLoadingSavingsNotifier extends SavingsOverviewNotifier {
  @override
  Future<SavingsOverview> build() => Completer<SavingsOverview>().future;
}

class _LoadingSusuListNotifier extends SusuListNotifier {
  @override
  Future<List<SusuSummary>> build() =>
      Completer<List<SusuSummary>>().future;
}

class _FakeVaultsNotifier extends VaultsNotifier {
  _FakeVaultsNotifier(this.vaults);
  final List<Vault> vaults;
  @override
  Future<List<Vault>> build() async => vaults;
}

Vault _lockedVault(double amount) => Vault(
      id: 'v1',
      name: 'Vault',
      targetAmountUsdc: amount * 2,
      currentAmountUsdc: amount,
      status: 'ACTIVE',
      startDate: DateTime(2026, 1, 1),
      maturityDate: DateTime(2026, 12, 1),
      isLocked: true,
      earlyBreakPenaltyPct: 10,
      autoRuleEnabled: false,
      streakCount: 0,
      longestStreak: 0,
      missedCount: 0,
      consistencyScore: 0,
      totalAzmEarned: 0,
    );

SusuSummary _susu({
  required SusuMemberStatus myStatus,
  SusuStatus status = SusuStatus.active,
  double contribution = 10,
}) =>
    SusuSummary(
      id: 's1',
      name: 'Circle',
      status: status,
      contributionUsdc: contribution,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      myCycleSlot: 1,
      myStatus: myStatus,
      myRole: 'MEMBER',
      nextCycle: null,
    );

/// Sentinel for _container's default fx (a usable rate).
const _kDefaultUsableFx = 'DEFAULT_USABLE_RATE';

/// A fresh, usable oracle snapshot (the backend's full freshness
/// contract holds: serverFresh + a recent external observation).
FxRateSnapshot _usableRate({double rate = 12.0}) => FxRateSnapshot(
      ghsPerUsdc: rate,
      source: 'oracle',
      lastSync: DateTime.now(),
      fetchedAt: DateTime.now(),
      serverFresh: true,
      lastExternalSync: DateTime.now(),
      externalRateAgeSeconds: 5,
      rateFreshnessMaxAgeSeconds: 300,
    );

ProviderContainer _container({
  BalanceData balance = const BalanceData(availableBalance: 50),
  BalanceReadiness readiness = BalanceReadiness.loaded,
  Object fx = _kDefaultUsableFx, // FxRateSnapshot | Exception
  List<Vault> vaults = const [],
  SavingsOverview? savings,
  bool savingsLoading = false,
  List<SusuSummary> susu = const [],
  bool susuLoading = false,
  bool isVendor = false,
}) {
  final container = ProviderContainer(
    overrides: [
      balanceDataProvider.overrideWith((ref) => balance),
      balanceReadinessProvider.overrideWith((ref) => readiness),
      fxRateProvider.overrideWith((ref) async {
        if (fx == _kDefaultUsableFx) return _usableRate();
        if (fx is FxRateSnapshot) return fx;
        throw fx as Exception;
      }),
      vaultsProvider.overrideWith(() => _FakeVaultsNotifier(vaults)),
      savingsLoading
          ? savingsOverviewProvider.overrideWith(
              _NeverLoadingSavingsNotifier.new)
          : savingsOverviewProvider.overrideWith(
              () => _FakeSavingsNotifier(savings ?? SavingsOverview({}))),
      susuLoading
          ? susuListProvider.overrideWith(_LoadingSusuListNotifier.new)
          : susuListProvider.overrideWith(() => _FakeSusuListNotifier(susu)),
      isVendorProvider.overrideWithValue(isVendor),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Lets the fakes' async builds complete, then reads the adapter.
Future<BalanceCardValuation> _val(ProviderContainer c) async {
  try {
    await c.read(fxRateProvider.future);
  } catch (_) {}
  try {
    await c.read(vaultsProvider.future);
  } catch (_) {}
  try {
    await c.read(savingsOverviewProvider.future);
  } catch (_) {}
  try {
    await c.read(susuListProvider.future);
  } catch (_) {}
  return c.read(balanceCardValuationProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Susu — committed requires the caller\'s OWN active membership', () {
    test('active group + OWN membership active → committed', () async {
      final v = await _val(_container(
        susu: [_susu(myStatus: SusuMemberStatus.active, contribution: 10)],
      ));
      expect(v.susuCommitted, 10);
    });

    test('active group but caller PENDING_VOUCH → nothing committed', () async {
      final v = await _val(_container(
        susu: [_susu(myStatus: SusuMemberStatus.pendingVouch)],
      ));
      expect(v.susuCommitted, 0,
          reason: 'a not-yet-admitted member has committed no funds — '
              'the group being active is not the caller\'s commitment');
    });

    test('active group but caller PENDING_CONTRACT → nothing committed', () async {
      final v = await _val(_container(
        susu: [_susu(myStatus: SusuMemberStatus.pendingContract)],
      ));
      expect(v.susuCommitted, 0);
    });

    test('active group but caller DEFAULTED → nothing committed', () async {
      final v = await _val(_container(
        susu: [_susu(myStatus: SusuMemberStatus.defaulted)],
      ));
      expect(v.susuCommitted, 0);
    });

    test('active group but caller REMOVED → nothing committed', () async {
      final v = await _val(_container(
        susu: [_susu(myStatus: SusuMemberStatus.removed)],
      ));
      expect(v.susuCommitted, 0);
    });

    test('own ACTIVE membership in a NON-active group → nothing committed', () async {
      final v = await _val(_container(
        susu: [
          _susu(myStatus: SusuMemberStatus.active, status: SusuStatus.configuring),
        ],
      ));
      expect(v.susuCommitted, 0);
    });

    test('mixed memberships: only the own-active rows count', () async {
      final v = await _val(_container(
        susu: [
          _susu(myStatus: SusuMemberStatus.active, contribution: 10),
          _susu(myStatus: SusuMemberStatus.pendingVouch, contribution: 40),
          _susu(myStatus: SusuMemberStatus.active, status: SusuStatus.completed),
        ],
      ));
      expect(v.susuCommitted, 10);
    });

    test('susu list NOT loaded → committed is UNKNOWN (null), not zero', () async {
      final v = _container(susuLoading: true)
          .read(balanceCardValuationProvider);
      expect(v.susuCommitted, isNull);
    });
  });

  group('Savings — unknown raw shapes are never a confirmed zero', () {
    test('goals is a real List with valid amounts → summed', () async {
      final v = await _val(_container(
        savings: SavingsOverview({
          'goals': [
            {'currentAmountGhs': 30},
            {'currentAmountGhs': 12.5},
          ],
        }),
      ));
      expect(v.savingsLockedGhs, 42.5);
    });

    test('goals is a valid EMPTY list → a real zero', () async {
      final v = await _val(_container(
        savings: SavingsOverview({'goals': <Map<String, dynamic>>[]}),
      ));
      expect(v.savingsLockedGhs, 0);
    });

    test('goals key ABSENT → UNKNOWN (null), never zero', () async {
      final v = await _val(_container(
        savings: SavingsOverview({'unrelated': 1}),
      ));
      expect(v.savingsLockedGhs, isNull,
          reason: 'the contract not publishing a goals collection does '
              'not confirm the user has no savings');
    });

    test('goals is NOT a List → UNKNOWN (null)', () async {
      final v = await _val(_container(
        savings: SavingsOverview({'goals': 'unavailable'}),
      ));
      expect(v.savingsLockedGhs, isNull);
    });

    test('any entry with a MISSING currentAmountGhs → UNKNOWN (null)', () async {
      final v = await _val(_container(
        savings: SavingsOverview({
          'goals': [
            {'currentAmountGhs': 30},
            {'name': 'Goal with no amount'},
          ],
        }),
      ));
      expect(v.savingsLockedGhs, isNull,
          reason: 'a missing amount is never read as 0');
    });

    test('any entry with a non-numeric amount → UNKNOWN (null)', () async {
      final v = await _val(_container(
        savings: SavingsOverview({
          'goals': [
            {'currentAmountGhs': 'thirty'},
          ],
        }),
      ));
      expect(v.savingsLockedGhs, isNull);
    });

    test('a NON-MAP entry → UNKNOWN (null)', () async {
      final v = await _val(_container(
        savings: SavingsOverview({'goals': ['malformed']}),
      ));
      expect(v.savingsLockedGhs, isNull);
    });

    test('savings still loading → UNKNOWN (null)', () async {
      final v =
          _container(savingsLoading: true).read(balanceCardValuationProvider);
      expect(v.savingsLockedGhs, isNull);
    });
  });

  group('USDC transaction gate — a backend authorisation fact', () {
    test('CLOSED even when a fresh usable rate is displayed', () async {
      final v = await _val(_container(fx: _usableRate()));
      expect(v.rate.kind, FxRateKind.fresh);
      expect(v.rate.isFresh, isTrue);
      expect(v.usdcTransactionGateOpen, isFalse,
          reason: 'rate usability is an FX fact, not a transaction '
              'authorisation — no backend gate field exists on the '
              'current contract, so the gate is honestly closed');
    });
  });

  group('Native GHS and balance readiness', () {
    test('nativeGhsAvailable is NULL on the current contract', () async {
      final v = await _val(_container());
      expect(v.nativeGhsAvailable, isNull);
      expect(v.availableGhsValue, 50 * 12.0,
          reason: 'the honest interim derivation: USDC × usable rate');
    });

    test('unresolved readiness → balanceConfirmed false', () async {
      final v =
          await _val(_container(readiness: BalanceReadiness.unresolved));
      expect(v.balanceConfirmed, isFalse);
      expect(v.headlineKnown, isFalse,
          reason: 'the #195 display law: while the balance is unconfirmed '
              'the headline shows the waiting dots, never a figure — the '
              'derived cached value is never displayed');
    });

    test('failed readiness → balanceConfirmed false', () async {
      final v =
          await _val(_container(readiness: BalanceReadiness.failed));
      expect(v.balanceConfirmed, isFalse);
    });

    test('loaded with a GENUINE zero → confirmed true, 0 is real', () async {
      final v = await _val(_container(
        balance: const BalanceData(),
        readiness: BalanceReadiness.loaded,
      ));
      expect(v.balanceConfirmed, isTrue);
      expect(v.availableUsdc, 0);
      // Pinned #195 contract: with NO native GHS wallet on the contract,
      // a confirmed zero USDC balance is an honestly EMPTY card — the GHS
      // figure stays absent rather than printing GH₵ 0.00 out of nothing.
      expect(v.availableGhsValue, isNull);
      expect(v.availableUsdcEquivalent, isNull);
    });

    test('vaults: empty loaded list → real zero; locked-active only', () async {
      final v = await _val(_container(vaults: [_lockedVault(7)]));
      expect(v.vaultLocked, 7);
    });

    test('no usable rate → no GHS figure, fresh-rate chrome absent', () async {
      final v = await _val(
          _container(fx: Exception('rate fetch failed')));
      expect(v.rate.kind, FxRateKind.none);
      expect(v.availableGhsValue, isNull);
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.usdcTransactionGateOpen, isFalse);
    });
  });
}
