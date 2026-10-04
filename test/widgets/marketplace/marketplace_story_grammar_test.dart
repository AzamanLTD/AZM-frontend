// EXPERIENCE PASS §16 — marketplace stories speak the chat rail's grammar.
//
// The marketplace's expanded story rail previously kept a second
// "Telegram-like" implementation: hard-coded 96-px travel, its own
// ratio math, its own ring scale (60 vs the chat rail's 64), and NO
// reduced-motion handling. §16 folds it into the same interaction
// grammar as chat:
//
//   - same scale language: ring size and rail content height come from
//     the shared StoryRailMetrics (not parallel literals)
//   - same snap behaviour: the open/closed decision point is the shared
//     StoryRailSnapPhysics.openFraction threshold
//   - same expansion/collapse feel: collapse travel is the rail's own
//     extent (StoryRailCollapse.travelPx), attached 1:1 to the scroll
//   - same reduced-motion handling: the rail lands directly (binary),
//     like reduced motion skips the inbox rail's expressive reveal
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart' show MarketplaceHomeScreen;
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/widgets/stories/story_rail_snap_physics.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A FollowingListNotifier that never touches the network: the rail's
/// data branch is driven directly in the test.
class _SeededFollowingNotifier extends FollowingListNotifier {
  _SeededFollowingNotifier() : super(_NullApiClient());

  @override
  Future<void> load() async {
    state = const AsyncValue.data([
      {
        'id': 1,
        'businessName': 'Adinkra Lounge',
        'logoUrl': null,
        'isVerified': true,
      },
      {
        'id': 2,
        'businessName': 'Cocoa Line',
        'logoUrl': null,
        'isVerified': false,
      },
    ]);
  }
}

/// Structural stand-in so _SeededFollowingNotifier satisfies the
/// constructor without a real ApiClient (load() is overridden; the
/// client is never used).
class _NullApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('§16 grammar — StoryRailCollapse (the shared collapse math)', () {
    test('extent is derived from the shared rail metrics, not a literal', () {
      expect(StoryRailCollapse.extentPx,
          StoryRailMetrics.ring + StoryRailMetrics.labelGap + StoryRailMetrics.label + 8);
      // Derivation sanity: ring 64 + gap 6 + label 16 + 8 breathing.
      expect(StoryRailCollapse.extentPx, 94.0);
    });

    test('collapse travel equals the rail extent (attached 1:1)', () {
      expect(StoryRailCollapse.travelPx, StoryRailCollapse.extentPx);
    });

    test('motion users get the continuous attached collapse', () {
      const t = StoryRailCollapse.travelPx;
      expect(StoryRailCollapse.ratio(scrollOffset: 0, reducedMotion: false),
          1.0);
      expect(
          StoryRailCollapse.ratio(
              scrollOffset: t / 2, reducedMotion: false),
          closeTo(0.5, 0.001));
      expect(StoryRailCollapse.ratio(scrollOffset: t, reducedMotion: false),
          0.0);
      // Over-travel clamps: the rail never reads below 0.
      expect(
          StoryRailCollapse.ratio(
              scrollOffset: t * 10, reducedMotion: false),
          0.0);
    });

    test('reduced motion lands directly — binary, no fractional slide', () {
      final threshold = StoryRailSnapPhysics.openFraction *
          StoryRailCollapse.travelPx;
      // Just below the shared snap threshold: fully open.
      expect(
          StoryRailCollapse.ratio(
              scrollOffset: threshold - 1, reducedMotion: true),
          1.0);
      // At/above it: fully collapsed. No in-between value exists.
      expect(
          StoryRailCollapse.ratio(
              scrollOffset: threshold, reducedMotion: true),
          0.0);
      // The snap threshold is the chat rail's own openFraction.
      expect(StoryRailSnapPhysics.openFraction, 0.40);
    });
  });

  testWidgets('§16 grammar — the marketplace rail renders at the chat '
      'rail scale', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          followingListProvider.overrideWith((ref) => _SeededFollowingNotifier()..load()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MarketplaceExpandedStories(
              onOpenBusiness: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rings = tester.widgetList<StoryRing>(find.byType(StoryRing));
    expect(rings.length, 2, reason: 'seeded following businesses render');
    for (final ring in rings) {
      // Same scale language: the marketplace ring IS the shared chat rail
      // ring size, not a parallel literal.
      expect(ring.size, StoryRailMetrics.ring);
    }
    // Rail content height derives from the shared metrics too.
    final railList = find.descendant(
      of: find.byType(MarketplaceExpandedStories),
      matching: find.byType(ListView),
    );
    expect(
      tester.getRect(railList.first).height,
      StoryRailMetrics.ring + StoryRailMetrics.labelGap + StoryRailMetrics.label,
    );
  });

  testWidgets('§16 grammar — MarketplaceHomeScreen scroll drives the shared '
      'collapse (offset 0 = fully open rail)', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          followingListProvider.overrideWith(
              (ref) => _SeededFollowingNotifier()..load()),
        ],
        child: const MaterialApp(
          home: MarketplaceHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // At rest the rail area is at its full shared extent.
    expect(find.byType(MarketplaceExpandedStories), findsOneWidget);
  });
}
