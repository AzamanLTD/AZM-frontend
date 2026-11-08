// test/presence/presence_controller_test.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE: CLIENT ACCEPTANCE TESTS (Part 6.10, packet 4-A)
//
// Everything here runs on the FAKE scanner and the FAKE gateway. No BLE
// package, no platform channel, no network, no delays.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/services/presence/beacon_key.dart';
import 'package:azaman/services/presence/presence_config.dart';
import 'package:azaman/services/presence/presence_gateway.dart';
import 'package:azaman/services/presence/presence_models.dart';
import 'package:azaman/services/presence/presence_scanner.dart';

const String kUuid = 'f7826da64fa24e988024bc5b71e0893e';

PresenceCandidate candidate(String id, {String hint = 'near', String? name}) =>
    PresenceCandidate(
      locationId: id,
      businessId: 'biz-$id',
      businessName: name ?? 'Azaman Mart',
      branchName: 'Osu',
      storefrontMode: StorefrontMode.catalogueAndPayment,
      proximityHint: hint,
    );

/// One controller + its fakes, wired through a real ProviderContainer so the
/// production providers are overridden exactly as the app would resolve them.
class Harness {
  Harness._();

  static Future<Harness> create({
    FakePresenceScenario scenario = FakePresenceScenario.foundOne,
    List<PresenceCandidate> candidates = const [],
    bool unlocked = true,
    bool discovery = true,
    bool gatewayAvailable = true,
    bool flagOn = true,
  }) async {
    AppConfig.setPresenceOverrideForTest(flagOn);
    final h = Harness._();
    h.scanner = FakePresenceScanner(scenario: scenario);
    h.gateway = FakePresenceGateway(
      candidates: candidates,
      available: gatewayAvailable,
    );
    h.container = ProviderContainer(
      overrides: [
        presenceScannerProvider.overrideWithValue(h.scanner),
        presenceApiGatewayProvider.overrideWithValue(h.gateway),
      ],
    );
    // Preferences persist asynchronously — await so the scan sees the value.
    await h.container
        .read(presencePreferencesProvider.notifier)
        .setNearbyDiscovery(discovery);
    // MoneyAccessController starts LOCKED; unlock it the real way.
    final money = h.container.read(moneyAccessProvider);
    if (unlocked) {
      money.finishUnlock(money.beginUnlock());
    } else {
      money.lock();
    }
    h.controller = NearbyPresenceController(
      h.container.read,
      scanner: h.scanner,
      gateway: h.gateway,
      tuning: PresenceTuning.fast,
    );
    return h;
  }

  late final FakePresenceScanner scanner;
  late final FakePresenceGateway gateway;
  late final ProviderContainer container;
  late final NearbyPresenceController controller;

  void dispose() {
    controller.dispose();
    container.dispose();
    AppConfig.setPresenceOverrideForTest(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.setPresenceOverrideForTest(null);
  });

  tearDown(() => AppConfig.setPresenceOverrideForTest(null));

  // ── Canonical beacon key ────────────────────────────────────────────────
  group('canonical beacon key (one path)', () {
    test('iBeacon key is normalised and idempotent', () {
      final k = beaconKeyForIBeacon(
        uuid: kUuid.toUpperCase(),
        major: 1,
        minor: 101,
      );
      expect(k, 'IBEACON:$kUuid:1:101');
      expect(canonicalBeaconKey(k), k);
    });

    test('uuid with hyphens and braces canonicalises to the same key', () {
      const dashed = 'F7826DA6-4FA2-4E98-8024-BC5B71E0893E';
      expect(
        beaconKeyForIBeacon(uuid: dashed, major: '1', minor: '101'),
        'IBEACON:$kUuid:1:101',
      );
    });

    test('Eddystone key requires exact hex widths', () {
      expect(
        beaconKeyForEddystoneUid(
          namespace: '00112233445566778899',
          instance: 'aabbccddeeff',
        ),
        'EDDYSTONE_UID:00112233445566778899:aabbccddeeff',
      );
      expect(
        () => beaconKeyForEddystoneUid(
          namespace: 'abc',
          instance: 'aabbccddeeff',
        ),
        throwsA(isA<BeaconKeyException>()),
      );
    });

    test('malformed keys are rejected, never trusted', () {
      expect(canonicalBeaconKey(''), isNull);
      expect(canonicalBeaconKey('IBEACON:nope'), isNull);
      expect(canonicalBeaconKey('CUSTOM:aa:bb'), isNull);
      expect(isValidBeaconKey('EDDYSTONE_UID:zz:aabbccddeeff'), isFalse);
    });

    test('out-of-range major/minor rejected', () {
      expect(
        () => beaconKeyForIBeacon(uuid: kUuid, major: 70000, minor: 1),
        throwsA(isA<BeaconKeyException>()),
      );
      expect(
        () => beaconKeyForIBeacon(uuid: kUuid, major: -1, minor: 1),
        throwsA(isA<BeaconKeyException>()),
      );
    });
  });

