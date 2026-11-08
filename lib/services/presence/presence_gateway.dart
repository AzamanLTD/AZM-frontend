// lib/services/presence/presence_gateway.dart
// =============================================================================
// AZAMAN — PRESENCE API GATEWAY (typed, Part 6.3 backend contract)
//
// This file defines the CLIENT-SIDE contract only. No backend route is added
// by this wave, so the production implementation is switched OFF behind the
// client build gate (AppConfig.presenceApiBuildEnabled).
//
// FOUR RULES THIS FILE ENFORCES:
//   1. When the backend endpoints are not deployed, the feature is
//      UNAVAILABLE — it throws PresenceUnavailableException and the UI stays
//      invisible. It must never fall back to fabricated candidate stores in a
//      production build.
//   2. A presence token is SUPPLEMENTARY CONTEXT, never payment authority.
//      Nothing here can authorise a charge, bypass step-up authentication, or
//      imply that a transaction succeeded.
//   3. Candidate identity comes from the SERVER. The client never invents a
//      merchant name, verification badge or storefront mode.
//   4. A server-supplied `storefrontRoute` is a HINT, not navigation. It is
//      validated against the app's own permitted routes before use, so a
//      backend string can never become unrestricted navigation.
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

// ── Storefront mode ─────────────────────────────────────────────────────────

enum StorefrontMode {
  /// Approved listing only. The customer sees the branch's listing
  /// experience; there is no payment surface.
  listingOnly('LISTING_ONLY'),

  /// The branch's existing catalogue experience (browse and order).
  catalogueAndPayment('CATALOGUE_AND_PAYMENT'),

  /// Payment-only branch. NO branch-payment intent exists yet, so this
  /// renders the honest coming-soon state. It must never fabricate an
  /// amount-entry screen.
  paymentOnly('PAYMENT_ONLY');

  const StorefrontMode(this.wireName);
  final String wireName;

  /// True only where a genuine client payment surface already exists. The
  /// retail pilot has none for PAYMENT_ONLY, so it must never render one.
  bool get isPayableHere => this == StorefrontMode.catalogueAndPayment;

  static StorefrontMode fromWire(String? raw) =>
      switch ((raw ?? '').toUpperCase()) {
        'CATALOGUE_AND_PAYMENT' => StorefrontMode.catalogueAndPayment,
        'PAYMENT_ONLY' => StorefrontMode.paymentOnly,
        _ => StorefrontMode.listingOnly,
      };
}

// ── Candidate ───────────────────────────────────────────────────────────────

/// One eligible branch the server matched to the observations.
///
/// Every field is rendered as supplied. There is deliberately NO `verified`
/// field: the backend only returns branches belonging to verified businesses,
/// so the client has no separate verification signal and must not invent one.
class PresenceCandidate {
  final String locationId;
  final String businessId;
  final String businessName;
  final String branchName;
  final String? logoUrl;
  final String? floor;
  final String? zone;
  final String? proximityHint;
  final StorefrontMode storefrontMode;
  final String? storefrontRoute;
  final bool gpsCorroboration;

  const PresenceCandidate({
    required this.locationId,
    required this.businessId,
    required this.businessName,
    required this.branchName,
    required this.storefrontMode,
    this.logoUrl,
    this.floor,
    this.zone,
    this.proximityHint,
    this.storefrontRoute,
    this.gpsCorroboration = false,
  });

  factory PresenceCandidate.fromJson(Map<String, dynamic> json) =>
      PresenceCandidate(
        locationId: '${json['locationId'] ?? ''}',
        businessId: '${json['businessId'] ?? ''}',
        businessName: '${json['businessName'] ?? ''}',
        branchName: '${json['branchName'] ?? ''}',
        logoUrl: json['logoUrl'] as String?,
        floor: json['floor'] as String?,
        zone: json['zone'] as String?,
        proximityHint: json['proximityHint'] as String?,
        storefrontMode: StorefrontMode.fromWire(
          json['storefrontMode'] as String?,
        ),
        storefrontRoute: json['storefrontRoute'] as String?,
        gpsCorroboration: json['gpsCorroboration'] == true,
      );
}

// ── GPS ─────────────────────────────────────────────────────────────────────

/// General-location corroboration. Optional; never a replacement for
/// Bluetooth, never proof of indoor position, never a payment authorisation.
class PresenceGpsCorroboration {
  final double lat;
  final double lng;
  final double? accuracyM;

