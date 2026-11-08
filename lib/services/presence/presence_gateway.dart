// lib/services/presence/presence_gateway.dart
// =============================================================================
// AZAMAN — PRESENCE API GATEWAY (typed, backend contract from Part 6.3)
//
// This file defines the CLIENT-SIDE contract only. No backend route is added
// by this wave, so the production implementation is switched OFF behind
// AppConfig.presenceEnabled (mirroring the existing billsApiEnabled gate).
//
// THREE RULES THIS FILE ENFORCES:
//   1. When the backend endpoints are not deployed, the feature is
//      UNAVAILABLE — it throws PresenceUnavailableException and the UI stays
//      invisible. It must never fall back to fabricated candidate stores in a
//      production build.
//   2. A presence token is EVIDENCE OF PROXIMITY, never payment authority.
//      Nothing here can authorise a charge, and the client must not treat a
//      resolved candidate as a paid/entitled state.
//   3. Candidate identity comes from the SERVER. The client never invents a
//      merchant name, verification badge or storefront mode.
//
// Fakes live in FakePresenceGateway and are only wired by tests, the demo
// harness and the worker-test simulation.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';

import 'beacon_key.dart';
import 'presence_models.dart';

/// Thrown when the presence backend is not available in this build.
class PresenceUnavailableException implements Exception {
  final String reason;
  const PresenceUnavailableException([
    this.reason = 'presence backend unavailable',
  ]);
  @override
  String toString() => 'PresenceUnavailableException: $reason';
}

// ── Wire models ─────────────────────────────────────────────────────────────

/// How a resolved branch may be entered by the customer.
enum StorefrontMode {
  /// A published storefront exists — the customer may open it.
  published,

  /// Merchant accepts presence visits but has no storefront to show.
  none;

  static StorefrontMode fromWire(String? raw) =>
      (raw ?? '').toUpperCase() == 'PUBLISHED'
      ? StorefrontMode.published
      : StorefrontMode.none;
}

/// One eligible branch the server matched to the observations.
class PresenceCandidate {
  final String branchId;
  final String merchantName;
  final String branchName;
  final StorefrontMode storefrontMode;
  final ProximityBucket proximity;
  final String? logoUrl;
  final bool verified;

  const PresenceCandidate({
    required this.branchId,
    required this.merchantName,
    required this.branchName,
    required this.storefrontMode,
    required this.proximity,
    this.logoUrl,
    this.verified = false,
  });

  factory PresenceCandidate.fromJson(Map<String, dynamic> json) =>
      PresenceCandidate(
        branchId: '${json['branchId'] ?? ''}',
        merchantName: '${json['merchantName'] ?? ''}',
        branchName: '${json['branchName'] ?? ''}',
        storefrontMode: StorefrontMode.fromWire(
          json['storefrontMode'] as String?,
        ),
        proximity: switch ('${json['proximity'] ?? 'far'}'.toLowerCase()) {
          'strong' => ProximityBucket.strong,
          'near' => ProximityBucket.near,
          _ => ProximityBucket.far,
        },
        logoUrl: json['logoUrl'] as String?,
        verified: json['verified'] == true,
      );
}

/// General-location corroboration. Optional; never a replacement for
/// Bluetooth and never a payment authorisation.
class PresenceGpsCorroboration {
  final double latitude;
  final double longitude;
  final double? accuracyMetres;

  const PresenceGpsCorroboration({
    required this.latitude,
    required this.longitude,
    this.accuracyMetres,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (accuracyMetres != null) 'accuracyMetres': accuracyMetres,
  };
}

class PresenceChallenge {
  final String token;
  final DateTime expiresAt;

  const PresenceChallenge({required this.token, required this.expiresAt});

  factory PresenceChallenge.fromJson(Map<String, dynamic> json) =>
      PresenceChallenge(
        token: '${json['token'] ?? ''}',
        expiresAt:
            DateTime.tryParse('${json['expiresAt'] ?? ''}') ??
            DateTime.now().add(const Duration(minutes: 2)),
      );
}

class PresenceResolveResult {
  final List<PresenceCandidate> candidates;

  const PresenceResolveResult(this.candidates);

  bool get isEmpty => candidates.isEmpty;
}

/// The event vocabulary this wave CREATES but does not upload.
///
/// Only fake/test events exist in this wave: `isTestEvent` is forced true by
/// every constructor path in the client. Raw packets and continuous RSSI
/// sample streams are never represented here at all — there is no field for
/// them, which is the strongest form of "we cannot accidentally upload it".
enum PresenceEventType {
  scanStarted('SCAN_STARTED'),
  scanCompleted('SCAN_COMPLETED'),
  scanThrottled('SCAN_THROTTLED'),
  candidateShown('CANDIDATE_SHOWN'),
  candidateChosen('CANDIDATE_CHOSEN'),
  candidateDismissed('CANDIDATE_DISMISSED'),
  scanFailed('SCAN_FAILED'),
  workerTestRun('WORKER_TEST_RUN');

  const PresenceEventType(this.wireName);
  final String wireName;
}

class PresenceEvent {
  final PresenceEventType type;
  final DateTime occurredAt;
  final String? branchId;

