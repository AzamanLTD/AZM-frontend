// test/presence/contract_test.dart
// =============================================================================
// AZAMAN — PRESENCE CONTRACT CORRECTIONS (directive §A–§J)
//
// Pins the WIRE shape, not just the Dart objects: a field rename or an invented
// field is a contract break and must fail here.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/providers/nearby_scan_triggers.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/services/presence/presence_config.dart';
import 'package:azaman/services/presence/presence_gateway.dart';
import 'package:azaman/services/presence/presence_scanner.dart';

PresenceCandidate cand(String id) => PresenceCandidate(
  locationId: id,
  businessId: 'biz-$id',
  businessName: 'Azaman Mart',
  branchName: 'Osu',
  logoUrl: 'https://cdn/x.png',
  floor: '2',
  zone: 'Food court',
  proximityHint: 'near',
  storefrontMode: StorefrontMode.catalogueAndPayment,
  storefrontRoute: '/business/biz-$id',
);

class Rig {
  Rig._(this.container, this.controller, this.scanner, this.gateway);

  final ProviderContainer container;
  final NearbyPresenceController controller;
  final FakePresenceScanner scanner;
  final FakePresenceGateway gateway;

  static Future<Rig> create({
    bool discovery = true,
    bool unlocked = true,
    FakePresenceScenario scenario = FakePresenceScenario.foundOne,
    List<PresenceCandidate>? candidates,
    bool gatewayAvailable = true,
  }) async {
    AppConfig.setPresenceOverrideForTest(true);
    final scanner = FakePresenceScanner(scenario: scenario);
    final gateway = FakePresenceGateway(
      candidates: candidates ?? [cand('l1')],
      available: gatewayAvailable,
    );
    final container = ProviderContainer(
      overrides: [
        presenceScannerProvider.overrideWithValue(scanner),
        presenceApiGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await container
        .read(presencePreferencesProvider.notifier)
        .setNearbyDiscovery(discovery);
    final money = container.read(moneyAccessProvider);
    if (unlocked) money.finishUnlock(money.beginUnlock());
    final controller = NearbyPresenceController(
      container.read,
      scanner: scanner,
      gateway: gateway,
      tuning: PresenceTuning.fast,
    );
    return Rig._(container, controller, scanner, gateway);
  }

  void dispose() {
    controller.dispose();
    container.dispose();
    AppConfig.setPresenceOverrideForTest(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('§B challenge/resolve binding', () {
    test(
      'challenge carries challengeId and nonce as SEPARATE fields',
      () async {
        final rig = await Rig.create();
        addTearDown(rig.dispose);
        await rig.controller.requestScan();

        final challenge = await rig.gateway.requestChallenge();
        expect(challenge.challengeId, isNotEmpty);
        expect(challenge.nonce, isNotEmpty);
        expect(challenge.challengeId, isNot(challenge.nonce));
      },
    );

    test('resolve sends challengeId AND the nonce it was issued', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      await rig.controller.requestScan();

      expect(rig.gateway.resolveRequests, hasLength(1));
      final body = rig.gateway.resolveRequests.single;
      expect(body['challengeId'], isNotNull);
      expect(body['nonce'], isNotNull);
      // The old opaque-token names must be gone from the wire.
      expect(body.containsKey('token'), isFalse);
      expect(body.containsKey('challengeToken'), isFalse);
    });

    test('expiry is represented, never inferred as "valid forever"', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      final challenge = await rig.gateway.requestChallenge();
      expect(challenge.expiresAt.isAfter(DateTime.now()), isTrue);
    });
  });

  group('§B observation and GPS wire names', () {
    test('observation wire keys match the backend contract exactly', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      await rig.controller.requestScan();

      final obs = (rig.gateway.resolveRequests.single['observations'] as List)
          .cast<Map<String, dynamic>>();
      expect(obs, isNotEmpty);
      for (final o in obs) {
        expect(o.keys.toSet(), {
          'beaconKey',
          'rssiBucket',
          'sampleCount',
          'observedAt',
        });
        expect(['STRONG', 'NEAR', 'FAR'], contains(o['rssiBucket']));
      }
      // No raw payload, no continuous sample stream, no invented frameType.
      for (final o in obs) {
        expect(o.containsKey('rssi'), isFalse);
        expect(o.containsKey('frameType'), isFalse);
        expect(o.containsKey('samples'), isFalse);
      }
    });

    test('GPS uses lat/lng/accuracyM when supplied', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      await rig.controller.requestScan();
      final gps = rig.gateway.resolveRequests.single['gps'];
      if (gps != null) {
        expect((gps as Map).keys.toSet(), {'lat', 'lng', 'accuracyM'});
      }
    });
  });