  const PresenceGpsCorroboration({
    required this.lat,
    required this.lng,
    this.accuracyM,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (accuracyM != null) 'accuracyM': accuracyM,
  };
}

// ── Challenge / resolve ─────────────────────────────────────────────────────

/// The issued challenge.
///
/// [nonce] is returned to the client ONCE and the server keeps only its HASH.
/// Resolving must therefore prove possession of that nonce — sending an
/// opaque [challengeId] alone proves nothing. The resolve request carries
/// both, and the server must verify `hash(nonce)` against the stored value
/// AND consume the challenge atomically (one successful resolve per
/// challenge) before any candidate is returned.
class PresenceChallenge {
  final String challengeId;
  final String nonce;
  final DateTime expiresAt;

  const PresenceChallenge({
    required this.challengeId,
    required this.nonce,
    required this.expiresAt,
  });

  factory PresenceChallenge.fromJson(Map<String, dynamic> json) =>
      PresenceChallenge(
        challengeId: '${json['challengeId'] ?? ''}',
        nonce: '${json['nonce'] ?? ''}',
        expiresAt:
            DateTime.tryParse('${json['expiresAt'] ?? ''}') ??
            DateTime.now().add(const Duration(minutes: 2)),
      );

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// The resolve result.
///
/// [presenceToken] is SHORT-LIVED SUPPLEMENTARY CONTEXT only: it never
/// authorises a payment, never bypasses step-up authentication, and never
/// implies that a transaction succeeded.
class PresenceResolveResult {
  final List<PresenceCandidate> candidates;
  final String? presenceToken;
  final DateTime? tokenExpiresAt;

  const PresenceResolveResult(
    this.candidates, {
    this.presenceToken,
    this.tokenExpiresAt,
  });

  bool get isEmpty => candidates.isEmpty;
}

// ── Server event contract ───────────────────────────────────────────────────

/// The SERVER event vocabulary. These are the only customer events this
/// client may submit.
///
/// Client-local diagnostics (scan started/completed/throttled/failed) are
/// deliberately NOT here: they stay on the device. There is also no
/// `isTestEvent` field, because the server contract does not define one —
/// worker-test scans simply never build a customer batch at all.
enum PresenceEventType {
  beaconObserved('BEACON_OBSERVED'),
  presenceResolved('PRESENCE_RESOLVED'),
  storefrontCandidateShown('STOREFRONT_CANDIDATE_SHOWN'),
  storefrontSelected('STOREFRONT_SELECTED'),
  storefrontDismissed('STOREFRONT_DISMISSED'),
  storefrontOpened('STOREFRONT_OPENED'),
  unknownBeaconObserved('UNKNOWN_BEACON_OBSERVED');

  const PresenceEventType(this.wireName);
  final String wireName;
}

/// One customer presence event.
///
/// Carries NO customer identity and NO merchant-visible personal data — the
/// backend derives authenticated identity and user pseudonyms itself.
class PresenceEvent {
  final PresenceEventType type;
  final DateTime occurredAt;
  final String? locationId;

  PresenceEvent({
    required this.type,
    required this.occurredAt,
    this.locationId,
  });

  /// Worker-test scans must never reach here. This assertion makes the
  /// invariant loud rather than silent if a caller ever gets it wrong.
  Map<String, dynamic> toJson() {
    assert(
      type != PresenceEventType.storefrontSelected ||
          (locationId != null && locationId!.isNotEmpty),
      'a selected storefront event must name the location',
    );
    return {
      'eventType': type.wireName,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      if (locationId != null) 'locationId': locationId,
    };
  }
}

/// The batch envelope. The server deduplicates per authenticated user on
/// `(eventType, occurredAt, locationId)`, so a retried batch is safe.
class PresenceEventBatch {
  final List<PresenceEvent> events;
  const PresenceEventBatch(this.events);

  bool get isEmpty => events.isEmpty;