  /// Always true in this wave. The field exists so a future server-side
  /// ingestion path can separate test traffic from production traffic
  /// without guessing.
  final bool isTestEvent = true;

  PresenceEvent({required this.type, required this.occurredAt, this.branchId});

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'isTestEvent': isTestEvent,
    if (branchId != null) 'branchId': branchId,
  };
}

// ── The seam ────────────────────────────────────────────────────────────────

abstract class PresenceApiGateway {
  /// True when a real backend is reachable in this build. The controller
  /// must not render presence UI when this is false.
  bool get isAvailable;

  Future<PresenceChallenge> requestChallenge();

  Future<PresenceResolveResult> resolve({
    required String challengeToken,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  });

  Future<void> submitEvents(List<PresenceEvent> events);

  Future<PresencePreferences> fetchPreferences();
}

/// Production gateway. Fails CLOSED when the API is not enabled.
class HttpPresenceGateway implements PresenceApiGateway {
  HttpPresenceGateway(this._client);

  final ApiClient _client;

  @override
  bool get isAvailable => AppConfig.presenceEnabled;

  void _requireAvailable() {
    if (!isAvailable) {
      throw const PresenceUnavailableException(
        'Presence API is not enabled in this build (--dart-define=PRESENCE_API=true).',
      );
    }
  }

  @override
  Future<PresenceChallenge> requestChallenge() async {
    _requireAvailable();
    final res = await _client.post('/presence/challenge', const {});
    return PresenceChallenge.fromJson(_decode(res));
  }

  @override
  Future<PresenceResolveResult> resolve({
    required String challengeToken,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  }) async {
    _requireAvailable();
    // The wire carries the CANONICAL KEY only. No frame struct, no raw
    // packet, no sample stream.
    final body = <String, dynamic>{
      'challengeToken': challengeToken,
      'observations': [
        for (final o in observations)
          {
            'beaconKey': canonicalBeaconKey(o.beaconKey) ?? o.beaconKey,
            'frameType': o.frameType.wireName,
            'rssi': o.rssi,
            'samples': o.sampleCount,
          },
      ],
      if (gps != null) 'gps': gps.toJson(),
    };
    final res = await _client.post('/presence/resolve', body);
    final decoded = _decode(res);
    final raw = (decoded['candidates'] as List?) ?? const [];
    return PresenceResolveResult([
      for (final c in raw)
        PresenceCandidate.fromJson(Map<String, dynamic>.from(c as Map)),
    ]);
  }

  @override
  Future<void> submitEvents(List<PresenceEvent> events) async {
    _requireAvailable();
    if (events.isEmpty) return;
    await _client.post('/presence/events', {
      'events': [for (final e in events) e.toJson()],
    });
  }

  @override
  Future<PresencePreferences> fetchPreferences() async {
    _requireAvailable();
    final res = await _client.get('/presence/preferences');
    return PresencePreferences.fromJson(_decode(res));
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 404) {
      throw const PresenceUnavailableException('presence route not deployed');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PresenceUnavailableException(
        'presence call failed (${res.statusCode})',
      );
    }
    final parsed = jsonDecode(res.body);
    if (parsed is! Map) {
      throw const PresenceUnavailableException('malformed presence payload');
    }
    final map = Map<String, dynamic>.from(parsed);
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }
}

/// Scripted gateway for tests, the demo harness and the worker simulation.
///
/// This type is NEVER wired as the production provider — see
/// `presenceApiGatewayProvider` below, which returns the HTTP gateway.
class FakePresenceGateway implements PresenceApiGateway {
  FakePresenceGateway({
    this.candidates = const [],
    this.available = true,
    this.challengeFails = false,
  });

  List<PresenceCandidate> candidates;
  bool available;
  bool challengeFails;

  int challengeCalls = 0;
  int resolveCalls = 0;
  final List<List<BeaconObservation>> resolveCallsWith =
      <List<BeaconObservation>>[];
  final List<List<PresenceEvent>> submittedEvents = <List<PresenceEvent>>[];
  PresencePreferences preferences = PresencePreferences.allOff;

  @override
  bool get isAvailable => available;

  @override
  Future<PresenceChallenge> requestChallenge() async {
    challengeCalls += 1;
    if (!available || challengeFails) {
      throw const PresenceUnavailableException('fake gateway unavailable');
    }
    return PresenceChallenge(
      token: 'fake-challenge-$challengeCalls',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  @override
  Future<PresenceResolveResult> resolve({
    required String challengeToken,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  }) async {
    resolveCalls += 1;
    resolveCallsWith.add(List<BeaconObservation>.from(observations));
    if (!available || challengeFails) {
      throw const PresenceUnavailableException('fake gateway unavailable');
    }
    return PresenceResolveResult(List<PresenceCandidate>.from(candidates));
  }

  @override
  Future<void> submitEvents(List<PresenceEvent> events) async {
    submittedEvents.add(List<PresenceEvent>.from(events));
  }

  @override
  Future<PresencePreferences> fetchPreferences() async => preferences;
}

/// The production provider: always the HTTP gateway. Fakes are injected by
/// overriding this provider in tests — never by changing this default.
final presenceApiGatewayProvider = Provider<PresenceApiGateway>((ref) {
  return HttpPresenceGateway(ref.watch(apiClientProvider));
});