  // ── Every outcome maps to a state ───────────────────────────────────────
  group('PresenceScanOutcome → state transitions', () {
    test('foundOne → PresenceFoundOne', () async {
      final h = await Harness.create(candidates: [candidate('b1')]);
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.controller.state, isA<PresenceFoundOne>());
    });

    test('foundMany → PresenceFoundMany', () async {
      final h = await Harness.create(
        scenario: FakePresenceScenario.foundMany,
        candidates: [candidate('b1'), candidate('b2'), candidate('b3')],
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      final s = h.controller.state as PresenceFoundMany;
      expect(s.candidates.length, 3);
    });

    test('none → PresenceNone', () async {
      final h = await Harness.create(scenario: FakePresenceScenario.none);
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.controller.state, isA<PresenceNone>());
      expect((h.controller.state as PresenceNone).explicit, isFalse);
    });

    test('bluetoothOff → blocked(bluetoothOff)', () async {
      final h = await Harness.create(
        scenario: FakePresenceScenario.bluetoothOff,
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.bluetoothOff,
      );
    });

    test('permissionDenied → blocked(permissionDenied)', () async {
      final h = await Harness.create(
        scenario: FakePresenceScenario.permissionDenied,
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.permissionDenied,
      );
    });

    test('permissionPermanentlyDenied → blocked, non-blocking state', () async {
      final h = await Harness.create(
        scenario: FakePresenceScenario.permissionPermanentlyDenied,
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.permissionPermanentlyDenied,
      );
    });

    test('unsupported → blocked(unsupported)', () async {
      final h = await Harness.create(
        scenario: FakePresenceScenario.unsupported,
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.unsupported,
      );
    });

    test('failed → PresenceError', () async {
      final h = await Harness.create(scenario: FakePresenceScenario.failed);
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.controller.state, isA<PresenceError>());
    });
  });

  // ── Gates ───────────────────────────────────────────────────────────────
  group('privacy gates', () {
    test('feature flag OFF → invisible, no scanner, no gateway call', () async {
      final h = await Harness.create(
        flagOn: false,
        candidates: [candidate('b1')],
      );
      addTearDown(h.dispose);
      expect(h.controller.isFeatureVisible, isFalse);
      await h.controller.requestScan();
      expect(h.scanner.scanCount, 0, reason: 'must not scan');
      expect(h.gateway.challengeCalls, 0, reason: 'must not call the API');
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.featureFlagOff,
      );
    });

    test('discovery preference OFF → no scan, no permission prompt', () async {
      final h = await Harness.create(
        discovery: false,
        candidates: [candidate('b1')],
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.scanner.scanCount, 0);
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.preferenceOff,
      );
    });

    test('locked app → blocked, no scan', () async {
      final h = await Harness.create(
        unlocked: false,
        candidates: [candidate('b1')],
      );
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.scanner.scanCount, 0);
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.appLocked,
      );
    });

    test('gateway unavailable (routes not deployed) → invisible', () async {
      final h = await Harness.create(gatewayAvailable: false);
      addTearDown(h.dispose);
      expect(h.controller.isFeatureVisible, isFalse);
    });

    test('all three preferences default OFF and are independent', () async {
      SharedPreferences.setMockInitialValues({});
      final p = PresencePreferencesNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(p.state, PresencePreferences.allOff);
      expect(p.state.nearbyDiscovery, isFalse);
      expect(p.state.presenceNotifications, isFalse);
      expect(p.state.personalisation, isFalse);

      await p.setNearbyDiscovery(true);
      expect(p.state.nearbyDiscovery, isTrue);
      expect(
        p.state.presenceNotifications,
        isFalse,
        reason: 'enabling discovery must not enable notifications',
      );
      expect(
        p.state.personalisation,
        isFalse,
        reason: 'enabling discovery must not enable personalisation',
      );
    });
  });

  // ── Throttle ────────────────────────────────────────────────────────────
  group('scan throttle', () {
    test('minimum interval blocks an immediate second scan', () async {
      final h = await Harness.create(candidates: [candidate('b1')]);
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.scanner.scanCount, 1);
      await h.controller.requestScan();
      expect(h.scanner.scanCount, 1, reason: '20 s minimum gap');
      expect(
        (h.controller.state as PresenceBlocked).reason,
        PresenceBlockReason.throttled,
      );
    });

    test('at most 4 starts per 30 s window', () async {
      AppConfig.setPresenceOverrideForTest(true);
      addTearDown(() => AppConfig.setPresenceOverrideForTest(null));
      var now = DateTime.utc(2026, 1, 1, 12);
      final scanner = FakePresenceScanner(scenario: FakePresenceScenario.none);
      final gateway = FakePresenceGateway();
      final container = ProviderContainer(
        overrides: [
          presenceScannerProvider.overrideWithValue(scanner),
          presenceApiGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(presencePreferencesProvider.notifier)
          .setNearbyDiscovery(true);
      final money = container.read(moneyAccessProvider);
      money.finishUnlock(money.beginUnlock());

      final c = NearbyPresenceController(
        container.read,
        scanner: scanner,
        gateway: gateway,
        // Production rate-limit window (4 starts / 30 s) with a 1 s minimum
        // gap, so the test drives the real budget without waiting 20 s.
        tuning: const PresenceTuning(minScanInterval: Duration(seconds: 1)),
        clock: () => now,
      );
      addTearDown(c.dispose);

      for (var i = 0; i < 4; i++) {
        await c.requestScan();
        now = now.add(const Duration(seconds: 6));
      }
      expect(scanner.scanCount, 4);
      await c.requestScan();
      expect(
        scanner.scanCount,
        4,
        reason: '5th start inside 30 s must be refused',
      );
      expect(
        (c.state as PresenceBlocked).reason,
        PresenceBlockReason.throttled,
      );

      // After the window drains, scanning is allowed again.
      now = now.add(const Duration(seconds: 31));
      await c.requestScan();
      expect(scanner.scanCount, 5);
    });
  });

  // ── Stale results ───────────────────────────────────────────────────────
  group('stale-event protection', () {
    test('a slow scan cannot replace a newer result', () async {
      AppConfig.setPresenceOverrideForTest(true);
      addTearDown(() => AppConfig.setPresenceOverrideForTest(null));
      var now = DateTime.utc(2026, 1, 1, 12);
      final scanner = FakePresenceScanner(
        scenario: FakePresenceScenario.manual,
      );
      final gateway = FakePresenceGateway(candidates: [candidate('b1')]);
      final container = ProviderContainer(
        overrides: [
          presenceScannerProvider.overrideWithValue(scanner),
          presenceApiGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(presencePreferencesProvider.notifier)
          .setNearbyDiscovery(true);
      final money = container.read(moneyAccessProvider);
      money.finishUnlock(money.beginUnlock());

      final c = NearbyPresenceController(
        container.read,
        scanner: scanner,
        gateway: gateway,
        tuning: PresenceTuning.fast,
        clock: () => now,
      );
      addTearDown(c.dispose);

      // Scan A starts and hangs.
      final a = c.requestScan();
      await Future<void>.delayed(Duration.zero);
      expect(scanner.pendingCount, 1);

      // Cancel A and start B after the minimum gap.
      c.cancel();
      now = now.add(const Duration(seconds: 25));
      final b = c.requestScan();
      await Future<void>.delayed(Duration.zero);
      expect(scanner.pendingCount, 2);

      // B settles first: no candidates.
      scanner.completeManual(1, const ScanNone());
      await b;
      expect(c.state, isA<PresenceNone>());

      // A's result arrives late — it must be discarded.
      scanner.completeManual(
        0,
        ScanFound(FakePresenceScanner.defaultFoundOne(PresenceTuning.fast)),
      );
      await a;
      expect(
        c.state,
        isA<PresenceNone>(),
        reason: 'the stale scan must not overwrite the newer result',
      );
      expect(gateway.resolveCalls, 0);
    });
  });

  // ── Eligibility ─────────────────────────────────────────────────────────
  group('sample eligibility', () {
    test('a beacon with fewer than 2 samples is not a candidate', () async {
      const tuning = PresenceTuning.fast;
      final weak = [
        FakePresenceScanner.observation(
          beaconKey: FakePresenceScanner.keyIBeacon(kUuid, 1, 7),
          rssi: -50,
          sampleCount: 1,
          tuning: tuning,
        ),
      ];
      final h = await Harness.create(candidates: [candidate('b1')]);
      addTearDown(h.dispose);
      h.scanner.observations = weak;
      await h.controller.requestScan();
      expect(h.controller.state, isA<PresenceNone>());
      expect(
        h.gateway.resolveCalls,
        0,
        reason: 'no resolution without evidence',
      );
    });
  });

  // ── Session memory ──────────────────────────────────────────────────────
  group('session dismissal memory', () {
    test('a dismissed branch is not offered again in this session', () async {
      final h = await Harness.create(candidates: [candidate('b1')]);
      addTearDown(h.dispose);
      await h.controller.requestScan();
      expect(h.controller.state, isA<PresenceFoundOne>());
      h.controller.rememberChoice('b1', chosen: false);
      expect(h.controller.sessionDismissed, contains('b1'));
      expect(h.controller.state, isA<PresenceIdle>());
    });
  });

  // ── Worker test ─────────────────────────────────────────────────────────
  group('worker test', () {
    test('runs as workerTest purpose and emits no customer events', () async {
      final h = await Harness.create(candidates: [candidate('b1')]);
      addTearDown(h.dispose);
      final events = <PresenceEvent>[];
      h.controller.onCustomerEvent = events.add;

      final outcome = await h.controller.runWorkerTest();
      expect(outcome, isA<ScanFound>());
      expect(h.scanner.scannedPurposes, [PresenceScanPurpose.workerTest]);
      expect(
        events,
        isEmpty,
        reason: 'worker test must never emit customer events',
      );
      expect(h.gateway.challengeCalls, 0);
      expect(h.gateway.resolveCalls, 0);
    });
  });
}