  group('§B candidate response', () {
    test('parses every documented field and invents none', () {
      final c = PresenceCandidate.fromJson({
        'locationId': 'loc-1',
        'businessId': 'biz-1',
        'businessName': 'Azaman Mart',
        'branchName': 'Osu',
        'logoUrl': 'https://cdn/l.png',
        'floor': '2',
        'zone': 'Food court',
        'proximityHint': 'near',
        'storefrontMode': 'CATALOGUE_AND_PAYMENT',
        'storefrontRoute': '/business/biz-1',
        'gpsCorroboration': true,
      });
      expect(c.locationId, 'loc-1');
      expect(c.businessId, 'biz-1');
      expect(c.businessName, 'Azaman Mart');
      expect(c.branchName, 'Osu');
      expect(c.logoUrl, 'https://cdn/l.png');
      expect(c.floor, '2');
      expect(c.zone, 'Food court');
      expect(c.proximityHint, 'near');
      expect(c.storefrontMode, StorefrontMode.catalogueAndPayment);
      expect(c.storefrontRoute, '/business/biz-1');
      expect(c.gpsCorroboration, isTrue);
    });

    test('no invented verified field', () {
      final c = PresenceCandidate.fromJson({'locationId': 'x'});
      expect(c.toString().contains('verified'), isFalse);
    });
  });

  group('§B storefront modes', () {
    test('all three documented modes parse', () {
      expect(
        StorefrontMode.fromWire('LISTING_ONLY'),
        StorefrontMode.listingOnly,
      );
      expect(
        StorefrontMode.fromWire('CATALOGUE_AND_PAYMENT'),
        StorefrontMode.catalogueAndPayment,
      );
      expect(
        StorefrontMode.fromWire('PAYMENT_ONLY'),
        StorefrontMode.paymentOnly,
      );
    });

    test('PAYMENT_ONLY has no payable surface', () {
      expect(StorefrontMode.paymentOnly.isPayableHere, isFalse);
    });

    test('unknown mode never becomes a payable mode', () {
      expect(StorefrontMode.fromWire('WHATEVER').isPayableHere, isFalse);
    });
  });

  group('§B storefront route safety', () {
    test('absolute and scheme URLs are refused', () {
      expect(safeStorefrontRoute('https://evil.example/x'), isNull);
      expect(safeStorefrontRoute('//evil.example'), isNull);
      expect(safeStorefrontRoute('javascript:alert(1)'), isNull);
    });

    test('in-app route is accepted, traversal refused', () {
      expect(safeStorefrontRoute('/business/biz-1'), '/business/biz-1');
      expect(safeStorefrontRoute('/business/../admin'), isNull);
    });
  });