  Map<String, dynamic> toJson() => {
    'events': events.map((e) => e.toJson()).toList(growable: false),
  };
}

// ── Route validation ────────────────────────────────────────────────────────

/// The ONLY route prefixes a server-supplied `storefrontRoute` may resolve to.
/// A backend string is data, never authority: anything outside this list is
/// rejected and the caller falls back to the client's own destination for the
/// storefront mode.
const List<String> _permittedStorefrontRoutePrefixes = <String>[
  '/biz/',
  '/business/',
  '/storefront/',
  '/marketplace/business/',
];

/// Returns [route] when it is a safe, in-app, relative Azaman route; otherwise
/// null. Rejects absolute URLs, schemes, protocol-relative forms, traversal
/// and anything outside the permitted prefixes.
String? safeStorefrontRoute(String? route) {
  if (route == null) return null;
  final r = route.trim();
  if (r.isEmpty || r.length > 512) return null;
  if (!r.startsWith('/')) return null; // absolute URL or scheme
  if (r.startsWith('//')) return null; // protocol-relative
  if (r.contains('..') || r.contains('\\')) return null;
  if (r.contains('://')) return null;
  for (final prefix in _permittedStorefrontRoutePrefixes) {
    if (r.startsWith(prefix)) return r;
  }
  return null;
}

// ── Preferences (server-persisted consent) ──────────────────────────────────

/// The server's preference record. Distinct from the LOCAL preference state,
/// and the only thing that authorises live customer event submission.
class ServerPresencePreferences {
  final bool nearbyDiscovery;
  final bool notifications;
  final bool personalisation;
  final int consentVersion;
  final DateTime? consentedAt;

  const ServerPresencePreferences({
    required this.nearbyDiscovery,
    required this.notifications,
    required this.personalisation,
    this.consentVersion = 0,
    this.consentedAt,
  });

  bool get hasConsent => consentedAt != null && consentVersion > 0;

  factory ServerPresencePreferences.fromJson(Map<String, dynamic> json) =>
      ServerPresencePreferences(
        nearbyDiscovery: json['nearbyDiscovery'] == true,
        notifications: json['notifications'] == true,
        personalisation: json['personalisation'] == true,
        consentVersion: (json['consentVersion'] as num?)?.toInt() ?? 0,
        consentedAt: DateTime.tryParse('${json['consentedAt'] ?? ''}'),
      );

  /// The wire body for an update. Enabling any preference REQUIRES a consent
  /// version and timestamp; the server rejects an enablement without them.
  Map<String, dynamic> toJson() => {
    'nearbyDiscovery': nearbyDiscovery,
    'notifications': notifications,
    'personalisation': personalisation,
    'consentVersion': consentVersion,
    if (consentedAt != null)
      'consentedAt': consentedAt!.toUtc().toIso8601String(),
  };
}

/// Mirror of the local preference switches onto the server wire names.
/// `presenceNotifications` locally IS the server's `notifications`.
ServerPresencePreferences serverPreferencesFromLocal(
  PresencePreferences local, {
  required int consentVersion,
  DateTime? consentedAt,
}) => ServerPresencePreferences(
  nearbyDiscovery: local.nearbyDiscovery,
  notifications: local.presenceNotifications,
  personalisation: local.personalisation,
  consentVersion: consentVersion,
  consentedAt: consentedAt,
);

// ── The seam ────────────────────────────────────────────────────────────────

abstract class PresenceApiGateway {
  /// True when a real backend is reachable in this build. The controller
  /// must not render presence UI when this is false.
  bool get isAvailable;

  Future<PresenceChallenge> requestChallenge();

  /// [nonce] proves possession of the challenge the server issued. The server
  /// verifies hash(nonce) and consumes the challenge atomically.
  Future<PresenceResolveResult> resolve({
    required String challengeId,
    required String nonce,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  });

  Future<void> submitEvents(PresenceEventBatch batch);

  Future<ServerPresencePreferences> fetchPreferences();

  Future<ServerPresencePreferences> savePreferences(
    ServerPresencePreferences preferences,
  );
}

/// Production gateway. Fails CLOSED when the build gate is off.
class HttpPresenceGateway implements PresenceApiGateway {
  HttpPresenceGateway(this._client);

  final ApiClient _client;

  @override
  bool get isAvailable => AppConfig.presenceApiBuildEnabled;

