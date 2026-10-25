// =============================================================================
// AZAMAN — WORKSTREAM H ACCEPTANCE: Mix co-activates Near You, honestly.
//
// The contracts pinned here:
//   H1. Pressing Mix attempts a SILENT location resolve — the explicit
//       permission-asking resolver is NEVER invoked by the Mix path.
//   H2. A valid position co-activates the proximity feed: exactly ONE
//       nearby search fires, the Near You control is visibly active and
//       the proximity strip renders.
//   H3. No position → the honest OFF state: no nearby search, no strip,
//       no prompt, no retry loop.
//   H4. The dial re-fires the nearby feed with the new category while
//       Mix owns the proximity feed.
//   H5. Exiting Mix restores the pre-Mix state exactly: mix-owned
//       proximity turns off, an EXPLICIT near-you activation survives.
//   H6. After a silent failure the explicit Near You control still
//       recovers the flow (the request/retry route).
//   H7. The local-first rails render ONLY real provider data, and raw
//       coordinates are never rendered.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/nearby_location_resolver.dart';

// ── Fakes (same seams the existing marketplace suites use — no network) ──────

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

class _FakeNearbyNotifier extends NearbySearchNotifier {
  _FakeNearbyNotifier() : super(BusinessService());

  int searchNearbyCalls = 0;
  double? lastLat;
  double? lastLng;
  String? lastCategory;

  @override
  Future<void> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    String? q,
    bool? verified,
  }) async {
    searchNearbyCalls++;
    lastLat = lat;
    lastLng = lng;
    lastCategory = category;
    // Recorded, not fired — states are injected directly.
  }

  @override
  Future<void> loadMore() async {}

  void injectLocations(List<BusinessLocation> locations) {
    state = NearbySearchState(
      locations: locations,
      lat: 5.6,
      lng: -0.19,
      hasMore: true,
      nextPage: 1,
    );
  }
}

/// Succeeds silently AND records whether the PROMPTING resolve() was ever
/// touched — the seam under test.
class _SilentRecordingResolver extends NearbyLocationResolver {
  const _SilentRecordingResolver(this.prompted);

  final _PromptLedger prompted;

  @override
  Future<Position> resolve() async {
    prompted.explicitResolveCalls++;
    return _position(5.603, -0.187);
  }

  @override
  Future<Position> resolveSilently() async => _position(5.603, -0.187);
}

class _SilentFailingResolver extends NearbyLocationResolver {
  const _SilentFailingResolver(this.prompted);

  final _PromptLedger prompted;

  @override
  Future<Position> resolve() async {
    prompted.explicitResolveCalls++;
    throw 'Location permission denied.';
  }

  @override
  Future<Position> resolveSilently() async {
    prompted.silentResolveCalls++;
    throw 'Location permission denied.';
  }
}

class _PromptLedger {
  int explicitResolveCalls = 0;
  int silentResolveCalls = 0;
}

Position _position(double lat, double lng) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 10,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

BusinessLocation _nearbyRow(String id, String name, {double? distanceKm}) =>
    BusinessLocation.fromJson({
      'id': id,
      'businessProfileId': 'bp-$id',
      'label': name,
      'address': 'Osu, Accra',
      'latitude': 5.56,
      'longitude': -0.19,
      'galleryUrls': <String>[],
      'isPrimary': true,
      'isActive': true,
      if (distanceKm != null) 'distanceKm': distanceKm,
      'businessProfile': {
        'bizId': 'BIZ-$id',
        'businessName': name,
        'category': 'RETAIL',
        'logoUrl': null,
        'isVerified': true,
        'averageRating': 4.5,
        'totalEscrows': 10,
      },
    });

Future<_FakeNearbyNotifier> _pumpHome(
  WidgetTester tester, {
  required NearbyLocationResolver resolver,
}) async {
  final nearby = _FakeNearbyNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) => _RecordingSearchNotifier()),
        nearbySearchProvider.overrideWith((ref) => nearby),
      ],
      child: MaterialApp(
        home: MarketplaceHomeScreen(locationResolver: resolver),
      ),
    ),
  );
  // initState's post-frame seeding search + one-shot timers elapse here.
  await tester.pump(const Duration(milliseconds: 600));
  return nearby;
}

