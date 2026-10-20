// =============================================================================
// AZAMAN — FX SNAPSHOT CONTRACT (PR #165 review §2)
//
// The backend's /api/oracle/rates freshness contract must be enforced on
// the client exactly as the backend computes it (rateFreshness.js +
// oracleRoutes.js): the gate is anchored to lastExternalSync, bounded by
// rateFreshnessMaxAgeSeconds, future-invalid beyond a 5s skew allowance,
// and NEVER refreshed by a local fetchedAt.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/currency_provider.dart';

void main() {
  // A fixed evaluation clock so age arithmetic is deterministic.
  final now = DateTime.utc(2026, 10, 20, 12, 0, 0);

  Map<String, dynamic> freshPayload({
    double rate = 13.42,
    DateTime? observed,
    bool isFresh = true,
    int? serverAge,
    double maxAge = 1800,
  }) {
    final obs = observed ?? now.subtract(const Duration(minutes: 5));
    return {
      'pair': 'USDC/GHS',
      'settlementCurrency': 'USDC',
      'displayCurrency': 'GHS',
      'liveRetailRate': rate,
      'liveUsdToGhs': 13.10,
      'rateSource': 'KOTANI_PAY',
      'lastSync': '2026-10-20T11:30:00.000Z',
      'lastExternalSync': obs.toIso8601String(),
      'isFresh': isFresh,
      'externalRateAgeSeconds': serverAge ?? 300,
      'rateFreshnessMaxAgeSeconds': maxAge,
    };
  }

  group('parseFxRateSnapshot — canonical freshness contract', () {
    test('a FRESH canonical snapshot is usable and keeps its fields', () {
      final snapshot = parseFxRateSnapshot(freshPayload(), now: now);

      expect(snapshot.ghsPerUsdc, 13.42);
      expect(snapshot.isCanonical, isTrue);
      expect(snapshot.isUsableAt(now), isTrue);
      expect(snapshot.pair, 'USDC/GHS');
      expect(snapshot.settlementCurrency, 'USDC');
      expect(snapshot.displayCurrency, 'GHS');
      expect(snapshot.source, 'KOTANI_PAY');
      expect(snapshot.serverFresh, isTrue);
      expect(snapshot.rateFreshnessMaxAgeSeconds, 1800);
      expect(snapshot.staleAt,
          snapshot.lastExternalSync!.add(const Duration(seconds: 1800)));
    });

    test('a STALE server observation is rejected — even freshly fetched '
        '(fetchedAt never makes an old observation fresh)', () {
      final snapshot = parseFxRateSnapshot(
        freshPayload(
          observed: now.subtract(const Duration(hours: 2)),
          isFresh: false,
          serverAge: 7200,
        ),
        now: now,
      );

      expect(snapshot.ghsPerUsdc, 13.42); // the rate is still readable
      expect(snapshot.isUsableAt(now), isFalse,
          reason: 'but it must never convert');
    });

    test('an observation at the exact threshold boundary is still usable; '
        'one second past it is not', () {
      final atLimit = parseFxRateSnapshot(
        freshPayload(observed: now.subtract(const Duration(seconds: 1800)),
            serverAge: 1800),
        now: now,
      );
      final pastLimit = parseFxRateSnapshot(
        freshPayload(
            observed: now.subtract(const Duration(seconds: 1801)),
            isFresh: false,
            serverAge: 1801),
        now: now,
      );

      expect(atLimit.isUsableAt(now), isTrue);
      expect(pastLimit.isUsableAt(now), isFalse);
    });

    test('a FUTURE-INVALID observation is rejected (beyond the 5s skew '
        'allowance it is untrusted, never infinitely fresh)', () {
      final slightlyFuture = parseFxRateSnapshot(
        freshPayload(observed: now.add(const Duration(seconds: 2)), serverAge: -2),
        now: now,
      );
      final farFuture = parseFxRateSnapshot(
        freshPayload(observed: now.add(const Duration(seconds: 60))),
        now: now,
      );

      expect(slightlyFuture.isUsableAt(now), isTrue,
          reason: 'benign skew within the allowance stays usable');
      expect(farFuture.isUsableAt(now), isFalse);
    });

    test('MISSING freshness metadata fails closed', () {
      // No lastExternalSync, no isFresh, no threshold at all.
      final snapshot = parseFxRateSnapshot({
        'pair': 'USDC/GHS',
        'settlementCurrency': 'USDC',
        'displayCurrency': 'GHS',
        'liveRetailRate': 13.42,
        'rateSource': 'KOTANI_PAY',
        'lastSync': '2026-10-20T11:30:00.000Z',
      }, now: now);

      expect(snapshot.isCanonical, isFalse,
          reason: 'freshness metadata is part of canonicity');
      expect(snapshot.isUsableAt(now), isFalse);
    });

    test('isFresh == false from the backend is rejected', () {
      final snapshot = parseFxRateSnapshot(
          freshPayload(isFresh: false, serverAge: 300),
          now: now);
      expect(snapshot.isUsableAt(now), isFalse);
    });

    test('a server age that CONTRADICTS ours is rejected as untrusted', () {
      // The server claims 5s old while its own timestamp computes 25
      // minutes old — contradictory metadata never converts.
      final snapshot = parseFxRateSnapshot(
        freshPayload(
          observed: now.subtract(const Duration(minutes: 25)),
          serverAge: 5,
        ),
        now: now,
      );
      expect(snapshot.isUsableAt(now), isFalse);
    });

    test('a NON-FINITE / non-positive threshold fails closed', () {
      for (final bad in [0.0, -600.0, double.nan, double.infinity]) {
        final snapshot =
            parseFxRateSnapshot(freshPayload(maxAge: bad), now: now);
        expect(snapshot.isUsableAt(now), isFalse,
            reason: 'rateFreshnessMaxAgeSeconds $bad must fail closed');
      }
    });

    test('usability EXPIRES with the clock: a retained snapshot that ages '
        'out stops converting with no refetch', () {
      final snapshot =
          parseFxRateSnapshot(freshPayload(), now: now);
      // 40 minutes later the same object is stale.
      final later = now.add(const Duration(minutes: 40));
      expect(snapshot.isUsableAt(later), isFalse,
          reason: 'the observation aged past the backend threshold');
    });

    test('the legacy USD/GHS fallback stays readable but never usable', () {
      final snapshot = parseFxRateSnapshot({
        'liveUsdToGhs': 13.10,
        'rateSource': 'LEGACY',
      }, now: now);

      expect(snapshot.ghsPerUsdc, 13.10);
      expect(snapshot.isCanonical, isFalse);
      expect(snapshot.isUsableAt(now), isFalse);
    });

    test('a zero canonical rate never becomes usable — the legacy '
        'headline fallback stays readable but unusable', () {
      final snapshot = parseFxRateSnapshot(
        freshPayload(rate: 0),
        now: now,
      );
      // The legacy liveUsdToGhs value remains readable for diagnostics…
      expect(snapshot.ghsPerUsdc, 13.10);
      // …but is explicitly non-canonical and never converts.
      expect(snapshot.isCanonical, isFalse);
      expect(snapshot.isUsableAt(now), isFalse);
    });
  });
}