  void _requireAvailable() {
    if (!isAvailable) {
      throw const PresenceUnavailableException(
        'Presence API is not enabled in this build '
        '(--dart-define=PRESENCE_API=true).',
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
    required String challengeId,
    required String nonce,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  }) async {
    _requireAvailable();
    // The wire carries the CANONICAL KEY and a coarse bucket only. No frame
    // struct, no raw packet, no continuous RSSI stream — the model has no
    // field for them, which is the strongest form of "cannot upload it".
    final body = <String, dynamic>{
      'challengeId': challengeId,
      'nonce': nonce,
      'observations': [
        for (final o in observations)
          {
            'beaconKey': canonicalBeaconKey(o.beaconKey) ?? o.beaconKey,
            'rssiBucket': o.bucket.wireName,
            'sampleCount': o.sampleCount,
            'observedAt': o.lastSeenAt.toUtc().toIso8601String(),
          },
      ],
      if (gps != null) 'gps': gps.toJson(),
    };
    final res = await _client.post('/presence/resolve', body);
    final decoded = _decode(res);
    final raw = (decoded['candidates'] as List?) ?? const [];
    return PresenceResolveResult(
      [
        for (final c in raw)
          PresenceCandidate.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      presenceToken: decoded['presenceToken'] as String?,
      tokenExpiresAt: DateTime.tryParse('${decoded['tokenExpiresAt'] ?? ''}'),
    );
  }

  @override
  Future<void> submitEvents(PresenceEventBatch batch) async {
    _requireAvailable();
    if (batch.isEmpty) return;
    await _client.post('/presence/events', batch.toJson());
  }

  @override
  Future<ServerPresencePreferences> fetchPreferences() async {
    _requireAvailable();
    final res = await _client.get('/presence/preferences');
    return ServerPresencePreferences.fromJson(_decode(res));
  }

  @override
  Future<ServerPresencePreferences> savePreferences(
    ServerPresencePreferences preferences,
  ) async {
    _requireAvailable();
    final res = await _client.put(
      '/presence/preferences',
      preferences.toJson(),
    );
    return ServerPresencePreferences.fromJson(_decode(res));
  }

  Map<String, dynamic> _decode(http.Response res) {
    final parsed = jsonDecode(res.body);
    if (parsed is! Map) {
      throw const PresenceUnavailableException('malformed presence payload');
    }
    final map = Map<String, dynamic>.from(parsed);
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }
}

/// TEST / DEMO ONLY. Never wired into a production build: the provider below
/// returns the HTTP gateway, and this class is only constructed explicitly by
/// tests and the worker-test simulation.
class FakePresenceGateway implements PresenceApiGateway {
  FakePresenceGateway({
    List<PresenceCandidate>? candidates,
    this.available = true,
    this.presenceToken,
    this.challengeId = 'challenge-test',
    this.nonce = 'nonce-test-123',
    this.failResolve = false,
  }) : candidates = candidates ?? const <PresenceCandidate>[];

  final List<PresenceCandidate> candidates;

  final bool available;

  final String? presenceToken;
  final String challengeId;
  final String nonce;
  final bool failResolve;

  /// Resolve requests actually issued — proves binding and throttle tests.
  final List<Map<String, dynamic>> resolveRequests = <Map<String, dynamic>>[];
  int challengeCalls = 0;
  int resolveCalls = 0;
  final List<PresenceEventBatch> submittedBatches = <PresenceEventBatch>[];

  ServerPresencePreferences _prefs = const ServerPresencePreferences(
    nearbyDiscovery: false,
    notifications: false,
    personalisation: false,
  );

  @override
  bool get isAvailable => available;

  void _requireAvailable() {
    if (!available) {
      throw const PresenceUnavailableException('fake gateway unavailable');
    }
  }

  @override
  Future<PresenceChallenge> requestChallenge() async {
    _requireAvailable();
    challengeCalls += 1;
    return PresenceChallenge(
      challengeId: challengeId,
      nonce: nonce,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  @override
  Future<PresenceResolveResult> resolve({
    required String challengeId,
    required String nonce,
    required List<BeaconObservation> observations,
    PresenceGpsCorroboration? gps,
  }) async {
    _requireAvailable();
    resolveCalls += 1;
    resolveRequests.add({
      'challengeId': challengeId,
      'nonce': nonce,
      'observations': observations.map((o) => o.toWire()).toList(),
      if (gps != null) 'gps': gps.toJson(),
    });
    if (failResolve) {
      throw const PresenceUnavailableException('resolve failed');
    }
    return PresenceResolveResult(
      candidates,
      presenceToken: presenceToken,
      tokenExpiresAt: presenceToken == null
          ? null
          : DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> submitEvents(PresenceEventBatch batch) async {
    _requireAvailable();
    if (batch.isEmpty) return;
    submittedBatches.add(batch);
  }

  @override
  Future<ServerPresencePreferences> fetchPreferences() async {
    _requireAvailable();
    return _prefs;
  }

  @override
  Future<ServerPresencePreferences> savePreferences(
    ServerPresencePreferences preferences,
  ) async {
    _requireAvailable();
    _prefs = preferences;
    return _prefs;
  }
}

final presenceApiGatewayProvider = Provider<PresenceApiGateway>((ref) {
  final client = ref.watch(apiClientProvider);
  return HttpPresenceGateway(client);
});