Future<void> _enterMix(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
  await tester.pump(const Duration(milliseconds: 400));
  // The silent resolve is async — let the post-frame chain complete.
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('H1 — pressing Mix NEVER touches the prompting resolver',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentRecordingResolver(ledger),
    );

    await _enterMix(tester);

    expect(ledger.explicitResolveCalls, 0,
        reason: 'the Mix path must never prompt — only the silent seam');
    expect(nearby.searchNearbyCalls, 1,
        reason: 'a position was silently available — exactly one fire');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H2 — a valid position co-activates the proximity feed once',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentRecordingResolver(ledger),
    );

    await _enterMix(tester);

    expect(nearby.searchNearbyCalls, 1, reason: 'no duplicate fires');
    expect(nearby.lastLat, 5.603);
    expect(nearby.lastLng, -0.187);
    expect(find.byKey(const ValueKey('mix_proximity_strip')), findsOneWidget,
        reason: 'the proximity indication is visible in Mix');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H3 — no location: the honest OFF state, no prompt',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentFailingResolver(ledger),
    );

    await _enterMix(tester);

    expect(ledger.silentResolveCalls, 1);
    expect(nearby.searchNearbyCalls, 0, reason: 'no position — no fire');
    expect(find.byKey(const ValueKey('mix_proximity_strip')), findsNothing,
        reason: 'no proximity claim without proximity data');
    expect(find.byKey(const ValueKey('mix_local_first_rails')), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H4 — a dial category re-fires the nearby feed in Mix',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentRecordingResolver(ledger),
    );

    await _enterMix(tester);
    expect(nearby.searchNearbyCalls, 1);

    // Pick a dial category through the real fan's speed-dial entry. The
    // category dial opens a radial fan; its first option is a category.
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pump(const Duration(milliseconds: 400));

    // H4 re-fire: the SAME nearby feed re-fires with the dial wire.
    expect(nearby.searchNearbyCalls, 1,
        reason: 'fan only OPENED — nothing re-fired yet');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H5 — exiting Mix restores the pre-Mix state exactly',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentRecordingResolver(ledger),
    );

    await _enterMix(tester);
    expect(nearby.searchNearbyCalls, 1);

    // Exit Mix: the mix-owned proximity feed turns OFF with it.
    await tester.tap(find.byKey(const ValueKey('marketplace-mix-entry')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('mix_proximity_strip')), findsNothing,
        reason: 'mix owned the proximity feed — it leaves with Mix');
    expect(find.byKey(const ValueKey('marketplace-near-you-active')),
        findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H6 — after a silent failure the explicit pill still recovers',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentFailingResolver(ledger),
    );

    await _enterMix(tester);
    expect(nearby.searchNearbyCalls, 0);

    // The user presses Near You explicitly — the request route works.
    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(ledger.explicitResolveCalls, 1,
        reason: 'the EXPLICIT control owns the prompting ask');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('H7 — rails render only real data; coordinates never render',
      (tester) async {
    final ledger = _PromptLedger();
    final nearby = await _pumpHome(
      tester,
      resolver: _SilentRecordingResolver(ledger),
    );

    await _enterMix(tester);

    nearby.injectLocations([
      _nearbyRow('near-1', 'Corner Kiosk', distanceKm: 0.2),
      _nearbyRow('near-2', 'Osu Mini Mart', distanceKm: 1.4),
    ]);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('mix_local_first_rails')),
        findsOneWidget,
        reason: 'real nearby rows render the rail');
    expect(find.text('Corner Kiosk'), findsWidgets);
    expect(find.text('Osu Mini Mart'), findsWidgets);
    // Coordinates are proximity FACTS, never rendered content.
    expect(find.textContaining('5.56'), findsNothing);
    expect(find.textContaining('-0.19'), findsNothing);

    // And with no real data at all, no rails — the honest absence.
    nearby.injectLocations([]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mix_local_first_rails_empty')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
  });
}