  group('§C event vocabulary', () {
    test('only the seven server event names exist', () {
      expect(PresenceEventType.values.map((e) => e.wireName).toSet(), {
        'BEACON_OBSERVED',
        'PRESENCE_RESOLVED',
        'STOREFRONT_CANDIDATE_SHOWN',
        'STOREFRONT_SELECTED',
        'STOREFRONT_DISMISSED',
        'STOREFRONT_OPENED',
        'UNKNOWN_BEACON_OBSERVED',
      });
    });

    test(
      'a customer scan emits only server events, no local diagnostics',
      () async {
        final rig = await Rig.create();
        addTearDown(rig.dispose);
        final seen = <PresenceEvent>[];
        rig.controller.onCustomerEvent = seen.add;
        final diag = <PresenceLocalDiagnostic>[];
        rig.controller.onLocalDiagnostic = diag.add;

        await rig.controller.requestScan();

        expect(seen, isNotEmpty);
        for (final e in seen) {
          expect(PresenceEventType.values, contains(e.type));
        }
        // Local diagnostics stayed local.
        expect(diag, isNotEmpty);
      },
    );

    test('worker test emits no customer events at all', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      final seen = <PresenceEvent>[];
      rig.controller.onCustomerEvent = seen.add;

      await rig.controller.runWorkerTest();
      expect(seen, isEmpty);
    });
  });

  group('§D preferences and consent', () {
    test('wire names are nearbyDiscovery/notifications/personalisation', () {
      const p = ServerPresencePreferences(
        nearbyDiscovery: true,
        notifications: false,
        personalisation: true,
      );
      final wire = p.toJson();
      expect(wire.containsKey('nearbyDiscovery'), isTrue);
      expect(wire.containsKey('notifications'), isTrue);
      expect(wire.containsKey('personalisation'), isTrue);
      // The old local name must not leak onto the wire.
      expect(wire.containsKey('presenceNotifications'), isFalse);
      expect(wire['notifications'], isFalse);
    });

    test('enabling requires consent version and timestamp', () {
      final p = ServerPresencePreferences(
        nearbyDiscovery: true,
        notifications: false,
        personalisation: false,
        consentVersion: 1,
        consentedAt: DateTime.utc(2026, 11, 8),
      );
      final wire = p.toJson();
      expect(wire['consentVersion'], 1);
      expect(wire['consentedAt'], isNotNull);
    });

    test('enabled without consent is not submittable', () {
      const p = ServerPresencePreferences(
        nearbyDiscovery: true,
        notifications: false,
        personalisation: false,
      );
      expect(p.hasConsent, isFalse);
    });
  });

  group('§E triggers', () {
    testWidgets('Home mount triggers a scan when eligible', (tester) async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      final t = NearbyScanTriggers(controller: rig.controller);
      t.onHomeMounted();
      // Drive a real frame so the deferred post-frame trigger actually runs.
      tester.binding.handleBeginFrame(Duration.zero);
      tester.binding.handleDrawFrame();
      await tester.pump(const Duration(milliseconds: 120));
      expect(rig.scanner.scanCount, greaterThan(0));
      t.dispose();
    });

    test('marketplace entry triggers a scan when eligible', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      NearbyScanTriggers(controller: rig.controller).onMarketplaceEntered();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rig.scanner.scanCount, greaterThan(0));
    });

    test('pull-to-refresh triggers an explicit scan', () async {
      final rig = await Rig.create();
      addTearDown(rig.dispose);
      await NearbyScanTriggers(controller: rig.controller).onPullToRefresh();
      expect(rig.scanner.scanCount, greaterThan(0));
    });

    test('discovery OFF means no trigger ever scans', () async {
      final rig = await Rig.create(discovery: false);
      addTearDown(rig.dispose);
      final t = NearbyScanTriggers(controller: rig.controller);
      t.onHomeMounted();
      t.onMarketplaceEntered();
      await t.onPullToRefresh();
      await Future<void>.delayed(Duration.zero);
      expect(rig.scanner.scanCount, 0);
      t.dispose();
    });

    test('locked app means no trigger scans', () async {
      final rig = await Rig.create(unlocked: false);
      addTearDown(rig.dispose);
      final t = NearbyScanTriggers(controller: rig.controller);
      t.onHomeMounted();
      t.onMarketplaceEntered();
      await t.onPullToRefresh();
      await Future<void>.delayed(Duration.zero);
      expect(rig.scanner.scanCount, 0);
      t.dispose();
    });

    test(
      'resume is debounced: a second resume inside the window is ignored',
      () async {
        final rig = await Rig.create();
        addTearDown(rig.dispose);
        var now = DateTime.utc(2026, 1, 1, 12);
        final t = NearbyScanTriggers(
          controller: rig.controller,
          resumeDebounce: const Duration(seconds: 2),
          clock: () => now,
        );
        expect(t.onResumed(), isTrue);
        now = now.add(const Duration(milliseconds: 500));
        expect(t.onResumed(), isFalse);
        now = now.add(const Duration(seconds: 3));
        expect(t.onResumed(), isTrue);
        t.dispose();
      },
    );

    test('triggers still respect the controller throttle', () async {
      final rig = await Rig.create(scenario: FakePresenceScenario.none);
      addTearDown(rig.dispose);
      final t = NearbyScanTriggers(controller: rig.controller);
      await t.onPullToRefresh();
      await t.onPullToRefresh();
      await t.onPullToRefresh();
      // PresenceTuning.fast minimum interval is 40ms — these run inside it.
      expect(rig.scanner.scanCount, lessThanOrEqualTo(1));
      t.dispose();
    });
  });

  group('§F build gate vs server flag', () {
    test(
      'build gate OFF makes the feature invisible and issues no request',
      () async {
        final rig = await Rig.create();
        addTearDown(rig.dispose);
        AppConfig.setPresenceOverrideForTest(false);
        expect(rig.controller.isFeatureVisible, isFalse);
        await rig.controller.requestScan();
        expect(rig.scanner.scanCount, 0);
        expect(rig.gateway.challengeCalls, 0);
      },
    );

    test('server unavailable never fabricates merchants', () async {
      final rig = await Rig.create(gatewayAvailable: false);
      addTearDown(rig.dispose);
      await rig.controller.requestScan();
      expect(rig.controller.state, isA<PresenceBlocked>());
      expect(rig.gateway.challengeCalls, 0);
    });

    test('the build gate is documented as NOT the server flag', () {
      final src = File('lib/config.dart').readAsStringSync();
      expect(src.contains('presenceApiBuildEnabled'), isTrue);
      expect(src.contains('GlobalSettings'), isTrue);
    });
  });

  group('§A/§I platform declarations', () {
    test('manifest has no premature neverForLocation attribute', () {
      final xml = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(xml.contains('usesPermissionFlags'), isFalse);
      expect(xml.contains('android.permission.BLUETOOTH_SCAN'), isTrue);
      expect(xml.contains('android:maxSdkVersion="30"'), isTrue);
    });

    test('no background location, no BLE plugin', () {
      final xml = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(xml.contains('ACCESS_BACKGROUND_LOCATION'), isFalse);
      final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
      for (final banned in ['flutter_blue', 'beacon', 'bluetooth_low_energy']) {
        expect(pubspec.contains(banned), isFalse, reason: banned);
      }
    });
  });
}
