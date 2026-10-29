// =============================================================================
// AZAMAN — WORKSTREAM F follow-up regression: the stories rail EMPTY state
// must render at the SAME 94px rail grammar as the populated rail.
//
// The defect: _buildEmptyState stacked a 'Suggested businesses' heading
// (≈13px) + 6px gap + the 86px rail box + 4px breathing ≈ 108px inside the
// home screen's fixed 94px rail extent (OverflowBox) — a RenderFlex
// overflow of 18px, silently clipped at the bottom by the parent ClipRect.
//
// The fix: the empty state now carries exactly the populated rail's
// geometry (86px rail box + 4px breathing = 90 ≤ 94). The heading's
// explanatory value moved into a Semantics label — screen readers hear
// the honest guidance without it stealing rail geometry.
//
// Contracts pinned here:
//   1. No RenderFlex overflow when the empty state lays out inside the
//      home screen's exact 94px extent harness.
//   2. The empty rail's ListView renders at the SAME height as the
//      populated rail's (the shared StoryRailMetrics grammar).
//   3. The Browse affordance (the honest nudge) still renders and opens
//      the browse callback.
//   4. The guidance text is exposed to semantics — the explanation
//      survives the heading removal.
// =============================================================================

import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Following list that loads to the honest EMPTY set — no network.
class _EmptyFollowingNotifier extends FollowingListNotifier {
  _EmptyFollowingNotifier() : super(_NullApiClient());

  @override
  Future<void> load() async {
    state = const AsyncValue.data([]);
  }
}

/// Structural stand-in so the notifier satisfies its constructor without
/// a real ApiClient (load() is overridden; the client is never used).
class _NullApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The home screen's exact rail-extent harness: a fixed 94px slot with an
/// OverflowBox laying the child out at full extent, clipped — the same
/// geometry the marketplace home applies to MarketplaceExpandedStories.
Widget _railExtentHarness(Widget rail) => SizedBox(
  height: StoryRailCollapse.extentPx,
  width: double.infinity,
  child: ClipRect(
    child: OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: StoryRailCollapse.extentPx,
      maxHeight: StoryRailCollapse.extentPx,
      child: rail,
    ),
  ),
);

Future<void> _pumpEmptyRail(
  WidgetTester tester, {
  VoidCallback? onBrowsePressed,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        followingListProvider.overrideWith(
          (ref) => _EmptyFollowingNotifier()..load(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: _railExtentHarness(
            MarketplaceExpandedStories(
              onOpenBusiness: (_) {},
              onBrowsePressed: onBrowsePressed,
            ),
          ),
        ),
      ),
    ),
  );
  // Let the shimmer placeholders' animate interval pass once so the
  // layout settles before assertions.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('empty state lays out inside the 94px rail extent — no '
      'overflow', (tester) async {
    await _pumpEmptyRail(tester);

    // The regression: the old stacked heading overflowed this exact harness
    // by 18px. No exception may surface now.
    expect(
      tester.takeException(),
      isNull,
      reason:
          'the empty state must fit the same rail extent the '
          'populated rail fits',
    );
  });

  testWidgets('empty rail box renders at the SHARED rail metrics — same '
      'grammar as the populated rail', (tester) async {
    await _pumpEmptyRail(tester);

    final emptyList = find.descendant(
      of: find.byType(MarketplaceExpandedStories),
      matching: find.byType(ListView),
    );
    expect(emptyList, findsOneWidget);
    expect(
      tester.getRect(emptyList.first).height,
      StoryRailMetrics.ring +
          StoryRailMetrics.labelGap +
          StoryRailMetrics.label,
      reason:
          '§16 one scale language — the empty rail box IS the populated '
          'rail box height',
    );

    // The whole state fits the extent with the breathing room intact.
    final railRect = tester.getRect(find.byType(MarketplaceExpandedStories));
    expect(railRect.height, lessThanOrEqualTo(StoryRailCollapse.extentPx));
  });

  testWidgets('the honest nudge survives — the Browse affordance renders '
      'and fires its callback', (tester) async {
    var browsePressed = 0;
    await _pumpEmptyRail(tester, onBrowsePressed: () => browsePressed++);

    expect(find.text('Browse'), findsOneWidget);

    await tester.tap(find.text('Browse'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      browsePressed,
      1,
      reason: 'the empty state still routes the user to discovery',
    );
  });

  testWidgets('the guidance explanation lives in semantics — screen '
      'readers hear what the heading used to say', (tester) async {
    await _pumpEmptyRail(tester);

    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(
      find.byType(MarketplaceExpandedStories).first,
    );
    expect(
      node.label,
      contains('No followed businesses yet'),
      reason: 'the heading removal must not remove the explanation',
    );
    handle.dispose();
  });
}
