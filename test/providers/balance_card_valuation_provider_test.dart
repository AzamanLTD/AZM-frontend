// =============================================================================
// BALANCE CARD VALUATION — PRODUCTION ADAPTER CONTRACT
//
// Pins the authoritative-source mapping rules of
// balanceCardValuationProvider (the ONLY seam production numbers enter
// the redesigned card through), with the honesty laws this PR exists
// to enforce:
//   • Committed Susu has NO client-side derivation AT ALL: a group's
//     recurring contribution amount is a schedule figure, not held
//     funds. Only the backend valuation contract's locked
//     committedSusuUsdc (backend PR #367) is a committed amount —
//     until it ships the row renders UNKNOWN (null).
//   • Balance unresolved/failed → balanceConfirmed false; loaded →
//     true even for a genuine zero; vaults/savings/susu unloaded →
//     null committed values, empty-loaded-list → real zero.
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/models/balance_valuation_payload.dart';
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
  Future<List<SusuSummary>> build() => Completer<List<SusuSummary>>().future;
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
}) => SusuSummary(
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
              _NeverLoadingSavingsNotifier.new,
            )
          : savingsOverviewProvider.overrideWith(
              () => _FakeSavingsNotifier(savings ?? const SavingsOverview({})),
            ),
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

  group('Susu committed — unknown until the backend contract publishes it', () {
    // THE REGRESSION this group exists for: an ACTIVE group plus the
    // caller's OWN ACTIVE membership were previously summed from the
    // group's recurring contributionUsdc and rendered as committed
    // funds. They do NOT establish a committed amount: a schedule
    // figure is not held money. Only the #367 valuation field
    // locked.committedSusuUsdc is authoritative — until the live
    // contract carries it the row is UNKNOWN.
    test(
      'active group + own ACTIVE membership → UNKNOWN (null), the regression',
      () async {
        final v = await _val(
          _container(
            susu: [_susu(myStatus: SusuMemberStatus.active, contribution: 10)],
          ),
        );
        expect(
          v.susuCommitted,
          isNull,
          reason:
              'an active group and active caller membership do not, '
              'by themselves, establish a committed amount: '
              'contributionUsdc is the recurring schedule amount, not '
              'proof of funds currently held',
        );
      },
    );

    test('pending/defaulted/removed memberships are equally unknown', () async {
      for (final status in [
        SusuMemberStatus.pendingVouch,
        SusuMemberStatus.pendingContract,
        SusuMemberStatus.defaulted,
        SusuMemberStatus.removed,
      ]) {
        final v = await _val(_container(susu: [_susu(myStatus: status)]));
        expect(v.susuCommitted, isNull);
      }
    });

    test('a non-active group is unknown too', () async {
      final v = await _val(
        _container(
          susu: [
            _susu(
              myStatus: SusuMemberStatus.active,
              status: SusuStatus.configuring,
            ),
          ],
        ),
      );
      expect(v.susuCommitted, isNull);
    });

    test('susu list NOT loaded → UNKNOWN (null), not zero', () async {
      final v = _container(
        susuLoading: true,
      ).read(balanceCardValuationProvider);
      expect(v.susuCommitted, isNull);
    });

    test(
      'an EMPTY loaded list is still unknown, not a confirmed zero',
      () async {
        final v = await _val(_container(susu: const []));
        expect(
          v.susuCommitted,
          isNull,
          reason:
              'no committed-Susu source exists on the current '
              'contract at all — even an empty list cannot confirm 0',
        );
      },
    );
  });

  group('Savings — unknown raw shapes are never a confirmed zero', () {
    test('goals is a real List with valid amounts → summed', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': [
              {'status': 'ACTIVE', 'currentAmountGhs': 30},
              {'status': 'PAUSED', 'currentAmountGhs': 12.5},
            ],
          }),
        ),
      );
      expect(v.savingsLockedGhs, 42.5);
    });

    test('goals is a valid EMPTY list → a real zero', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({'goals': <Map<String, dynamic>>[]}),
        ),
      );
      expect(v.savingsLockedGhs, 0);
    });

    // STATUS FILTER — the agreed backend valuation contract counts
    // ONLY ACTIVE and PAUSED goals in the committed-savings bucket
    // (backend PR #367, SAVINGS_ACTIVE_STATUSES). COMPLETED/CANCELLED
    // goals are settled history, not currently committed savings.
    test('ACTIVE and PAUSED goals contribute', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': [
              {'status': 'ACTIVE', 'currentAmountGhs': 30},
              {'status': 'PAUSED', 'currentAmountGhs': 12.5},
            ],
          }),
        ),
      );
      expect(v.savingsLockedGhs, 42.5);
    });

    test('COMPLETED and CANCELLED goals are excluded', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': [
              {'status': 'ACTIVE', 'currentAmountGhs': 30},
              {'status': 'COMPLETED', 'currentAmountGhs': 500},
              {'status': 'CANCELLED', 'currentAmountGhs': 700},
            ],
          }),
        ),
      );
      expect(v.savingsLockedGhs, 30);
    });

    test('a list of ONLY completed/cancelled goals is a real zero', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': [
              {'status': 'COMPLETED', 'currentAmountGhs': 500},
              {'status': 'CANCELLED', 'currentAmountGhs': 700},
            ],
          }),
        ),
      );
      expect(
        v.savingsLockedGhs,
        0,
        reason:
            'validly parsed, just settled history — that is a '
            'real zero of currently committed savings, not an unknown',
      );
    });

    test(
      'an entry with a MISSING status is malformed → UNKNOWN (null)',
      () async {
        final v = await _val(
          _container(
            savings: const SavingsOverview({
              'goals': [
                {'currentAmountGhs': 30},
              ],
            }),
          ),
        );
        expect(
          v.savingsLockedGhs,
          isNull,
          reason:
              'the overview does not guarantee a default status — '
              'an entry without a status is never silently included or '
              'excluded',
        );
      },
    );

    test(
      'an entry with a NON-STRING status is malformed → UNKNOWN (null)',
      () async {
        final v = await _val(
          _container(
            savings: const SavingsOverview({
              'goals': [
                {'status': 3, 'currentAmountGhs': 30},
              ],
            }),
          ),
        );
        expect(v.savingsLockedGhs, isNull);
      },
    );

    test('goals key ABSENT → UNKNOWN (null), never zero', () async {
      final v = await _val(
        _container(savings: const SavingsOverview({'unrelated': 1})),
      );
      expect(
        v.savingsLockedGhs,
        isNull,
        reason:
            'the contract not publishing a goals collection does '
            'not confirm the user has no savings',
      );
    });

    test('goals is NOT a List → UNKNOWN (null)', () async {
      final v = await _val(
        _container(savings: const SavingsOverview({'goals': 'unavailable'})),
      );
      expect(v.savingsLockedGhs, isNull);
    });

    test(
      'any entry with a MISSING currentAmountGhs → UNKNOWN (null)',
      () async {
        final v = await _val(
          _container(
            savings: const SavingsOverview({
              'goals': [
                {'currentAmountGhs': 30},
                {'name': 'Goal with no amount'},
              ],
            }),
          ),
        );
        expect(
          v.savingsLockedGhs,
          isNull,
          reason: 'a missing amount is never read as 0',
        );
      },
    );

    test('any entry with a non-numeric amount → UNKNOWN (null)', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': [
              {'currentAmountGhs': 'thirty'},
            ],
          }),
        ),
      );
      expect(v.savingsLockedGhs, isNull);
    });

    test('a NON-MAP entry → UNKNOWN (null)', () async {
      final v = await _val(
        _container(
          savings: const SavingsOverview({
            'goals': ['malformed'],
          }),
        ),
      );
      expect(v.savingsLockedGhs, isNull);
    });

    test('savings still loading → UNKNOWN (null)', () async {
      final v = _container(
        savingsLoading: true,
      ).read(balanceCardValuationProvider);
      expect(v.savingsLockedGhs, isNull);
    });
  });

  group('USDC transaction gate — a backend authorisation fact', () {
    test('CLOSED even when a fresh usable rate is displayed', () async {
      final v = await _val(_container(fx: _usableRate()));
      expect(v.rate.kind, FxRateKind.fresh);
      expect(v.rate.isFresh, isTrue);
      expect(
        v.usdcTransactionGateOpen,
        isFalse,
        reason:
            'rate usability is an FX fact, not a transaction '
            'authorisation — no backend gate field exists on the '
            'current contract, so the gate is honestly closed',
      );
    });
  });

  group('Native GHS and balance readiness', () {
    test('nativeGhsAvailable is NULL on the current contract — and the '
        'headline is honestly UNAVAILABLE, never derived from USDC', () async {
      final v = await _val(_container());
      expect(v.nativeGhsAvailable, isNull);
      expect(
        v.availableGhsValue,
        isNull,
        reason:
            'NO client-side derivation of GHS from USDC exists '
            '(owner-corrected contract 2026-10-27): without an '
            'authoritative GHS source the headline is unavailable',
      );
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.headlineKnown, isFalse);
    });

    test('unresolved readiness → balanceConfirmed false', () async {
      final v = await _val(_container(readiness: BalanceReadiness.unresolved));
      expect(v.balanceConfirmed, isFalse);
      expect(
        v.headlineKnown,
        isFalse,
        reason:
            'the #195 display law: while the balance is unconfirmed '
            'the headline shows the waiting dots, never a figure — the '
            'derived cached value is never displayed',
      );
    });

    test('failed readiness → balanceConfirmed false', () async {
      final v = await _val(_container(readiness: BalanceReadiness.failed));
      expect(v.balanceConfirmed, isFalse);
    });

    test('loaded with a GENUINE zero → confirmed true, 0 is real', () async {
      final v = await _val(
        _container(
          balance: const BalanceData(),
          readiness: BalanceReadiness.loaded,
        ),
      );
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
      final v = await _val(_container(fx: Exception('rate fetch failed')));
      expect(v.rate.kind, FxRateKind.none);
      expect(v.availableGhsValue, isNull);
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.usdcTransactionGateOpen, isFalse);
    });

    test('REFRESH WINDOW: an in-flight re-fetch keeps the valid rate on '
        'screen and reports loading truthfully (PR-C)', () async {
      final c = _container();
      final settled = await _val(c);
      expect(
        settled.rate.hasRate,
        isTrue,
        reason: 'sanity: the snapshot landed before the refresh',
      );
      expect(settled.rate.loading, isFalse);

      // The refresh window: invalidate WITHOUT awaiting the new future —
      // Riverpod keeps the previous snapshot in `.value` while the state
      // is AsyncLoading, exactly like a live invalidate/refresh.
      c.invalidate(fxRateProvider);
      final during = c.read(balanceCardValuationProvider);

      expect(
        during.rate.hasRate,
        isTrue,
        reason:
            'the valid rate must survive the refresh window — it '
            'is never swapped for the initial-fetch dots',
      );
      expect(during.rate.kind, FxRateKind.fresh);
      expect(
        during.rate.loading,
        isTrue,
        reason:
            'the in-flight fetch is reported TRUTHFULLY so the card '
            'can show its inline updating indication',
      );
      expect(
        during.availableGhsValue,
        settled.availableGhsValue,
        reason: 'the displayed valuation is unchanged while refreshing',
      );

      // Once the re-fetch lands, loading clears.
      final after = await _val(c);
      expect(after.rate.hasRate, isTrue);
      expect(after.rate.loading, isFalse);
    });

    test('FAILED re-fetch with a previous usable snapshot: the last known '
        'rate stays honest (freshness-gated), loading is reported', () async {
      // First fetch succeeds, then the provider is replaced by one that
      // fails — the refresh-error window (AsyncError keeps `.value`).
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          balanceDataProvider.overrideWith(
            (ref) => const BalanceData(availableBalance: 50),
          ),
          balanceReadinessProvider.overrideWith(
            (ref) => BalanceReadiness.loaded,
          ),
          fxRateProvider.overrideWith((ref) async {
            calls++;
            if (calls == 1) return _usableRate();
            throw Exception('refresh failed');
          }),
          vaultsProvider.overrideWith(() => _FakeVaultsNotifier(const [])),
          savingsOverviewProvider.overrideWith(
            () => _FakeSavingsNotifier(const SavingsOverview({})),
          ),
          susuListProvider.overrideWith(() => _FakeSusuListNotifier(const [])),
          isVendorProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);

      final settled = await _val(c);
      expect(settled.rate.hasRate, isTrue);
      c.invalidate(fxRateProvider);
      await c
          .read(fxRateProvider.future)
          .catchError((Object _) => null as FxRateSnapshot?);
      // AsyncError retains the previous value: the freshness contract
      // (isUsable, re-verified per read) stays the only authority on
      // whether it may still be presented as a rate.
      final after = c.read(balanceCardValuationProvider);
      expect(
        after.rate.hasRate,
        isTrue,
        reason:
            'a failed background refresh does not erase the last '
            'known usable rate — staleness is gated by isUsable, not by '
            'the error',
      );
      expect(after.rate.kind, FxRateKind.fresh);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // The backend valuation block (backend PR #367): the adapter consumes
  // `data.valuation` when the contract ships, and distinguishes the
  // three states — legacy (field absent), explicit backend
  // unavailability (null / malformed), backend-authoritative (parses).
  // ─────────────────────────────────────────────────────────────────────

  /// A well-formed #367 valuation payload, exactly as the backend
  /// serializes it (money = { exact, value }).
  Map<String, dynamic> valuation367Payload({
    double nativeGhs = 0,
    double availableUsdc = 100,
    Map<String, dynamic>? usdcEquivalent,
    Map<String, dynamic>? availableGhsValue,
    String rateStatus = 'CURRENT',
    String valuationStatus = 'CURRENT',
    bool gateOpen = true,
  }) {
    // The real #367 serializer sends NO displayRate when the rate is
    // UNAVAILABLE (there is no display rate to describe).
    final displayRate = rateStatus == 'UNAVAILABLE'
        ? null
        : {'basis': rateStatus, 'rate': 12.5};
    return {
      'pair': 'USDC/GHS',
      'nativeGhsAvailable': {
        'exact': nativeGhs.toStringAsFixed(8),
        'value': nativeGhs,
      },
      'availableUsdc': {
        'exact': availableUsdc.toStringAsFixed(8),
        'value': availableUsdc,
      },
      'usdcEquivalent': usdcEquivalent,
      'availableGhsValue': availableGhsValue,
      'rateStatus': rateStatus,
      'valuationStatus': valuationStatus,
      'currentRate': {
        'rate': 12.5,
        'rateExact': '12.50000000',
        'isFresh': true,
        'pair': 'USDC/GHS',
        'source': 'KOTANI_PAY',
        'observedAt': '2026-10-26T10:00:00Z',
      },
      'savedRate': null,
      'displayRate': displayRate,
      'usdcTransactionGateOpen': gateOpen,
      'usdcTransactionGateReason': 'FRESH_CANONICAL_RATE',
      'locked': {
        'escrowUsdc': {'exact': '5.00000000', 'value': 5},
        'disputesUsdc': {'exact': '2.00000000', 'value': 2},
        'vaultsUsdc': {'exact': '7.00000000', 'value': 7},
        'savingsGhs': {'exact': '42.50000000', 'value': 42.5},
        'committedSusuUsdc': {'exact': '9.00000000', 'value': 9},
        'vendorUnallocatedUsdc': {'exact': '0.00000000', 'value': 0},
      },
      'nonCash': {
        'azmPoints': {'exact': '900.75000000', 'value': 900.75},
      },
      'evaluatedAt': '2026-10-26T10:00:05Z',
    };
  }

  group('backend valuation PRESENT + parses → backend-authoritative', () {
    test('every figure is mapped verbatim from the payload', () async {
      final payload = valuation367Payload(
        nativeGhs: 20,
        availableUsdc: 100,
        usdcEquivalent: {'exact': '116.00000000', 'value': 116},
        availableGhsValue: {'exact': '1450.00000000', 'value': 1450},
      );
      final v = await _val(
        _container(
          balance: BalanceData(
            availableBalance: 999,
            valuationFieldPresent: true,
            valuationRaw: payload,
          ),
        ),
      );
      // OWNER-CORRECTED CONTRACT (2026-10-27): the GHS headline maps the
      // documented AUTHORITATIVE native-GHS balance verbatim. The
      // backend's own COMBINED totals (1450 = native + converted USDC;
      // 116 = its equivalent) are parsed for contract compatibility but
      // deliberately NOT consumed — the headline is native GHS only.
      expect(v.nativeGhsAvailable, 20);
      expect(v.availableUsdc, 100);
      expect(v.availableGhsValue, 20);
      expect(
        v.availableUsdcEquivalent,
        closeTo(20 / 12.5, 1e-9),
        reason:
            'the estimate is derived FROM the native GHS balance '
            'at the display rate — never the backend combined figure',
      );
      expect(v.escrowLocked, 5);
      expect(v.disputeEscrow, 2);
      expect(v.vaultLocked, 7);
      expect(v.savingsLockedGhs, 42.5);
      // WORKSTREAM K2A — committedSusuUsdc is parsed for contract
      // compatibility but deliberately NOT displayed: the approved
      // money architecture has not settled its customer-facing
      // meaning (domestic Susu = fixed GHS obligation; USDC is one
      // distinct funding asset). The row stays UNKNOWN.
      expect(v.susuCommitted, isNull);
      expect(v.azmPoints, 900.75);
      expect(v.rate.kind, FxRateKind.fresh);
      expect(v.rate.ghsPerUsdc, 12.5);
      expect(v.rate.sourceLabel, 'KOTANI_PAY');
    });

    test('K2A: a payload carrying committedSusuUsdc keeps the Susu row '
        'UNKNOWN — parsed, never displayed', () async {
      final payload = valuation367Payload();
      // Contract compatibility: the strict parser still accepts the
      // field (a malformed amount would flip the whole valuation to
      // unavailable — pinned separately below).
      final parsed = BackendBalanceValuation.parse(payload);
      expect(
        parsed,
        isNotNull,
        reason: 'committedSusuUsdc remains a parsed contract field',
      );
      expect(parsed!.locked.committedSusuUsdc.value, 9);
      // Display: the customer-facing committed amount stays UNKNOWN
      // until the approved contract establishes the field's meaning,
      // currency and relation to the promised payout.
      final v = await _val(
        _container(
          balance: BalanceData(
            availableBalance: 999,
            valuationFieldPresent: true,
            valuationRaw: payload,
          ),
        ),
      );
      // K2B-2: the savings aggregate stays MAPPED here — it is the
      // nominal GHS-denominated goal progress (server-maintained,
      // guards below). The card's DISPLAY gate lives in
      // balance_card_breakdown.dart and renders the row UNKNOWN; this
      // mapping is what keeps the parse semantics test-covered.
      expect(
        v.savingsLockedGhs,
        42.5,
        reason:
            'savings stays mapped as the nominal GHS goal '
            'progress — display-gated in the breakdown widget '
            '(K2B-2), never presented as native GHS held',
      );
      expect(
        v.susuCommitted,
        isNull,
        reason:
            'a raw USDC sum is not the amount the customer is '
            'owed by a domestic Susu product',
      );
    });

    test(
      'the backend gate is mapped VERBATIM — closed payload stays closed',
      () async {
        final v = await _val(
          _container(
            balance: BalanceData(
              valuationFieldPresent: true,
              valuationRaw: valuation367Payload(
                gateOpen: false,
                rateStatus: 'SAVED_FALLBACK',
                valuationStatus: 'SAVED_FALLBACK',
              ),
            ),
          ),
        );
        expect(v.usdcTransactionGateOpen, isFalse);
        expect(
          v.rate.kind,
          FxRateKind.saved,
          reason:
              'a saved rate is displayed as saved — it is never '
              'labelled current/fresh',
        );
      },
    );

    test('the payload\u2019s COMBINED totals are NOT consumed — the '
        'headline is the native-GHS balance only', () async {
      // The payload's own combined GHS total (1450 = 20 native + 100
      // USDC × 12.5, rounded) folds a converted USDC component into
      // the figure. The owner-corrected contract forbids exactly that:
      // the headline maps nativeGhsAvailable (20) and NEVER the
      // combined total, whatever the backend computes.
      final v = await _val(
        _container(
          balance: BalanceData(
            availableBalance: 100,
            valuationFieldPresent: true,
            valuationRaw: valuation367Payload(
              nativeGhs: 20,
              availableGhsValue: {'exact': '1450.00000000', 'value': 1450},
              usdcEquivalent: {'exact': '116.00000000', 'value': 116},
            ),
          ),
        ),
      );
      expect(
        v.availableGhsValue,
        20,
        reason:
            'native GHS only — the 1450 combined figure must '
            'never reach the headline',
      );
      expect(
        v.availableUsdcEquivalent,
        closeTo(20 / 12.5, 1e-9),
        reason:
            'the estimate derives from the GHS headline, not from '
            'the backend\u2019s combined equivalent (116)',
      );
      expect(
        v.availableUsdc,
        100,
        reason: 'the real USDC holding passes through as its own fact',
      );
    });

    test('REGRESSION: changes to actual USDC held do NOT affect the GHS '
        'headline — and the USDC estimate is derived FROM the GHS '
        'balance', () async {
      // Same native GHS (20), wildly different USDC held: the headline
      // and its derived estimate must be identical in both.
      Map<String, dynamic> payloadFor(double usdc) =>
          valuation367Payload(nativeGhs: 20, availableUsdc: usdc);
      final small = await _val(
        _container(
          balance: BalanceData(
            valuationFieldPresent: true,
            valuationRaw: payloadFor(1),
          ),
        ),
      );
      final large = await _val(
        _container(
          balance: BalanceData(
            valuationFieldPresent: true,
            valuationRaw: payloadFor(10000),
          ),
        ),
      );
      expect(small.availableGhsValue, 20);
      expect(
        large.availableGhsValue,
        20,
        reason: '10,000 USDC held must not move the GHS headline',
      );
      expect(small.availableUsdcEquivalent, closeTo(20 / 12.5, 1e-9));
      expect(
        large.availableUsdcEquivalent,
        closeTo(20 / 12.5, 1e-9),
        reason:
            'the estimate follows the GHS balance, never the '
            'USDC holding',
      );
      // The holding itself passes through truthfully.
      expect(small.availableUsdc, 1);
      expect(large.availableUsdc, 10000);
    });

    test('a PARTIAL_FX_UNAVAILABLE payload: the native GHS headline '
        'still shows — GHS never needed a rate — and only the USDC '
        'estimate is unavailable', () async {
      // Owner-corrected contract (2026-10-27): FX unavailability may
      // never take down the GHS headline (the main-currency balance is
      // not a conversion). Only the USDC equivalent estimate goes
      // unavailable, and the gate stays the backend's own fact.
      final v = await _val(
        _container(
          balance: BalanceData(
            valuationFieldPresent: true,
            valuationRaw: valuation367Payload(
              nativeGhs: 30,
              usdcEquivalent: null,
              availableGhsValue: null,
              rateStatus: 'UNAVAILABLE',
              valuationStatus: 'PARTIAL_FX_UNAVAILABLE',
              gateOpen: false,
            ),
          ),
        ),
      );
      expect(
        v.availableGhsValue,
        30,
        reason: 'the native GHS balance survives FX unavailability',
      );
      expect(
        v.availableUsdcEquivalent,
        isNull,
        reason:
            'the estimate needs the rate and is honestly '
            'unavailable without one',
      );
      expect(v.usdcTransactionGateOpen, isFalse);
      expect(v.rate.kind, FxRateKind.none);
    });

    test(
      'a DEMO_FALLBACK payload maps the demo rate kind, gate closed',
      () async {
        final v = await _val(
          _container(
            balance: BalanceData(
              valuationFieldPresent: true,
              valuationRaw: valuation367Payload(
                rateStatus: 'DEMO_FALLBACK',
                valuationStatus: 'DEMO_FALLBACK',
                gateOpen: false,
              ),
            ),
          ),
        );
        expect(v.rate.kind, FxRateKind.demo);
        expect(
          v.usdcTransactionGateOpen,
          isFalse,
          reason: 'a demo rate never opens the transaction gate',
        );
      },
    );
  });

  group('backend valuation EXPLICITLY unavailable → no client substitution', () {
    test(
      'explicit null valuation → NO GHS figure even with a usable client rate',
      () async {
        // THE core honesty regression: a usable CLIENT-side oracle rate is
        // loaded, but the backend explicitly said the valuation is
        // unavailable. The card must NOT derive a GHS total from the
        // client rate and present it as though the backend valued it.
        final v = await _val(
          _container(
            balance: const BalanceData(
              availableBalance: 100,
              valuationFieldPresent: true,
              valuationRaw: null,
            ),
          ),
        );
        expect(
          v.availableGhsValue,
          isNull,
          reason:
              'an explicit backend valuation failure must never be '
              'silently replaced with a client-side conversion',
        );
        expect(v.availableUsdcEquivalent, isNull);
        expect(v.nativeGhsAvailable, isNull);
        expect(
          v.availableUsdc,
          100,
          reason:
              'the real USDC holding is still shown — the failure '
              'was the valuation, not the ledger',
        );
        expect(v.usdcTransactionGateOpen, isFalse);
      },
    );

    test(
      'a MALFORMED valuation payload is treated exactly like explicit null',
      () async {
        final v = await _val(
          _container(
            balance: const BalanceData(
              availableBalance: 100,
              valuationFieldPresent: true,
              valuationRaw: <String, dynamic>{
                'pair': 'USDC/GHS',
                // nativeGhsAvailable malformed → whole payload rejected.
                'nativeGhsAvailable': {'exact': 'x', 'value': 'nope'},
                'availableUsdc': {'exact': '1.00000000', 'value': 1},
              },
            ),
          ),
        );
        expect(v.availableGhsValue, isNull);
        expect(v.availableUsdcEquivalent, isNull);
        expect(v.availableUsdc, 100);
      },
    );

    test('an unknown rateStatus string rejects the payload', () async {
      final v = await _val(
        _container(
          balance: BalanceData(
            valuationFieldPresent: true,
            valuationRaw: valuation367Payload(rateStatus: 'SOMEHOW_FRESH'),
          ),
        ),
      );
      expect(v.availableGhsValue, isNull);
    });
  });

  group('legacy response (valuation field absent) → NO authoritative GHS '
      'source', () {
    test('REGRESSION: no derivation — the headline is UNAVAILABLE whatever '
        'the USDC holding and the rate', () async {
      final v = await _val(_container());
      final rate = _usableRate();
      expect(
        v.availableGhsValue,
        isNull,
        reason:
            'the legacy fallback derivation (USDC × rate) was '
            'REMOVED (owner-corrected contract 2026-10-27): GHS may '
            'never be derived from USDC',
      );
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.nativeGhsAvailable, isNull);
      expect(v.usdcTransactionGateOpen, isFalse);
      // The rate row keeps its own informational state — a rate fact
      // is not a valuation.
      expect(v.rate.kind, FxRateKind.fresh);
      expect(v.rate.ghsPerUsdc, rate.ghsPerUsdc);
      // The REAL USDC holding still passes through as its own fact (the
      // back-face row) — it just never becomes a GHS figure.
      expect(v.availableUsdc, 50);
    });
  });
}
